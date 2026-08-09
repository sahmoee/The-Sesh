// index.ts — SESH Worker router (modular TypeScript).
//
// What changed vs. the old single-file index.js:
//   #C1  Every request is authenticated. Sign in with Apple identity tokens are
//        verified server-side (auth.ts) and exchanged for short-lived session
//        tokens. Handlers only ever use the VERIFIED uid — client-supplied
//        userID headers/body fields are gone.
//   #C3  WebSockets (Durable Objects) replace 12-second polling: /api/ws pushes
//        social-state change events; /api/rooms/:id/ws streams chat live.
//   #C4  Shared KV blobs are partitioned: SocialDO owns users/friends/blocks/
//        cyphers/live/feed (serialized writes); RoomDO owns each room's
//        messages, one record per message.
//   #C5  Writes accept X-Idempotency-Key so the app's offline outbox can replay
//        safely — duplicates are acknowledged, not re-applied.
//   #C9  APNs sends report dead tokens (410 / BadDeviceToken), which are pruned
//        from the owning user's record; sign-out unregisters tokens.
//
// Secrets (wrangler secret put):
//   SESSION_SECRET       – HMAC key for session tokens (long random string)
//   APNS_KEY_ID / APNS_TEAM_ID / APNS_KEY_P8
//   SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET
// Vars (wrangler.toml):
//   APNS_BUNDLE_ID, APPLE_BUNDLE_ID, APNS_USE_SANDBOX (optional)

import { CORS, displayHandle, displayName, json, now, str } from "./util";
import { mintSession, requireAuth, verifyAppleIdentityToken, SessionClaims } from "./auth";
import { deviceCheckGate } from "./devicecheck";
import { apnsSend } from "./apns";
import * as spotify from "./spotify";
import { SocialDO } from "./social";
import { RoomDO } from "./rooms";
import { LoungeDO } from "./lounge";

export { SocialDO, RoomDO, LoungeDO };

export interface Env {
  SESH?: KVNamespace;              // legacy data + Spotify refresh tokens
  SOCIAL: DurableObjectNamespace;  // singleton social graph
  ROOMS: DurableObjectNamespace;   // one per chat room
  LOUNGE: DurableObjectNamespace;  // singleton public feed
  SESSION_SECRET: string;
  ADMIN_KEY?: string;
  APPLE_BUNDLE_ID?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_P8?: string;
  APNS_BUNDLE_ID?: string;
  APNS_USE_SANDBOX?: string;
  SPOTIFY_CLIENT_ID?: string;
  SPOTIFY_CLIENT_SECRET?: string;
  DC_KEY_ID?: string;
  DC_TEAM_ID?: string;
  DC_KEY_P8?: string;
  DEVICECHECK_REQUIRED?: string;
  DEVICECHECK_USE_SANDBOX?: string;
}

const socialStub = (env: Env) => env.SOCIAL.get(env.SOCIAL.idFromName("main"));
const roomStub = (env: Env, roomID: string) => env.ROOMS.get(env.ROOMS.idFromName(roomID));
const loungeStub = (env: Env) => env.LOUNGE.get(env.LOUNGE.idFromName("main"));

/** Forward a request into a DO with the verified identity attached. */
function doRequest(path: string, me: SessionClaims, init: RequestInit & { idem?: string | null; room?: string; blocked?: string } = {}): Request {
  const headers = new Headers(init.headers);
  headers.set("x-uid", me.uid);
  headers.set("x-handle", me.handle);
  headers.set("x-name", me.name);
  if (init.idem) headers.set("x-idempotency-key", init.idem);
  if (init.room) headers.set("x-room", init.room);
  if (init.blocked) headers.set("x-blocked", init.blocked);
  return new Request(`https://do${path}`, { ...init, headers });
}

/** Send push jobs returned by SocialDO; prune tokens APNs says are dead (#C9). */
async function deliverPushJobs(env: Env, me: SessionClaims,
                               jobs: { uid: string; token: string; payload: unknown }[]): Promise<void> {
  const dead: Record<string, string[]> = {};
  await Promise.all(jobs.map(async (job) => {
    const res = await apnsSend(env, job.token, job.payload);
    if (res.tokenInvalid) (dead[job.uid] ||= []).push(job.token);
  }));
  await Promise.all(Object.entries(dead).map(([uid, tokens]) =>
    socialStub(env).fetch(doRequest("/push/prune", me, {
      method: "POST", body: JSON.stringify({ uid, tokens }),
    }))));
}

async function readBody(request: Request): Promise<Record<string, unknown>> {
  try { return await request.json(); } catch { return {}; }
}

// ---- Lounge media hosting (SESH-RL-001-R2 Phase 4 / compose) ----------------
// JPEG bytes live in KV under `lmedia_<uuid>` and are served from an
// unguessable capability URL (image loaders can't attach bearer tokens).

const MEDIA_MAX_BYTES = 2 * 1024 * 1024;             // 2 MB decoded
const MEDIA_MAX_B64_CHARS = 2_900_000;               // ~2 MB after base64 decode
const MEDIA_TTL_SECONDS = 180 * 24 * 60 * 60;        // ~180 days
const MEDIA_RATE_MAX = 20;                            // uploads
const MEDIA_RATE_WINDOW_MS = 10 * 60 * 1000;          // per 10 min per uid

/** Decode the upload body: raw image/jpeg bytes or {dataBase64} JSON. */
async function readMediaBytes(request: Request): Promise<Uint8Array | null> {
  const ct = request.headers.get("Content-Type") || "";
  if (ct.includes("application/json")) {
    const body = await readBody(request);
    const b64 = typeof body.dataBase64 === "string" ? body.dataBase64.replace(/\s+/g, "") : "";
    if (!b64 || b64.length > MEDIA_MAX_B64_CHARS) return null;
    try {
      const bin = atob(b64);
      const out = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
      return out;
    } catch { return null; }
  }
  return new Uint8Array(await request.arrayBuffer());
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname;

    // (#17) Structured request log. The app sends X-Request-ID, so a failure in
    // the client's os_log can be matched to the exact Worker invocation.
    const reqID = request.headers.get("X-Request-ID") || "-";
    const started = Date.now();
    const log = (status: number) =>
      console.log(JSON.stringify({ t: now(), reqID, method: request.method, path, status, ms: Date.now() - started }));
    const finish = (resp: Response) => { log(resp.status); return resp; };

    if (path === "/health") return finish(json({ ok: true, ts: now() }));

    // ---- Auth (the only unauthenticated endpoints) -------------------------

    if (request.method === "POST" && path === "/api/auth/apple") {
      const body = await readBody(request);
      // (#C2) DeviceCheck gate: scripted signups get rejected when enforced.
      const dcError = await deviceCheckGate(env, str(body.dcToken, 4096));
      if (dcError) return finish(json({ error: dcError }, 403));
      const idToken = str(body.identityToken, 8192);
      const sub = await verifyAppleIdentityToken(env, idToken);
      if (!sub) return finish(json({ error: "invalid_identity_token" }, 401));
      const uid = `apple:${sub}`;
      const me: SessionClaims = {
        uid,
        // Never mint a session whose display name is "You": the name in these
        // claims is what gets stamped onto every message this account sends
        // and is rendered on everyone ELSE's device.
        handle: displayHandle(body.handle, uid),
        name: displayName(body.name, body.handle, uid),
        exp: 0,
      };
      const token = await mintSession(env, me.uid, me.handle, me.name);
      await socialStub(env).fetch(doRequest("/register", me, {
        method: "POST", body: JSON.stringify({ code: str(body.code, 16) }),
      }));
      return finish(json({ token, uid: me.uid }));
    }

    if (request.method === "POST" && path === "/api/auth/guest") {
      // "Continue without signing in": device-scoped guest identity, gated by
      // DeviceCheck when enforcement is on (#C2).
      const body = await readBody(request);
      const dcError = await deviceCheckGate(env, str(body.dcToken, 4096));
      if (dcError) return finish(json({ error: dcError }, 403));
      const deviceID = str(body.deviceID, 64);
      if (deviceID.length < 8) return finish(json({ error: "invalid_device" }, 400));
      const uid = `guest:${deviceID}`;
      const me: SessionClaims = {
        uid,
        handle: displayHandle(body.handle, uid),
        name: displayName(body.name, body.handle, uid),
        exp: 0,
      };
      const token = await mintSession(env, me.uid, me.handle, me.name);
      await socialStub(env).fetch(doRequest("/register", me, {
        method: "POST", body: JSON.stringify({ code: str(body.code, 16) }),
      }));
      return finish(json({ token, uid: me.uid }));
    }

    // ---- Admin --------------------------------------------------------------

    if (request.method === "GET" && path === "/api/admin/export") {
      if (!env.ADMIN_KEY || request.headers.get("x-admin-key") !== env.ADMIN_KEY) {
        return json({ error: "unauthorized" }, 401);
      }
      const admin: SessionClaims = { uid: "admin", handle: "@admin", name: "admin", exp: 0 };
      const snap = await socialStub(env).fetch(doRequest("/snapshot", admin, { method: "GET" }));
      return json({ exportedAt: now(), data: await snap.json() });
    }

    // ---- Lounge media serving (PUBLIC by design) ----------------------------
    // The uuid is an unguessable capability; AsyncImage-style loaders can't
    // attach bearer tokens, so this GET is deliberately unauthenticated.

    const mediaMatch = path.match(/^\/api\/lounge\/media\/([0-9a-fA-F-]{8,64})$/);
    if (request.method === "GET" && mediaMatch) {
      const data = env.SESH ? await env.SESH.get(`lmedia_${mediaMatch[1]}`, "arrayBuffer") : null;
      if (!data) return finish(json({ error: "not_found" }, 404));
      return finish(new Response(data, {
        headers: {
          "Content-Type": "image/jpeg",
          "Cache-Control": "public, max-age=31536000, immutable",
          ...CORS,
        },
      }));
    }

    // ---- Everything below requires a valid session (#C1) --------------------

    const me = await requireAuth(env, request);
    if (!me) return finish(json({ error: "unauthorized" }, 401));
    const idem = request.headers.get("X-Idempotency-Key");

    // ---- Profile (display name / handle) -------------------------------------
    //
    // The session token carries the display name, and RoomDO stamps that name
    // onto every message — so a name set or changed AFTER sign-in used to be
    // invisible to everyone else until the 24h session expired. This re-mints
    // the session (same verified uid, no re-authentication) with the new name
    // and updates the user record, so the next message is attributed correctly.
    if (request.method === "POST" && path === "/api/profile") {
      const body = await readBody(request);
      const wantHandle = str(body.handle, 40) || me.handle;
      const wantName = str(body.name, 80) || me.name;
      const next: SessionClaims = {
        uid: me.uid,
        handle: displayHandle(wantHandle, me.uid),
        name: displayName(wantName, wantHandle, me.uid),
        exp: 0,
      };
      const token = await mintSession(env, next.uid, next.handle, next.name);
      await socialStub(env).fetch(doRequest("/register", next, {
        method: "POST", body: JSON.stringify({ code: str(body.code, 16) }),
      }));
      return finish(json({ token, uid: next.uid, handle: next.handle, name: next.name }));
    }

    // Social WebSocket (#C3)
    if (path === "/api/ws") {
      return socialStub(env).fetch(doRequest("/ws", me, { method: "GET", headers: request.headers }));
    }

    if (request.method === "GET" && path === "/api/snapshot") {
      const headers: Record<string, string> = {};
      const inm = request.headers.get("If-None-Match");
      if (inm) headers["If-None-Match"] = inm;
      return finish(withCORS(await socialStub(env).fetch(doRequest("/snapshot", me, { method: "GET", headers }))));
    }

    // ---- The Lounge (SESH-RL-001-R2) -----------------------------------------
    //
    // Thin pass-through: the DO owns visibility and moderation so a post that
    // fails a check is never serialized into a response (§12). The router only
    // attaches the verified identity.

    if (path.startsWith("/api/lounge/")) {
      const sub = path.slice("/api/lounge/".length);
      const lounge = loungeStub(env);

      if (request.method === "GET" && sub === "feed") {
        return finish(withCORS(await lounge.fetch(
          doRequest(`/feed${url.search}`, me, { method: "GET" }))));
      }
      if (request.method === "GET" && sub.startsWith("post/")) {
        return finish(withCORS(await lounge.fetch(
          doRequest(`/${sub}`, me, { method: "GET" }))));
      }
      // POST /api/lounge/media — upload JPEG bytes, get back a capability URL.
      if (request.method === "POST" && sub === "media") {
        if (!env.SESH) return finish(json({ error: "media_unavailable" }, 503));

        // Per-uid rate limit via a KV window counter — same shape as the
        // in-DO limiter in rooms.ts, but KV is enough for a 10-minute window.
        const rlKey = `lmedia_rl_${me.uid}`;
        const nowMs = Date.now();
        let rl = await env.SESH.get<{ count: number; start: number }>(rlKey, "json");
        if (!rl || typeof rl.start !== "number" || nowMs - rl.start > MEDIA_RATE_WINDOW_MS) {
          rl = { count: 0, start: nowMs };
        }
        if (rl.count >= MEDIA_RATE_MAX) return finish(json({ error: "rate_limited" }, 429));

        const bytes = await readMediaBytes(request);
        if (!bytes || bytes.length === 0) return finish(json({ error: "invalid_media" }, 400));
        if (bytes.length > MEDIA_MAX_BYTES) return finish(json({ error: "too_large" }, 413));

        const mediaID = crypto.randomUUID();
        await env.SESH.put(`lmedia_${mediaID}`, bytes.buffer as ArrayBuffer,
          { expirationTtl: MEDIA_TTL_SECONDS });
        rl.count += 1;
        await env.SESH.put(rlKey, JSON.stringify(rl),
          { expirationTtl: Math.ceil(MEDIA_RATE_WINDOW_MS / 1000) });
        return finish(json({ url: `${url.origin}/api/lounge/media/${mediaID}` }));
      }

      // POST /api/lounge/live/end {postID} — author-only, ends a live session.
      if (request.method === "POST" && sub === "live/end") {
        const raw = await request.text();
        return finish(withCORS(await lounge.fetch(
          doRequest("/live/end", me, { method: "POST", body: raw, idem }))));
      }

      if (request.method === "POST") {
        const writable = ["create", "react", "vote", "comment",
                          "report", "hide", "block", "unblock", "follow", "unfollow"];
        if (writable.includes(sub)) {
          const raw = await request.text();
          return finish(withCORS(await lounge.fetch(
            doRequest(`/${sub}`, me, { method: "POST", body: raw, idem }))));
        }
      }
      return finish(json({ error: "not_found" }, 404));
    }

    // ---- Spotify -------------------------------------------------------------

    if (request.method === "GET" && path === "/api/spotify/now-playing") {
      const np = await spotify.nowPlaying(env, me.uid);
      if (!np) return new Response(null, { status: 204, headers: CORS });
      return json(np);
    }
    if (request.method === "GET" && path === "/api/spotify/search") {
      const q = url.searchParams.get("q") || "";
      return json(q ? await spotify.search(env, me.uid, q) : []);
    }
    if (request.method === "POST" && path === "/api/spotify/exchange") {
      const body = await readBody(request);
      const ok = await spotify.exchangeCode(env, me.uid, str(body.code, 2048),
        str(body.verifier, 256), str(body.redirectURI, 512));
      return json({ ok });
    }
    if (request.method === "POST" && path === "/api/spotify/disconnect") {
      await spotify.clearRefresh(env, me.uid);
      return json({ ok: true });
    }
    if (request.method === "POST" && path === "/api/spotify/playlist") {
      const body = await readBody(request);
      const tracks = Array.isArray(body.tracks) ? body.tracks : [];
      // Spotify's own per-playlist ceiling is far higher and exportPlaylist
      // already chunks adds in batches of 100; this cap only guards against
      // abusive payloads, not real libraries.
      if (tracks.length > 1000) return json({ error: "too_many_tracks" }, 400);
      const result = await spotify.exportPlaylist(env, me.uid,
        str(body.name, 100) || "The Sesh Playlist",
        tracks as never, str(body.existingID, 100) || null);
      if ((result as { error?: string }).error) return json(result, 400);
      return json(result);
    }

    // ---- Rooms (RoomDO) --------------------------------------------------------

    const roomMatch = path.match(/^\/api\/rooms\/([^/]+)\/(messages|ws|presence|join)$/);
    if (roomMatch) {
      const [, roomID, sub] = roomMatch;
      const stub = roomStub(env, roomID);

      // Opening a room makes you one of its members (this is what the room
      // list's "N members" counts — it was hard-wired to 0 before).
      if (sub === "join") {
        if (request.method !== "POST") return finish(json({ error: "not_found" }, 404));
        return finish(withCORS(await socialStub(env).fetch(doRequest("/room-join", me, {
          method: "POST", body: JSON.stringify({ roomID }),
        }))));
      }
      if (sub === "ws") {
        return stub.fetch(doRequest("/ws", me, { method: "GET", headers: request.headers, room: roomID }));
      }
      if (sub === "presence") {
        if (request.method !== "GET") return finish(json({ error: "not_found" }, 404));
        return finish(withCORS(await stub.fetch(doRequest("/presence", me, { method: "GET", room: roomID }))));
      }
      if (request.method === "GET") {
        // Blocked ids come from SocialDO so blocked senders stay hidden.
        const blocksResp = await socialStub(env).fetch(doRequest("/blocks", me, { method: "GET" }));
        const blocked = await blocksResp.text();
        return withCORS(await stub.fetch(doRequest(`/messages${url.search}`, me, {
          method: "GET", room: roomID, blocked,
        })));
      }
      if (request.method === "POST") {
        const body = await request.text();
        const resp = await stub.fetch(doRequest("/messages", me, {
          method: "POST", body, idem, room: roomID,
        }));
        if (resp.ok) {
          // Update room metadata + notify snapshot listeners.
          let text = "";
          try { text = str((JSON.parse(body) as Record<string, unknown>).text, 200); } catch { /* noop */ }
          ctx.waitUntil(socialStub(env).fetch(doRequest("/room-touch", me, {
            method: "POST", body: JSON.stringify({ roomID, text }),
          })));
        }
        return withCORS(resp);
      }
    }

    // ---- Social writes (SocialDO) ---------------------------------------------

    if (request.method === "POST" && path.startsWith("/api/")) {
      const doPath = path.slice(4); // "/api/activity" -> "/activity"
      const allowed = /^\/(activity|nowplaying(\/clear)?|heartbeat|milestone|invite|push\/(register|unregister)|cyphers(\/[^/]+\/(join|leave))?|live(\/[^/]+\/end)?|block|unblock|report|friends\/add)$/;
      if (!allowed.test(doPath)) return json({ error: "not found" }, 404);

      let body = await readBody(request);
      // Normalize now-playing clear into the same DO endpoint.
      let target = doPath;
      if (doPath === "/nowplaying/clear") { target = "/nowplaying"; body = { nowPlaying: null }; }
      else if (doPath === "/nowplaying") {
        body = { nowPlaying: {
          title: str(body.title, 200) || "Unknown",
          artist: str(body.artist, 200) || "Unknown artist",
          album: str(body.album, 200) || null,
          artworkURL: str(body.artworkURL, 500) || null,
          source: str(body.source, 20) || "apple",
          isPlaying: body.isPlaying !== false,
          updatedAt: now(),
        } };
      }

      const resp = await socialStub(env).fetch(doRequest(target, me, {
        method: "POST", body: JSON.stringify(body), idem,
      }));
      if (!resp.ok) return withCORS(resp);

      // Block reconciliation: LoungeDO keeps its own `block:<uid>` edges for
      // canView, so fan each social block/unblock out to it too. Best-effort —
      // a Lounge hiccup must never fail the social block itself.
      if (doPath === "/block" || doPath === "/unblock") {
        ctx.waitUntil(loungeStub(env).fetch(doRequest(doPath, me, {
          method: "POST", body: JSON.stringify({ userID: str(body.userID, 200) }),
        })).then(() => undefined, () => undefined));
      }

      const data = (await resp.json()) as { pushJobs?: { uid: string; token: string; payload: unknown }[] };
      if (data.pushJobs?.length) ctx.waitUntil(deliverPushJobs(env, me, data.pushJobs));
      return finish(json({ ok: true }));
    }

    return finish(json({ error: "not found" }, 404));
  },
};

/** Re-wrap a DO response with CORS headers for the app. */
function withCORS(resp: Response): Response {
  const headers = new Headers(resp.headers);
  for (const [k, v] of Object.entries(CORS)) headers.set(k, v);
  return new Response(resp.body, { status: resp.status, headers });
}
