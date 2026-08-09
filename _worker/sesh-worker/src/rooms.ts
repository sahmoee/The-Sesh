// rooms.ts — RoomDO Durable Object: one instance per chat room (#C3, #C4).
//
// Messages are stored one-record-per-message under `msg:<sentAt>:<id>` instead
// of a single 500-message KV array, so concurrent sends can't clobber each
// other and pagination is a keyed range scan. Connected WebSocket clients get
// each new message pushed instantly; the app falls back to REST pagination
// for history.
//
// Rate limiting lives here too (per-user, in-DO, strongly consistent) instead
// of the old KV token bucket that raced with itself.

import { displayHandle, displayName, isSelfLabel, json, now, str } from "./util";

interface StoredMessage {
  id: string;
  roomID: string;
  senderID: string;
  senderHandle: string;
  senderName: string;
  text: string;
  sentAt: string;
}

const MAX_MESSAGES = 2000;
const RATE_MAX = 20;          // messages
const RATE_WINDOW_MS = 10000; // per 10s per user

export class RoomDO implements DurableObject {
  private state: DurableObjectState;
  private rate: Map<string, { count: number; start: number }> = new Map();

  constructor(state: DurableObjectState) {
    this.state = state;
  }

  private broadcast(msg: StoredMessage): void {
    const frame = JSON.stringify({ type: "message", message: msg });
    for (const ws of this.state.getWebSockets()) {
      try { ws.send(frame); } catch { /* gone */ }
    }
  }

  async webSocketMessage(): Promise<void> { /* read-only sockets */ }
  async webSocketClose(): Promise<void> { /* hibernation handles cleanup */ }

  private allowed(uid: string): boolean {
    const nowMs = Date.now();
    const rec = this.rate.get(uid);
    if (!rec || nowMs - rec.start > RATE_WINDOW_MS) {
      this.rate.set(uid, { count: 1, start: nowMs });
      return true;
    }
    if (rec.count >= RATE_MAX) return false;
    rec.count += 1;
    return true;
  }

  async fetch(request: Request): Promise<Response> {
    const url = new URL(request.url);
    const path = url.pathname;
    const uid = request.headers.get("x-uid") || "";
    const handle = request.headers.get("x-handle") || "";
    const name = request.headers.get("x-name") || "";
    const idem = request.headers.get("x-idempotency-key");
    const roomID = request.headers.get("x-room") || "";

    // WebSocket: live message stream for an open room (#C3).
    if (path === "/ws") {
      if (request.headers.get("Upgrade") !== "websocket") return new Response("expected websocket", { status: 426 });
      const pair = new WebSocketPair();
      this.state.acceptWebSocket(pair[1]);
      return new Response(null, { status: 101, webSocket: pair[0] });
    }

    // GET /presence — live occupancy from the hibernation API (SESH-RL-001-R2
    // Phase 4: the Lounge shows how many people are in a live post's room).
    if (request.method === "GET" && path === "/presence") {
      const count = Math.max(0, this.state.getWebSockets().length);
      return new Response(JSON.stringify({ count }),
        { headers: { "Content-Type": "application/json" } });
    }

    // GET /messages?before=<ISO>&limit=N  (blocked ids passed by the router)
    if (request.method === "GET" && path === "/messages") {
      const before = url.searchParams.get("before");
      // Clamp: a negative/zero/garbage limit must never reach DO storage (throws).
      const limit = Math.max(1, Math.min(parseInt(url.searchParams.get("limit") || "100", 10) || 100, 200));
      let blocked: string[] = [];
      try { blocked = JSON.parse(request.headers.get("x-blocked") || "[]"); } catch { blocked = []; }
      const blockedSet = new Set(blocked);

      // Keys sort by sentAt; scan the tail (newest) backwards.
      const opts: DurableObjectListOptions = { prefix: "msg:", reverse: true, limit: limit * 2 };
      if (before) opts.end = `msg:${before}`;
      const map = await this.state.storage.list<StoredMessage>(opts);
      const page = [...map.values()]
        .filter((m) => !blockedSet.has(m.senderID))
        .slice(0, limit)
        .reverse() // oldest -> newest
        // Repair on read: messages written before the sender-name fix are
        // stored with the literal "You", which every other device then showed
        // as the author. Re-derive a real label for them instead of forcing a
        // storage migration — the stored rows stay untouched.
        .map((m) => ({
          ...m,
          senderHandle: displayHandle(m.senderHandle, m.senderID),
          senderName: isSelfLabel(m.senderName || "")
            ? displayName("", m.senderHandle, m.senderID)
            : displayName(m.senderName, m.senderHandle, m.senderID),
          isMe: m.senderID === uid,
        }));
      return new Response(JSON.stringify(page), { headers: { "Content-Type": "application/json" } });
    }

    // POST /messages {id, text}
    if (request.method === "POST" && path === "/messages") {
      if (!this.allowed(uid)) {
        return new Response(JSON.stringify({ ok: false, error: "rate_limited" }),
          { status: 429, headers: { "Content-Type": "application/json" } });
      }
      let body: Record<string, unknown> = {};
      try { body = await request.json(); } catch { body = {}; }

      const id = str(body.id, 64) || crypto.randomUUID();
      // Idempotent replay from the offline outbox (#C5): a message id is itself
      // a natural idempotency key — check both.
      const idemKey = idem || id;
      if (await this.state.storage.get(`idem:${idemKey}`)) {
        return new Response(JSON.stringify({ ok: true, replayed: true }),
          { headers: { "Content-Type": "application/json" } });
      }
      await this.state.storage.put(`idem:${idemKey}`, Date.now());

      // NEVER store "You" (or any other second-person placeholder) as the
      // author: this record is what every OTHER device renders. `displayName`
      // falls back to the handle, then to a stable "Sesher <tag>" derived from
      // the uid, so a nameless account still reads as a distinct person.
      const msg: StoredMessage = {
        id, roomID, senderID: uid,
        senderHandle: displayHandle(handle, uid),
        senderName: displayName(name, handle, uid),
        text: str(body.text, 1000), sentAt: now(),
      };
      await this.state.storage.put(`msg:${msg.sentAt}:${id}`, msg);
      this.broadcast(msg);

      // Bounded history: trim oldest beyond MAX_MESSAGES occasionally.
      const count = (await this.state.storage.get<number>("count")) ?? 0;
      await this.state.storage.put("count", count + 1);
      if ((count + 1) % 100 === 0) {
        const all = await this.state.storage.list({ prefix: "msg:" });
        const keys = [...all.keys()];
        if (keys.length > MAX_MESSAGES) {
          await this.state.storage.delete(keys.slice(0, keys.length - MAX_MESSAGES));
        }
      }
      return new Response(JSON.stringify({ ok: true, message: msg }),
        { headers: { "Content-Type": "application/json" } });
    }

    return json({ error: "not_found" }, 404);
  }
}
