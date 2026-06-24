/**
 * SESH social Worker  (identity-aware)
 * ------------------------------------
 * Backs The SESH: friends' presence, Cyphers (shared sessions), live streams,
 * chat rooms, and an activity feed. Now attributes everything to the real
 * signed-in user, whose identity { userID, handle, name } is sent with each
 * request (POST body or x-sesh-* headers).
 *
 * Storage: one Cloudflare KV namespace (binding `SESH`). Poll-based — the app
 * pulls /api/snapshot on a short timer. Migrate to Durable Objects + WebSockets
 * later for push without changing the request contract.
 */

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,x-sesh-user,x-sesh-handle,x-sesh-name,x-sesh-code",
};

const json = (data, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

const now = () => new Date().toISOString();
const PRESENCE_WINDOW_MS = 5 * 60 * 1000; // "active" if seen within 5 min

// ---- KV helpers -----------------------------------------------------------

async function kvGet(env, key, fallback) {
  if (!env.SESH) return fallback;
  const raw = await env.SESH.get(key);
  if (!raw) return fallback;
  try { return JSON.parse(raw); } catch { return fallback; }
}
async function kvPut(env, key, value) {
  if (!env.SESH) return;
  await env.SESH.put(key, JSON.stringify(value));
}

// ---- Rate limiting (token bucket per user/action) -------------------------

/** Returns true if allowed, false if the caller is over the limit. */
async function rateLimit(env, userID, action, max, windowMs) {
  if (!env.SESH) return true;
  const key = `rl_${action}_${userID}`;
  const nowMs = Date.now();
  const rec = await kvGet(env, key, { count: 0, start: nowMs });
  if (nowMs - rec.start > windowMs) {
    await kvPut(env, key, { count: 1, start: nowMs });
    return true;
  }
  if (rec.count >= max) return false;
  rec.count += 1;
  await kvPut(env, key, rec);
  return true;
}

// ---- Blocking -------------------------------------------------------------

async function blockedSet(env, userID) {
  const blocks = await kvGet(env, "blocks", {});
  return new Set(blocks[userID] || []);
}


// ---- Push notifications (APNs over HTTP/2) --------------------------------
//
// Token-based auth: we sign a short-lived ES256 JWT with the APNs .p8 key and
// send it as the Authorization bearer to api.push.apple.com. Three secrets are
// required (set with `wrangler secret put`):
//   APNS_KEY_ID    – the 10-char Key ID of the .p8 (e.g. WFDJ9HHW4U)
//   APNS_TEAM_ID   – your 10-char Apple Team ID
//   APNS_KEY_P8    – the FULL contents of the .p8 file (BEGIN/END lines incl.)
// And one plain var (in wrangler.toml [vars]):
//   APNS_BUNDLE_ID – com.sowens.The-SESH-  (the apns-topic)
//
// JWTs are cached ~50 min (Apple allows reuse up to ~60 min).

const b64url = (buf) => {
  const bytes = buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf;
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

/** Convert a PEM .p8 (PKCS#8) into a CryptoKey for ES256 signing. */
async function importP8(pem) {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8", der.buffer,
    { name: "ECDSA", namedCurve: "P-256" },
    false, ["sign"]);
}

let _apnsJWT = null; // { token, iat }

async function apnsToken(env) {
  const nowSec = Math.floor(Date.now() / 1000);
  if (_apnsJWT && nowSec - _apnsJWT.iat < 50 * 60) return _apnsJWT.token;
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;

  const header = b64url(new TextEncoder().encode(
    JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID })));
  const claims = b64url(new TextEncoder().encode(
    JSON.stringify({ iss: env.APNS_TEAM_ID, iat: nowSec })));
  const signingInput = `${header}.${claims}`;

  const key = await importP8(env.APNS_KEY_P8);
  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" }, key,
    new TextEncoder().encode(signingInput));
  const token = `${signingInput}.${b64url(sig)}`;
  _apnsJWT = { token, iat: nowSec };
  return token;
}

/** Send one notification to one device token. Returns true on 200. */
async function apnsSend(env, deviceToken, payload) {
  const jwt = await apnsToken(env);
  if (!jwt || !deviceToken) return false;
  const topic = env.APNS_BUNDLE_ID || "com.sowens.The-SESH-";
  // Production APNs host. (Sandbox is api.sandbox.push.apple.com — TestFlight &
  // App Store builds both use production; only debug builds from Xcode use sandbox.)
  const host = env.APNS_USE_SANDBOX === "1"
    ? "https://api.sandbox.push.apple.com"
    : "https://api.push.apple.com";
  try {
    const res = await fetch(`${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        "authorization": `bearer ${jwt}`,
        "apns-topic": topic,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });
    return res.status === 200;
  } catch {
    return false;
  }
}

/** Shared fan-out: send one push payload to all of `me`'s friends. */
async function fanOutToFriends(env, me, body, extra) {
  const users = await kvGet(env, "users", {});
  const meRec = users[me.userID];
  if (!meRec || !Array.isArray(meRec.friends)) return;
  await Promise.all(meRec.friends.map(async (fid) => {
    const f = users[fid];
    if (!f || !Array.isArray(f.pushTokens) || f.pushTokens.length === 0) return;
    const blocked = await blockedSet(env, fid);
    if (blocked.has(me.userID)) return;
    await Promise.all(f.pushTokens.map((tok) =>
      apnsSend(env, tok, {
        aps: { alert: { title: "The SESH", body }, sound: "default" },
        fromHandle: me.handle, ...extra,
      })));
  }));
}

/** Notify a user's friends that they just went live / active. */
async function notifyFriendsOfActivity(env, me, activity, detail) {
  // The "loud" transitions worth a push, with emoji.
  const loud = {
    live:        "is live now 🔴",
    smoking:     "just sparked up 💨",
    hitting_bong:"is hitting the bong 🌬️",
    rolling_up:  "is rolling up 🌿",
    in_cypher:   "started a Cypher 🔄",
  };
  const line = loud[activity];
  if (!line) return;

  const users = await kvGet(env, "users", {});
  const meRec = users[me.userID] || {};
  const title = me.name || meRec.displayName || "A friend";
  // Richer body: include the strain/detail when present.
  const body = detail ? `${title} ${line} — ${detail}` : `${title} ${line}`;
  await fanOutToFriends(env, me, body, { kind: "friend_activity", activity });
}

/** Notify friends about a one-off milestone (roll record, streak, etc.). */
async function notifyFriendsOfMilestone(env, me, kind, detail) {
  const lines = {
    roll_record:  "set a new roll record 🏆",
    streak:       "hit a new streak 🔥",
    champion:     "crowned a new favorite 👑",
  };
  const line = lines[kind];
  if (!line) return;
  const users = await kvGet(env, "users", {});
  const meRec = users[me.userID] || {};
  const title = me.name || meRec.displayName || "A friend";
  const body = detail ? `${title} ${line} — ${detail}` : `${title} ${line}`;
  await fanOutToFriends(env, me, body, { kind: "friend_milestone", milestone: kind });
}

// ---- Identity -------------------------------------------------------------

/** Pull the caller's identity from headers and/or body. */
function identity(request, body) {
  const h = request.headers;
  const userID = body.userID || h.get("x-sesh-user") || "anon";
  const handle = body.handle || h.get("x-sesh-handle") || "@you";
  const name = body.name || h.get("x-sesh-name") || "You";
  const code = body.code || h.get("x-sesh-code") || "";
  return { userID, handle, name, code };
}

/** Record/refresh a user's presence + activity in the users map. */
async function touchUser(env, id, fields) {
  const users = await kvGet(env, "users", {});
  const prev = users[id] || {};
  users[id] = {
    id,
    handle: fields.handle || prev.handle || "@you",
    displayName: fields.name || prev.displayName || "You",
    activity: fields.activity !== undefined ? fields.activity : (prev.activity || "idle"),
    lastSeen: now(),
    streak: prev.streak || 0,
    isFriend: true,
    code: fields.code || prev.code || "",
    friends: prev.friends || [],
    pushTokens: prev.pushTokens || [],
    nowPlaying: fields.nowPlaying !== undefined ? fields.nowPlaying : (prev.nowPlaying || null),
  };
  await kvPut(env, "users", users);
  return users[id];
}

// ---- Seed -----------------------------------------------------------------

function seedRooms() {
  const t = Date.now();
  const ago = (s) => new Date(t - s * 1000).toISOString();
  return [
    { id: "rm_general", name: "General", topic: "Anything goes 🌿", memberCount: 248, lastMessage: "anyone tried the new Runtz pheno?", lastMessageAt: ago(120), unread: 0 },
    { id: "rm_strains", name: "Strain Talk", topic: "Reviews & recs", memberCount: 156, lastMessage: "GDP hits different at night", lastMessageAt: ago(600), unread: 0 },
    { id: "rm_growers", name: "Growers", topic: "Cultivation chat", memberCount: 89, lastMessage: "week 6 flower, frosty af", lastMessageAt: ago(3600), unread: 0 },
    { id: "rm_sesh", name: "Sesh Lounge", topic: "Find a Cypher", memberCount: 312, lastMessage: "who's rolling up rn 🤙", lastMessageAt: ago(60), unread: 0 },
  ];
}

// A few seeded "community" users so a brand-new, only-user still sees life.
function seedUsers() {
  const t = Date.now();
  const ago = (s) => new Date(t - s * 1000).toISOString();
  return {
    u_shalise: { id: "u_shalise", handle: "@shalise", displayName: "Shalise", activity: "rolling_up", lastSeen: ago(30), streak: 12, isFriend: true },
    u_dro:     { id: "u_dro", handle: "@dro", displayName: "Dro", activity: "hitting_bong", lastSeen: ago(90), streak: 5, isFriend: true },
    u_kaya:    { id: "u_kaya", handle: "@kaya", displayName: "Kaya", activity: "live", lastSeen: ago(20), streak: 21, isFriend: true },
    u_indica:  { id: "u_indica", handle: "@indi", displayName: "Indi", activity: "smoking", lastSeen: ago(45), streak: 16, isFriend: true },
  };
}

// ---- Snapshot -------------------------------------------------------------

function deriveFeedFrom(users) {
  return Object.values(users)
    .filter((u) => u.activity && u.activity !== "idle")
    .map((u) => ({
      id: `ev_${u.id}_${Date.parse(u.lastSeen)}`,
      userHandle: u.handle, userName: u.displayName,
      activity: u.activity, detail: null, at: u.lastSeen,
    }))
    .sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
}

async function buildSnapshot(env, me) {
  const blocked = me && me.userID ? await blockedSet(env, me.userID) : new Set();
  let users = await kvGet(env, "users", null);
  if (!users) { users = seedUsers(); await kvPut(env, "users", users); }

  let rooms = await kvGet(env, "rooms", null);
  if (!rooms) { rooms = seedRooms(); await kvPut(env, "rooms", rooms); }

  const cyphers = await kvGet(env, "cyphers", []);
  const live = await kvGet(env, "live", []);
  const storedFeed = await kvGet(env, "feed", []);

  // Friends = everyone except me, with stale presence downgraded to idle.
  const tnow = Date.now();
  const friends = Object.values(users)
    .filter((u) => !me || u.id !== me.userID)
    .filter((u) => !blocked.has(u.id))
    .map((u) => {
      const stale = tnow - Date.parse(u.lastSeen) > PRESENCE_WINDOW_MS;
      // Stale users show as idle and we drop their now-playing so the app
      // doesn't display a track for someone who isn't currently around.
      return { ...u, activity: stale ? "idle" : u.activity,
               nowPlaying: stale ? null : (u.nowPlaying || null) };
    });

  // Feed = explicit events + derived presence, newest first, de-duped.
  const derived = deriveFeedFrom(users);
  const seen = new Set();
  const feed = [...storedFeed, ...derived]
    .sort((a, b) => Date.parse(b.at) - Date.parse(a.at))
    .filter((e) => { const k = e.id; if (seen.has(k)) return false; seen.add(k); return true; })
    .filter((e) => !blocked.has(e.userID || ""))
    .slice(0, 50);

  return { friends, cyphers, rooms, live, feed };
}

// ---- Spotify (OAuth token storage + Web API) ------------------------------
//
// The app links a user's Spotify account with Authorization Code + PKCE. The
// app does the user-facing authorize step and sends us the `code` + PKCE
// `verifier`; we swap them for tokens here (the client secret stays server-side)
// and store the refresh token keyed by userID. We then mint short-lived access
// tokens on demand for now-playing, search, and playlist export.
//
// Secrets (wrangler secret put):
//   SPOTIFY_CLIENT_ID
//   SPOTIFY_CLIENT_SECRET
// Refresh tokens live in KV under `sp_refresh_<userID>`.

const SPOTIFY_TOKEN_URL = "https://accounts.spotify.com/api/token";
const SPOTIFY_API = "https://api.spotify.com/v1";

async function spotifyStoreRefresh(env, userID, refreshToken) {
  if (!refreshToken) return;
  await kvPut(env, `sp_refresh_${userID}`, { refreshToken, at: now() });
}
async function spotifyGetRefresh(env, userID) {
  const rec = await kvGet(env, `sp_refresh_${userID}`, null);
  return rec && rec.refreshToken ? rec.refreshToken : null;
}
async function spotifyClearRefresh(env, userID) {
  if (!env.SESH) return;
  await env.SESH.delete(`sp_refresh_${userID}`);
}

/** Exchange an authorization code (PKCE) for tokens; store the refresh token. */
async function spotifyExchangeCode(env, userID, code, verifier, redirectURI) {
  if (!env.SPOTIFY_CLIENT_ID) return false;
  const params = new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectURI,
    client_id: env.SPOTIFY_CLIENT_ID,
    code_verifier: verifier,
  });
  // PKCE token exchange. Sending the secret as well (Basic) is harmless and lets
  // the same app work whether or not it was registered as "public".
  const headers = { "Content-Type": "application/x-www-form-urlencoded" };
  if (env.SPOTIFY_CLIENT_SECRET) {
    headers["Authorization"] =
      "Basic " + btoa(`${env.SPOTIFY_CLIENT_ID}:${env.SPOTIFY_CLIENT_SECRET}`);
  }
  const resp = await fetch(SPOTIFY_TOKEN_URL, { method: "POST", headers, body: params });
  if (!resp.ok) return false;
  const data = await resp.json();
  if (data.refresh_token) {
    await spotifyStoreRefresh(env, userID, data.refresh_token);
    return true;
  }
  return false;
}

/** Get a fresh access token for a user from their stored refresh token. */
async function spotifyAccessToken(env, userID) {
  const refresh = await spotifyGetRefresh(env, userID);
  if (!refresh || !env.SPOTIFY_CLIENT_ID || !env.SPOTIFY_CLIENT_SECRET) return null;
  const params = new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refresh,
    client_id: env.SPOTIFY_CLIENT_ID,
  });
  const resp = await fetch(SPOTIFY_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Authorization": "Basic " + btoa(`${env.SPOTIFY_CLIENT_ID}:${env.SPOTIFY_CLIENT_SECRET}`),
    },
    body: params,
  });
  if (!resp.ok) return null;
  const data = await resp.json();
  // Spotify may return a rotated refresh token; persist it if so.
  if (data.refresh_token) await spotifyStoreRefresh(env, userID, data.refresh_token);
  return data.access_token || null;
}

/** Normalize a Spotify track object into the app's PlaylistTrack/NowPlaying shape. */
function spotifyTrackToJSON(track, source) {
  if (!track) return null;
  const artist = (track.artists || []).map((a) => a.name).join(", ");
  const img = track.album && track.album.images && track.album.images[0];
  return {
    title: track.name || "Unknown",
    artist: artist || "Unknown artist",
    album: track.album ? track.album.name : null,
    artworkURL: img ? img.url : null,
    source: source || "spotify",
    isrc: track.external_ids ? track.external_ids.isrc || null : null,
    spotifyURI: track.uri || null,
  };
}

/** Fetch the user's currently-playing track. Returns NowPlaying JSON or null. */
async function spotifyNowPlaying(env, userID) {
  const token = await spotifyAccessToken(env, userID);
  if (!token) return null;
  const resp = await fetch(`${SPOTIFY_API}/me/player/currently-playing`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (resp.status === 204 || !resp.ok) return null;
  const data = await resp.json();
  if (!data || !data.item) return null;
  const np = spotifyTrackToJSON(data.item, "spotify");
  if (!np) return null;
  np.isPlaying = !!data.is_playing;
  np.updatedAt = now();
  return np;
}

/** Search the Spotify catalog. Returns an array of PlaylistTrack JSON. */
async function spotifySearch(env, userID, query) {
  const token = await spotifyAccessToken(env, userID);
  if (!token) return [];
  const url = `${SPOTIFY_API}/search?type=track&limit=20&q=${encodeURIComponent(query)}`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!resp.ok) return [];
  const data = await resp.json();
  const items = (data.tracks && data.tracks.items) || [];
  return items.map((t) => spotifyTrackToJSON(t, "spotify")).filter(Boolean);
}

/** Resolve one app track to a Spotify URI (use given URI, else ISRC, else text). */
async function spotifyResolveURI(env, token, track) {
  if (track.spotifyURI) return track.spotifyURI;
  // ISRC is the most accurate.
  if (track.isrc) {
    const u = `${SPOTIFY_API}/search?type=track&limit=1&q=${encodeURIComponent("isrc:" + track.isrc)}`;
    const r = await fetch(u, { headers: { Authorization: `Bearer ${token}` } });
    if (r.ok) {
      const d = await r.json();
      const hit = d.tracks && d.tracks.items && d.tracks.items[0];
      if (hit && hit.uri) return hit.uri;
    }
  }
  // Title + artist fallback.
  const q = `${track.title} ${track.artist}`;
  const u2 = `${SPOTIFY_API}/search?type=track&limit=1&q=${encodeURIComponent(q)}`;
  const r2 = await fetch(u2, { headers: { Authorization: `Bearer ${token}` } });
  if (r2.ok) {
    const d2 = await r2.json();
    const hit2 = d2.tracks && d2.tracks.items && d2.tracks.items[0];
    if (hit2 && hit2.uri) return hit2.uri;
  }
  return null;
}

/** Create (or reuse) a playlist on the user's account and add the tracks. */
async function spotifyExportPlaylist(env, userID, name, tracks, existingID) {
  const token = await spotifyAccessToken(env, userID);
  if (!token) return { error: "not linked" };

  // Resolve tracks to URIs.
  const uris = [];
  for (const t of tracks) {
    const uri = await spotifyResolveURI(env, token, t);
    if (uri) uris.push(uri);
  }
  if (uris.length === 0) return { added: 0, total: tracks.length, url: null };

  // Need the Spotify user id to create a playlist under their account.
  const meResp = await fetch(`${SPOTIFY_API}/me`, { headers: { Authorization: `Bearer ${token}` } });
  if (!meResp.ok) return { error: "me failed" };
  const meData = await meResp.json();
  const spUserID = meData.id;

  // Reuse an existing playlist if one was passed, else create a new one.
  let playlistID = existingID || null;
  let playlistURL = null;
  if (!playlistID) {
    const createResp = await fetch(`${SPOTIFY_API}/users/${spUserID}/playlists`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ name: name || "The Sesh Playlist", description: "Made in The Sesh", public: false }),
    });
    if (!createResp.ok) return { error: "create failed" };
    const created = await createResp.json();
    playlistID = created.id;
    playlistURL = created.external_urls ? created.external_urls.spotify : null;
  } else {
    playlistURL = `https://open.spotify.com/playlist/${playlistID}`;
  }

  // Add tracks in batches of 100 (Spotify's per-request cap).
  for (let i = 0; i < uris.length; i += 100) {
    const batch = uris.slice(i, i + 100);
    await fetch(`${SPOTIFY_API}/playlists/${playlistID}/tracks`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ uris: batch }),
    });
  }
  return { added: uris.length, total: tracks.length, url: playlistURL };
}


// ---- Handlers -------------------------------------------------------------

async function pushFeed(env, event) {
  const feed = await kvGet(env, "feed", []);
  feed.unshift(event);
  await kvPut(env, "feed", feed.slice(0, 50));
}

async function handlePost(env, path, body, request) {
  const me = identity(request, body);

  // presence / activity
  if (path === "/api/activity") {
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code, activity: body.activity || "idle" });
    if (body.activity && body.activity !== "idle") {
      await pushFeed(env, {
        id: `ev_${me.userID}_${Date.now()}`, userHandle: me.handle, userName: me.name,
        activity: body.activity, detail: body.detail || null, at: now(),
      });
      // Notify friends on the "loud" transitions (live / smoking / cypher).
      await notifyFriendsOfActivity(env, me, body.activity, body.detail || null);
    }
    return json({ ok: true });
  }

  // ---- Scrobbler now-playing ----
  if (path === "/api/nowplaying") {
    const np = {
      title: String(body.title || "Unknown"),
      artist: String(body.artist || "Unknown artist"),
      album: body.album || null,
      artworkURL: body.artworkURL || null,
      source: body.source || "apple",
      isPlaying: body.isPlaying !== false,
      updatedAt: now(),
    };
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code, nowPlaying: np });
    return json({ ok: true });
  }
  if (path === "/api/nowplaying/clear") {
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code, nowPlaying: null });
    return json({ ok: true });
  }

  // ---- Spotify account link + playlist export ----
  if (path === "/api/spotify/exchange") {
    const ok = await spotifyExchangeCode(
      env, me.userID, String(body.code || ""), String(body.verifier || ""),
      String(body.redirectURI || ""));
    return json({ ok });
  }
  if (path === "/api/spotify/disconnect") {
    await spotifyClearRefresh(env, me.userID);
    return json({ ok: true });
  }
  if (path === "/api/spotify/playlist") {
    const tracks = Array.isArray(body.tracks) ? body.tracks : [];
    const result = await spotifyExportPlaylist(
      env, me.userID, String(body.name || "The Sesh Playlist"), tracks, body.existingID || null);
    if (result && result.error) return json({ error: result.error }, 400);
    return json(result);
  }

  // one-off milestone (roll record, streak, champion) -> friends get a push
  if (path === "/api/milestone") {
    const kind = String(body.kind || "").trim();
    if (kind) {
      await pushFeed(env, {
        id: `ms_${me.userID}_${Date.now()}`, userHandle: me.handle, userName: me.name,
        activity: "milestone", detail: body.detail || null, at: now(),
      });
      await notifyFriendsOfMilestone(env, me, kind, body.detail || null);
    }
    return json({ ok: true });
  }

  // register / refresh this device's APNs push token
  if (path === "/api/push/register") {
    const token = String(body.token || "").trim();
    if (!token) return json({ ok: false, error: "no_token" }, 400);
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code });
    const users = await kvGet(env, "users", {});
    const u = users[me.userID];
    if (u) {
      const set = new Set(u.pushTokens || []);
      set.add(token);
      // keep it bounded (a few devices max)
      u.pushTokens = [...set].slice(-5);
      await kvPut(env, "users", users);
    }
    return json({ ok: true });
  }

  // unregister a device token (e.g. on sign-out or push-permission revoked)
  if (path === "/api/push/unregister") {
    const token = String(body.token || "").trim();
    const users = await kvGet(env, "users", {});
    const u = users[me.userID];
    if (u && Array.isArray(u.pushTokens)) {
      u.pushTokens = u.pushTokens.filter((t) => t !== token);
      await kvPut(env, "users", users);
    }
    return json({ ok: true });
  }

  // simple heartbeat to keep presence fresh without changing activity
  if (path === "/api/heartbeat") {
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code });
    return json({ ok: true });
  }

  // create cypher
  if (path === "/api/cyphers") {
    const cyphers = await kvGet(env, "cyphers", []);
    cyphers.unshift({
      id: body.id, title: body.title || "Cypher",
      hostHandle: me.handle, hostName: me.name,
      strainName: body.strain || null, participantIDs: [me.userID], maxParticipants: 8,
      isLive: !!body.live, visibility: body.visibility || "public", startedAt: now(), note: null,
    });
    await kvPut(env, "cyphers", cyphers.slice(0, 50));
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code, activity: body.live ? "live" : "in_cypher" });
    return json({ ok: true });
  }

  // join / leave cypher
  let m = path.match(/^\/api\/cyphers\/([^/]+)\/(join|leave)$/);
  if (m) {
    const [, id, action] = m;
    const cyphers = await kvGet(env, "cyphers", []);
    const c = cyphers.find((x) => x.id === id);
    if (c) {
      if (action === "join" && !c.participantIDs.includes(me.userID)) c.participantIDs.push(me.userID);
      if (action === "leave") c.participantIDs = c.participantIDs.filter((p) => p !== me.userID);
      await kvPut(env, "cyphers", cyphers);
    }
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code, activity: action === "join" ? "in_cypher" : "idle" });
    return json({ ok: true });
  }

  // start live
  if (path === "/api/live") {
    const live = await kvGet(env, "live", []);
    live.unshift({
      id: body.id, hostHandle: me.handle, hostName: me.name, title: body.title || "Live",
      viewerCount: 0, strainName: body.strain || null, startedAt: now(),
      cypherID: body.cypher || null,
    });
    await kvPut(env, "live", live.slice(0, 50));
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code, activity: "live" });
    await notifyFriendsOfActivity(env, me, "live", body.title || body.strain || null);
    return json({ ok: true });
  }

  // end live
  m = path.match(/^\/api\/live\/([^/]+)\/end$/);
  if (m) {
    const id = m[1];
    let live = await kvGet(env, "live", []);
    live = live.filter((x) => x.id !== id);
    await kvPut(env, "live", live);
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code, activity: "idle" });
    return json({ ok: true });
  }

  // post message (rate limited: 20 / 10s)
  m = path.match(/^\/api\/rooms\/([^/]+)\/messages$/);
  if (m) {
    if (!(await rateLimit(env, me.userID, "msg", 20, 10000)))
      return json({ ok: false, error: "rate_limited" }, 429);
    const roomID = m[1];
    const key = `msgs_${roomID}`;
    const msgs = await kvGet(env, key, []);
    msgs.push({
      id: body.id, roomID, senderHandle: me.handle, senderName: me.name,
      senderID: me.userID, text: String(body.text || "").slice(0, 1000), sentAt: now(),
    });
    await kvPut(env, key, msgs.slice(-500));

    const rooms = await kvGet(env, "rooms", []);
    const r = rooms.find((x) => x.id === roomID);
    if (r) { r.lastMessage = body.text || ""; r.lastMessageAt = now(); await kvPut(env, "rooms", rooms); }
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code });
    return json({ ok: true });
  }


  // block / unblock a user
  if (path === "/api/block" || path === "/api/unblock") {
    const blocks = await kvGet(env, "blocks", {});
    const list = new Set(blocks[me.userID] || []);
    const target = body.userID || "";
    if (path === "/api/block" && target) list.add(target);
    if (path === "/api/unblock") list.delete(target);
    blocks[me.userID] = [...list];
    await kvPut(env, "blocks", blocks);
    return json({ ok: true, blocked: blocks[me.userID] });
  }

  // report a user or message (stored for moderation)
  if (path === "/api/report") {
    if (!(await rateLimit(env, me.userID, "report", 10, 60000)))
      return json({ ok: false, error: "rate_limited" }, 429);
    const reports = await kvGet(env, "reports", []);
    reports.unshift({
      id: `rep_${Date.now()}`, reporterID: me.userID,
      targetID: body.userID || null, messageID: body.messageID || null,
      reason: String(body.reason || "").slice(0, 280), at: now(),
    });
    await kvPut(env, "reports", reports.slice(0, 500));
    return json({ ok: true });
  }

  // add a friend by code (rate limited: 20 / min)
  if (path === "/api/friends/add") {
    if (!(await rateLimit(env, me.userID, "friend", 20, 60000)))
      return json({ ok: false, error: "rate_limited" }, 429);
    await touchUser(env, me.userID, { handle: me.handle, name: me.name, code: me.code });
    const fresh = await kvGet(env, "users", {});
    const wanted = (body.code || "").toUpperCase().trim();
    const match = Object.values(fresh).find((u) => (u.code || "").toUpperCase() === wanted);
    if (!match || match.id === me.userID) return json({ ok: false }, 404);
    const map = await kvGet(env, "users", {});
    if (!map[me.userID].friends.includes(match.id)) map[me.userID].friends.push(match.id);
    if (!map[match.id].friends.includes(me.userID)) map[match.id].friends.push(me.userID);
    await kvPut(env, "users", map);
    return json({ ok: true, friend: { id: match.id, handle: match.handle, displayName: match.displayName } });
  }

  return json({ error: "not found" }, 404);
}

// ---- Router ---------------------------------------------------------------

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    const url = new URL(request.url);
    const path = url.pathname;

    if (path === "/health") return json({ ok: true, ts: now() });

    // #19 — backup export of all managed KV data (guard with a secret header).
    if (request.method === "GET" && path === "/api/admin/export") {
      if (!env.ADMIN_KEY || request.headers.get("x-admin-key") !== env.ADMIN_KEY) {
        return json({ error: "unauthorized" }, 401);
      }
      const dump = {};
      for (const key of ["users", "rooms", "cyphers", "live", "feed", "blocks", "reports"]) {
        dump[key] = await kvGet(env, key, null);
      }
      return json({ exportedAt: now(), data: dump });
    }

    if (request.method === "GET" && path === "/api/snapshot") {
      const me = {
        userID: request.headers.get("x-sesh-user") || url.searchParams.get("uid") || "anon",
      };
      return json(await buildSnapshot(env, me));
    }

    // Spotify now-playing for the signed-in user (Worker holds the token).
    if (request.method === "GET" && path === "/api/spotify/now-playing") {
      const uid = request.headers.get("x-sesh-user") || url.searchParams.get("uid") || "anon";
      const np = await spotifyNowPlaying(env, uid);
      if (!np) return new Response(null, { status: 204, headers: CORS });
      return json(np);
    }

    // Spotify catalog search (for adding songs to a playlist).
    if (request.method === "GET" && path === "/api/spotify/search") {
      const uid = request.headers.get("x-sesh-user") || url.searchParams.get("uid") || "anon";
      const q = url.searchParams.get("q") || "";
      if (!q) return json([]);
      return json(await spotifySearch(env, uid, q));
    }

    // messages in a room: tagged isMe, blocked senders hidden, paginated.
    // Query: ?before=<ISO> returns the page ending before that time; ?limit=N.
    const msgMatch = path.match(/^\/api\/rooms\/([^/]+)\/messages$/);
    if (request.method === "GET" && msgMatch) {
      const meID = request.headers.get("x-sesh-user") || url.searchParams.get("uid") || "anon";
      const blocked = await blockedSet(env, meID);
      const before = url.searchParams.get("before");
      const limit = Math.min(parseInt(url.searchParams.get("limit") || "100", 10) || 100, 200);
      let msgs = await kvGet(env, `msgs_${msgMatch[1]}`, []);
      msgs = msgs.filter((m) => !blocked.has(m.senderID));
      if (before) {
        const cutoff = Date.parse(before);
        msgs = msgs.filter((m) => Date.parse(m.sentAt) < cutoff);
      }
      // newest `limit`, returned oldest->newest
      const page = msgs.slice(-limit).map((m) => ({ ...m, isMe: m.senderID === meID }));
      return json(page);
    }

    if (request.method === "POST") {
      let body = {};
      try { body = await request.json(); } catch { body = {}; }
      return handlePost(env, path, body, request);
    }

    return json({ error: "not found" }, 404);
  },
};
