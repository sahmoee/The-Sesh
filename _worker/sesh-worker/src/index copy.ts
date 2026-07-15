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

import { CORS, json, now, str } from "./util";
import { mintSession, requireAuth, verifyAppleIdentityToken, SessionClaims } from "./auth";
import { deviceCheckGate } from "./devicecheck";
import { apnsSend } from "./apns";
import * as spotify from "./spotify";
import { SocialDO } from "./social";
import { RoomDO } from "./rooms";

export { SocialDO, RoomDO };

export interface Env {
  SESH?: KVNamespace;              // legacy data + Spotify refresh tokens
  SOCIAL: DurableObjectNamespace;  // singleton social graph
  ROOMS: DurableObjectNamespace;   // one per chat room
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
      const me: SessionClaims = {
        uid: `apple:${sub}`,
        handle: str(body.handle, 40) || "@you",
        name: str(body.name, 80) || "You",
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
      const me: SessionClaims = {
        uid: `guest:${deviceID}`,
        handle: str(body.handle, 40) || "@you",
        name: str(body.name, 80) || "You",
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

    // ---- Everything below requires a valid session (#C1) --------------------

    const me = await requireAuth(env, request);
    if (!me) return finish(json({ error: "unauthorized" }, 401));
    const idem = request.headers.get("X-Idempotency-Key");

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
      const result = await spotify.exportPlaylist(env, me.uid,
        str(body.name, 100) || "The Sesh Playlist",
        tracks as never, str(body.existingID, 100) || null);
      if ((result as { error?: string }).error) return json(result, 400);
      return json(result);
    }

    // ---- Rooms (RoomDO) --------------------------------------------------------

    const roomMatch = path.match(/^\/api\/rooms\/([^/]+)\/(messages|ws)$/);
    if (roomMatch) {
      const [, roomID, sub] = roomMatch;
      const stub = roomStub(env, roomID);

      if (sub === "ws") {
        return stub.fetch(doRequest("/ws", me, { method: "GET", headers: request.headers, room: roomID }));
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
