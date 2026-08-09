// social.ts — SocialDO Durable Object (#C3, #C4).
//
// Replaces the shared KV blobs ("users", "blocks", "cyphers", "live", "feed",
// "rooms") that every request read-modified-wrote — two concurrent writes
// routinely overwrote each other. A Durable Object serializes all writes and
// stores records individually:
//
//   user:<uid>     one record per user (profile, presence, friends, blocks,
//                  pushTokens, nowPlaying)
//   code:<CODE>    friend-code -> uid index
//   cyphers / live / feed / rooms   small bounded lists
//   idem:<key>     processed idempotency keys (offline-outbox replay, #C5)
//
// Realtime (#C3): clients open a WebSocket at /api/ws. Whenever social state
// changes, connected clients get {type:"changed"} (debounced) and re-pull the
// snapshot — same contract as polling, but push-driven. The DO uses WebSocket
// hibernation so idle sockets cost nothing.
//
// APNs fan-out: the DO never does network I/O to Apple. Mutations return
// `pushJobs` (token + payload) to the Worker router, which sends them and
// reports dead tokens back to POST /push/prune (#C9).

import { displayHandle, displayName, json, now, PRESENCE_WINDOW_MS, str } from "./util";

interface UserRecord {
  id: string;
  handle: string;
  displayName: string;
  code: string;
  activity: string;
  lastSeen: string;
  streak: number;
  friends: string[];
  pushTokens: string[];
  blocks: string[];
  nowPlaying: unknown | null;
}

interface PushJob { uid: string; token: string; payload: unknown }

const LOUD_ACTIVITY: Record<string, string> = {
  live: "is live now 🔴",
  smoking: "just sparked up 💨",
  hitting_bong: "is hitting the bong 🌬️",
  rolling_up: "is rolling up 🌿",
  in_cypher: "started a Cypher 🔄",
};

const MILESTONE_LINES: Record<string, string> = {
  roll_record: "set a new roll record 🏆",
  streak: "hit a new streak 🔥",
  champion: "crowned a new favorite 👑",
};

function seedRooms() {
  return [
    { id: "rm_general", name: "General", topic: "Anything goes 🌿", memberCount: 0, lastMessage: null, lastMessageAt: null, unread: 0 },
    { id: "rm_strains", name: "Strain Talk", topic: "Reviews & recs", memberCount: 0, lastMessage: null, lastMessageAt: null, unread: 0 },
    { id: "rm_growers", name: "Growers", topic: "Cultivation chat", memberCount: 0, lastMessage: null, lastMessageAt: null, unread: 0 },
    { id: "rm_sesh", name: "Sesh Lounge", topic: "Find a Cypher", memberCount: 0, lastMessage: null, lastMessageAt: null, unread: 0 },
  ];
}

export class SocialDO implements DurableObject {
  private state: DurableObjectState;

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  // ---- storage helpers -----------------------------------------------------

  private async user(uid: string): Promise<UserRecord | undefined> {
    return this.state.storage.get<UserRecord>(`user:${uid}`);
  }

  private async putUser(u: UserRecord): Promise<void> {
    if (u.code) {
      const key = `code:${u.code.toUpperCase()}`;
      const owner = await this.state.storage.get<string>(key);
      if (owner && owner !== u.id) {
        // Code already belongs to another uid — refuse the hijack.
        u.code = "";
      } else if (!owner) {
        await this.state.storage.put(key, u.id);
      }
    }
    await this.state.storage.put(`user:${u.id}`, u);
  }

  private async allUsers(): Promise<UserRecord[]> {
    const map = await this.state.storage.list<UserRecord>({ prefix: "user:" });
    return [...map.values()];
  }

  private async list<T>(key: string, fallback: T[]): Promise<T[]> {
    return (await this.state.storage.get<T[]>(key)) ?? fallback;
  }

  private async touch(uid: string, handle: string, name: string,
                      fields: Partial<UserRecord> = {}): Promise<UserRecord> {
    const prev = await this.user(uid);
    const rec: UserRecord = {
      id: uid,
      // Never persist a second-person placeholder ("@you" / "You") as this
      // user's identity — it is what every OTHER account sees.
      handle: displayHandle(handle || prev?.handle, uid),
      displayName: displayName(name || prev?.displayName, handle || prev?.handle, uid),
      code: (fields.code as string) || prev?.code || "",
      activity: fields.activity !== undefined ? (fields.activity as string) : (prev?.activity || "idle"),
      lastSeen: now(),
      streak: prev?.streak || 0,
      friends: prev?.friends || [],
      pushTokens: prev?.pushTokens || [],
      blocks: prev?.blocks || [],
      nowPlaying: fields.nowPlaying !== undefined ? fields.nowPlaying : (prev?.nowPlaying ?? null),
    };
    await this.putUser(rec);
    return rec;
  }

  // ---- room membership -------------------------------------------------------
  //
  // `memberCount` used to be seeded at 0 and never written again, so every room
  // in the app read "0 members" forever — including the room you were standing
  // in. Membership is now the set of uids that have opened or posted in a room.

  private static readonly MAX_ROOM_MEMBERS = 5000;

  /** Record `uid` as a member of `roomID`. Returns true if this was new. */
  private async joinRoom(roomID: string, uid: string): Promise<boolean> {
    if (!roomID || !uid) return false;
    const key = `rmem:${roomID}`;
    const members = await this.list<string>(key, []);
    if (members.includes(uid)) return false;
    members.push(uid);
    await this.state.storage.put(key,
      members.slice(-SocialDO.MAX_ROOM_MEMBERS));
    return true;
  }

  private async roomMemberCount(roomID: string): Promise<number> {
    return (await this.list<string>(`rmem:${roomID}`, [])).length;
  }

  private async pushFeed(event: unknown): Promise<void> {
    const feed = await this.list<unknown>("feed", []);
    feed.unshift(event);
    await this.state.storage.put("feed", feed.slice(0, 50));
  }

  // ---- realtime (#C3) --------------------------------------------------------

  /** Nudge all connected sockets that state changed (they re-pull /snapshot). */
  private broadcastChanged(): void {
    const msg = JSON.stringify({ type: "changed", at: now() });
    for (const ws of this.state.getWebSockets()) {
      try { ws.send(msg); } catch { /* socket already gone */ }
    }
    // (#C8) Bump the snapshot revision (the /snapshot ETag) without awaiting —
    // the DO's write coalescing keeps this cheap.
    void this.state.storage.get<number>("rev").then((rev) =>
      this.state.storage.put("rev", (rev ?? 0) + 1));
  }

  async webSocketMessage(ws: WebSocket, message: ArrayBuffer | string): Promise<void> {
    // Heartbeat from the client keeps presence fresh over the socket. The uid
    // comes from the tag attached at acceptWebSocket (verified identity), never
    // from the frame — a client can't forge someone else's presence.
    try {
      const data = JSON.parse(typeof message === "string" ? message : new TextDecoder().decode(message));
      if (data.type === "heartbeat") {
        const [uid] = this.state.getTags(ws);
        if (uid) {
          const u = await this.user(uid);
          if (u) { u.lastSeen = now(); await this.putUser(u); }
        }
        ws.send(JSON.stringify({ type: "pong", at: now() }));
      }
    } catch { /* ignore malformed frames */ }
  }

  async webSocketClose(): Promise<void> { /* hibernation API handles cleanup */ }

  // ---- idempotency (#C5) -----------------------------------------------------

  private async alreadyProcessed(key: string | null): Promise<boolean> {
    if (!key) return false;
    return !!(await this.state.storage.get(`idem:${key.slice(0, 128)}`));
  }

  /** Record an idempotency key AFTER the handler succeeded — a thrown handler
   *  must not swallow the client's retry. */
  private async markProcessed(key: string | null): Promise<void> {
    if (!key) return;
    await this.state.storage.put(`idem:${key.slice(0, 128)}`, Date.now());
    // Opportunistic cleanup of old keys (bounded scan).
    const old = await this.state.storage.list<number>({ prefix: "idem:", limit: 500 });
    const cutoff = Date.now() - 24 * 60 * 60 * 1000;
    const stale = [...old].filter(([, at]) => at < cutoff).map(([k2]) => k2);
    if (stale.length) await this.state.storage.delete(stale);
  }

  // ---- snapshot --------------------------------------------------------------

  private async snapshot(meID: string) {
    const me = await this.user(meID);
    const blocked = new Set(me?.blocks || []);
    const users = await this.allUsers();

    let rooms = await this.list<Record<string, unknown>>("rooms", []);
    if (rooms.length === 0) { rooms = seedRooms(); await this.state.storage.put("rooms", rooms); }
    // memberCount is derived, not stored on the room record, so it can't drift.
    rooms = await Promise.all(rooms.map(async (r) => ({
      ...r,
      memberCount: await this.roomMemberCount(str(r.id, 64)),
    })));

    const cyphers = await this.list<unknown>("cyphers", []);
    const live = await this.list<Record<string, unknown>>("live", []);
    const storedFeed = await this.list<Record<string, unknown>>("feed", []);

    const tnow = Date.now();
    const friendIDs = new Set(me?.friends || []);
    // The admin export (uid "admin", ADMIN_KEY-guarded in the router) needs the
    // unfiltered view; everyone else sees only their actual friends.
    const isAdminExport = meID === "admin";
    const friends = users
      .filter((u) => u.id !== meID && (isAdminExport || friendIDs.has(u.id)) && !blocked.has(u.id))
      .map((u) => {
        const stale = tnow - Date.parse(u.lastSeen) > PRESENCE_WINDOW_MS;
        return {
          id: u.id, handle: u.handle, displayName: u.displayName,
          activity: stale ? "idle" : u.activity, lastSeen: u.lastSeen,
          streak: u.streak, isFriend: true,
          nowPlaying: stale ? null : (u.nowPlaying ?? null),
        };
      });

    const derived = users
      .filter((u) => (isAdminExport || u.id === meID || friendIDs.has(u.id)) && u.activity && u.activity !== "idle")
      .map((u) => ({
        id: `ev_${u.id}_${Date.parse(u.lastSeen)}`,
        userID: u.id, userHandle: u.handle, userName: u.displayName,
        activity: u.activity, detail: null as string | null, at: u.lastSeen,
      }));

    const seen = new Set<string>();
    const feed = [...storedFeed, ...derived]
      .sort((a, b) => Date.parse(b.at as string) - Date.parse(a.at as string))
      .filter((e) => { const k = e.id as string; if (seen.has(k)) return false; seen.add(k); return true; })
      .filter((e) => {
        const who = (e.userID as string) || "";
        return !blocked.has(who) && (isAdminExport || who === meID || friendIDs.has(who));
      })
      .slice(0, 50);

    return { friends, cyphers, rooms, live, feed };
  }

  /** Push jobs to notify `me`'s friends. Skips friends who blocked me. */
  private async friendPushJobs(me: UserRecord, body: string, extra: Record<string, unknown>): Promise<PushJob[]> {
    const jobs: PushJob[] = [];
    for (const fid of me.friends) {
      const f = await this.user(fid);
      if (!f || f.blocks.includes(me.id)) continue;
      for (const token of f.pushTokens) {
        jobs.push({
          uid: fid, token,
          payload: {
            aps: { alert: { title: "The SESH", body }, sound: "default" },
            fromHandle: me.handle, ...extra,
          },
        });
      }
    }
    return jobs;
  }

  // ---- request handling --------------------------------------------------

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const uid = request.headers.get("x-uid") || "";
    const handle = request.headers.get("x-handle") || "";
    const name = request.headers.get("x-name") || "";
    const idem = request.headers.get("x-idempotency-key");
    const ok = (data: Record<string, unknown> = {}) =>
      new Response(JSON.stringify({ ok: true, ...data }), { headers: { "Content-Type": "application/json" } });

    // WebSocket upgrade (#C3). Tag the socket with the verified uid so
    // heartbeats can't forge presence for someone else.
    if (path === "/ws") {
      if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
      const pair = new WebSocketPair();
      this.state.acceptWebSocket(pair[1], uid ? [uid] : []);
      await this.touch(uid, handle, name);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }

    if (request.method === "GET" && path === "/snapshot") {
      // (#C8) Presence staleness affects the snapshot even when no write
      // happened, so the ETag combines the revision with a coarse time bucket
      // (presence window). Unchanged -> 304 with no body.
      const rev = (await this.state.storage.get<number>("rev")) ?? 0;
      const bucket = Math.floor(Date.now() / PRESENCE_WINDOW_MS);
      const etag = `"v${rev}-t${bucket}"`;
      if (request.headers.get("If-None-Match") === etag) {
        return new Response(null, { status: 304, headers: { "ETag": etag } });
      }
      return new Response(JSON.stringify(await this.snapshot(uid)),
        { headers: { "Content-Type": "application/json", "ETag": etag } });
    }

    // GET the caller's blocked set (used by the router for room reads).
    if (request.method === "GET" && path === "/blocks") {
      const me = await this.user(uid);
      return new Response(JSON.stringify(me?.blocks || []),
        { headers: { "Content-Type": "application/json" } });
    }

    if (request.method !== "POST") return json({ error: "not_found" }, 404);
    let body: Record<string, unknown> = {};
    try { body = await request.json(); } catch { body = {}; }

    // Idempotent replay: acknowledge without re-applying (#C5).
    if (await this.alreadyProcessed(idem)) return ok({ replayed: true });

    let pushJobs: PushJob[] = [];
    let changed = true;

    switch (true) {
      case path === "/register": {
        // Called after auth: persists code + profile so friend codes resolve.
        await this.touch(uid, handle, name, { code: str(body.code, 16) });
        changed = false;
        break;
      }

      case path === "/activity": {
        const activity = str(body.activity, 40) || "idle";
        const detail = str(body.detail, 200) || null;
        const me = await this.touch(uid, handle, name, { activity });
        if (activity !== "idle") {
          await this.pushFeed({
            id: `ev_${uid}_${Date.now()}`, userID: uid, userHandle: me.handle,
            userName: me.displayName, activity, detail, at: now(),
          });
          const line = LOUD_ACTIVITY[activity];
          if (line) {
            const text = detail ? `${me.displayName} ${line} — ${detail}` : `${me.displayName} ${line}`;
            pushJobs = await this.friendPushJobs(me, text, { kind: "friend_activity", activity });
          }
        }
        break;
      }

      case path === "/nowplaying": {
        await this.touch(uid, handle, name, { nowPlaying: body.nowPlaying ?? null });
        break;
      }

      case path === "/heartbeat": {
        await this.touch(uid, handle, name);
        changed = false;
        break;
      }

      case path === "/milestone": {
        const kind = str(body.kind, 40);
        const detail = str(body.detail, 200) || null;
        const me = await this.touch(uid, handle, name);
        const line = MILESTONE_LINES[kind];
        if (kind) {
          await this.pushFeed({
            id: `ms_${uid}_${Date.now()}`, userID: uid, userHandle: me.handle,
            userName: me.displayName, activity: "milestone", detail, at: now(),
          });
        }
        if (line) {
          const text = detail ? `${me.displayName} ${line} — ${detail}` : `${me.displayName} ${line}`;
          pushJobs = await this.friendPushJobs(me, text, { kind: "friend_milestone", milestone: kind });
        }
        break;
      }

      case path === "/invite": {
        const me = await this.touch(uid, handle, name);
        const handles = Array.isArray(body.handles) ? (body.handles as string[]).slice(0, 20) : [];
        const detail = str(body.detail, 200);
        const users = await this.allUsers();
        for (const h of handles) {
          const target = users.find((u) => u.handle === h);
          if (!target || target.blocks.includes(uid)) continue;
          for (const token of target.pushTokens) {
            pushJobs.push({
              uid: target.id, token,
              payload: {
                aps: { alert: { title: "The SESH", body: detail ? `${me.displayName} invited you to sesh — ${detail}` : `${me.displayName} invited you to sesh 🤙` }, sound: "default" },
                kind: "sesh_invite", fromHandle: me.handle,
              },
            });
          }
        }
        changed = false;
        break;
      }

      case path === "/push/register": {
        const token = str(body.token, 200);
        if (!token) return new Response(JSON.stringify({ ok: false, error: "no_token" }), { status: 400 });
        const me = await this.touch(uid, handle, name);
        const set = new Set(me.pushTokens); set.add(token);
        me.pushTokens = [...set].slice(-5);
        await this.putUser(me);
        changed = false;
        break;
      }

      case path === "/push/unregister": {
        const token = str(body.token, 200);
        const me = await this.user(uid);
        if (me) { me.pushTokens = me.pushTokens.filter((t) => t !== token); await this.putUser(me); }
        changed = false;
        break;
      }

      case path === "/push/prune": {
        // Router reports dead tokens after APNs 410 / BadDeviceToken (#C9).
        const dead = Array.isArray(body.tokens) ? (body.tokens as string[]) : [];
        const owner = str(body.uid, 200) || uid;
        const u = await this.user(owner);
        if (u && dead.length) {
          u.pushTokens = u.pushTokens.filter((t) => !dead.includes(t));
          await this.putUser(u);
        }
        changed = false;
        break;
      }

      case path === "/cyphers": {
        const me = await this.touch(uid, handle, name, { activity: body.live === true ? "live" : "in_cypher" });
        const cyphers = await this.list<Record<string, unknown>>("cyphers", []);
        cyphers.unshift({
          id: str(body.id, 64) || `cy_${Date.now()}`,
          title: str(body.title, 100) || "Cypher",
          hostHandle: me.handle, hostName: me.displayName,
          strainName: str(body.strain, 100) || null,
          participantIDs: [uid], maxParticipants: 8,
          isLive: body.live === true, visibility: str(body.visibility, 20) || "public",
          startedAt: now(), note: null,
        });
        await this.state.storage.put("cyphers", cyphers.slice(0, 50));
        break;
      }

      case /^\/cyphers\/[^/]+\/(join|leave)$/.test(path): {
        const m = path.match(/^\/cyphers\/([^/]+)\/(join|leave)$/)!;
        const [, id, action] = m;
        const cyphers = await this.list<{ id: string; participantIDs: string[] }>("cyphers", []);
        const c = cyphers.find((x) => x.id === id);
        if (c) {
          if (action === "join" && !c.participantIDs.includes(uid)) c.participantIDs.push(uid);
          if (action === "leave") c.participantIDs = c.participantIDs.filter((p) => p !== uid);
          await this.state.storage.put("cyphers", cyphers);
        }
        await this.touch(uid, handle, name, { activity: action === "join" ? "in_cypher" : "idle" });
        break;
      }

      case path === "/live": {
        const me = await this.touch(uid, handle, name, { activity: "live" });
        const live = await this.list<Record<string, unknown>>("live", []);
        live.unshift({
          id: str(body.id, 64) || `lv_${Date.now()}`,
          hostHandle: me.handle, hostName: me.displayName,
          title: str(body.title, 100) || "Live",
          viewerCount: 0, strainName: str(body.strain, 100) || null,
          startedAt: now(), cypherID: str(body.cypher, 64) || null,
        });
        await this.state.storage.put("live", live.slice(0, 50));
        const detail = str(body.title, 100) || str(body.strain, 100) || null;
        const text = detail ? `${me.displayName} is live now 🔴 — ${detail}` : `${me.displayName} is live now 🔴`;
        pushJobs = await this.friendPushJobs(me, text, { kind: "friend_activity", activity: "live" });
        break;
      }

      case /^\/live\/[^/]+\/end$/.test(path): {
        const id = path.match(/^\/live\/([^/]+)\/end$/)![1];
        let live = await this.list<{ id: string }>("live", []);
        live = live.filter((x) => x.id !== id);
        await this.state.storage.put("live", live);
        await this.touch(uid, handle, name, { activity: "idle" });
        break;
      }

      case path === "/room-touch": {
        // Called by the router after RoomDO stores a message.
        const roomID = str(body.roomID, 64);
        const rooms = await this.list<{ id: string; lastMessage?: string | null; lastMessageAt?: string | null }>("rooms", seedRooms() as never);
        const r = rooms.find((x) => x.id === roomID);
        if (r) {
          r.lastMessage = str(body.text, 200);
          r.lastMessageAt = now();
          await this.state.storage.put("rooms", rooms);
        }
        // Posting in a room makes you a member of it.
        await this.joinRoom(roomID, uid);
        break;
      }

      case path === "/room-join": {
        // Called when the app opens a room, so lurkers are counted too. Only a
        // genuinely new member changes the snapshot — re-opening a room you're
        // already in must not bump the revision and wake every client.
        changed = await this.joinRoom(str(body.roomID, 64), uid);
        break;
      }

      case path === "/block" || path === "/unblock": {
        const target = str(body.userID, 200);
        const me = await this.touch(uid, handle, name);
        const set = new Set(me.blocks);
        if (path === "/block" && target) set.add(target);
        if (path === "/unblock") set.delete(target);
        me.blocks = [...set];
        // (#App17) Blocking also severs the friendship both ways.
        if (path === "/block" && target) {
          me.friends = me.friends.filter((f) => f !== target);
          const other = await this.user(target);
          if (other) { other.friends = other.friends.filter((f) => f !== uid); await this.putUser(other); }
        }
        await this.putUser(me);
        break;
      }

      case path === "/report": {
        const reports = await this.list<unknown>("reports", []);
        reports.unshift({
          id: `rep_${Date.now()}`, reporterID: uid,
          targetID: str(body.userID, 200) || null, messageID: str(body.messageID, 200) || null,
          reason: str(body.reason, 280), at: now(),
        });
        await this.state.storage.put("reports", (reports as unknown[]).slice(0, 500));
        changed = false;
        break;
      }

      case path === "/friends/add": {
        const me = await this.touch(uid, handle, name, { code: str(body.myCode, 16) });
        const wanted = str(body.code, 16).toUpperCase().trim();
        const targetID = await this.state.storage.get<string>(`code:${wanted}`);
        const match = targetID ? await this.user(targetID) : undefined;
        if (!match || match.id === uid) {
          return new Response(JSON.stringify({ ok: false }), { status: 404, headers: { "Content-Type": "application/json" } });
        }
        if (!me.friends.includes(match.id)) me.friends.push(match.id);
        if (!match.friends.includes(uid)) match.friends.push(uid);
        await this.putUser(me);
        await this.putUser(match);
        await this.markProcessed(idem);
        return ok({ friend: { id: match.id, handle: match.handle, displayName: match.displayName } });
      }

      default:
        return json({ error: "not_found" }, 404);
    }

    // Handler succeeded — only now is the idempotency key committed (#C5).
    await this.markProcessed(idem);
    if (changed) this.broadcastChanged();
    return ok(pushJobs.length ? { pushJobs } : {});
  }
}
