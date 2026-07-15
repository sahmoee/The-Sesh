// spotify.ts — Spotify OAuth token storage + Web API calls.
//
// Refresh tokens stay in KV under `sp_refresh_<userID>` — they are single-key,
// single-writer records, so KV's eventual consistency is fine here (unlike the
// old shared "users"/"rooms" blobs, which moved to Durable Objects, #C4).
// Secrets: SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET.

import { now } from "./util";

export interface SpotifyEnv {
  SESH?: KVNamespace;
  SPOTIFY_CLIENT_ID?: string;
  SPOTIFY_CLIENT_SECRET?: string;
}

const TOKEN_URL = "https://accounts.spotify.com/api/token";
const API = "https://api.spotify.com/v1";

async function storeRefresh(env: SpotifyEnv, userID: string, refreshToken: string): Promise<void> {
  if (!refreshToken || !env.SESH) return;
  await env.SESH.put(`sp_refresh_${userID}`, JSON.stringify({ refreshToken, at: now() }));
}
async function getRefresh(env: SpotifyEnv, userID: string): Promise<string | null> {
  if (!env.SESH) return null;
  const raw = await env.SESH.get(`sp_refresh_${userID}`);
  if (!raw) return null;
  try { return (JSON.parse(raw) as { refreshToken?: string }).refreshToken || null; } catch { return null; }
}
export async function clearRefresh(env: SpotifyEnv, userID: string): Promise<void> {
  if (env.SESH) await env.SESH.delete(`sp_refresh_${userID}`);
}

export async function exchangeCode(env: SpotifyEnv, userID: string, code: string,
                                   verifier: string, redirectURI: string): Promise<boolean> {
  if (!env.SPOTIFY_CLIENT_ID) return false;
  const params = new URLSearchParams({
    grant_type: "authorization_code", code, redirect_uri: redirectURI,
    client_id: env.SPOTIFY_CLIENT_ID, code_verifier: verifier,
  });
  const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded" };
  if (env.SPOTIFY_CLIENT_SECRET) {
    headers["Authorization"] = "Basic " + btoa(`${env.SPOTIFY_CLIENT_ID}:${env.SPOTIFY_CLIENT_SECRET}`);
  }
  const resp = await fetch(TOKEN_URL, { method: "POST", headers, body: params });
  if (!resp.ok) return false;
  const data = (await resp.json()) as { refresh_token?: string };
  if (data.refresh_token) { await storeRefresh(env, userID, data.refresh_token); return true; }
  return false;
}

async function accessToken(env: SpotifyEnv, userID: string): Promise<string | null> {
  const refresh = await getRefresh(env, userID);
  if (!refresh || !env.SPOTIFY_CLIENT_ID || !env.SPOTIFY_CLIENT_SECRET) return null;
  const params = new URLSearchParams({
    grant_type: "refresh_token", refresh_token: refresh, client_id: env.SPOTIFY_CLIENT_ID,
  });
  const resp = await fetch(TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
      "Authorization": "Basic " + btoa(`${env.SPOTIFY_CLIENT_ID}:${env.SPOTIFY_CLIENT_SECRET}`),
    },
    body: params,
  });
  if (!resp.ok) return null;
  const data = (await resp.json()) as { access_token?: string; refresh_token?: string };
  if (data.refresh_token) await storeRefresh(env, userID, data.refresh_token);
  return data.access_token || null;
}

interface SpTrack {
  name?: string; uri?: string;
  artists?: { name: string }[];
  album?: { name: string; images?: { url: string }[] };
  external_ids?: { isrc?: string };
}

function trackToJSON(track: SpTrack | null, source: string) {
  if (!track) return null;
  const artist = (track.artists || []).map((a) => a.name).join(", ");
  const img = track.album?.images?.[0];
  return {
    title: track.name || "Unknown",
    artist: artist || "Unknown artist",
    album: track.album ? track.album.name : null,
    artworkURL: img ? img.url : null,
    source: source || "spotify",
    isrc: track.external_ids?.isrc || null,
    spotifyURI: track.uri || null,
  };
}

export async function nowPlaying(env: SpotifyEnv, userID: string) {
  const token = await accessToken(env, userID);
  if (!token) return null;
  const resp = await fetch(`${API}/me/player/currently-playing`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (resp.status === 204 || !resp.ok) return null;
  const data = (await resp.json()) as { item?: SpTrack; is_playing?: boolean };
  if (!data?.item) return null;
  const np = trackToJSON(data.item, "spotify") as Record<string, unknown> | null;
  if (!np) return null;
  np.isPlaying = !!data.is_playing;
  np.updatedAt = now();
  return np;
}

export async function search(env: SpotifyEnv, userID: string, query: string) {
  const token = await accessToken(env, userID);
  if (!token) return [];
  const url = `${API}/search?type=track&limit=20&q=${encodeURIComponent(query)}`;
  const resp = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
  if (!resp.ok) return [];
  const data = (await resp.json()) as { tracks?: { items?: SpTrack[] } };
  return (data.tracks?.items || []).map((t) => trackToJSON(t, "spotify")).filter(Boolean);
}

interface ExportTrack { title: string; artist: string; isrc?: string; spotifyURI?: string }

async function resolveURI(token: string, track: ExportTrack): Promise<string | null> {
  if (track.spotifyURI) return track.spotifyURI;
  if (track.isrc) {
    const u = `${API}/search?type=track&limit=1&q=${encodeURIComponent("isrc:" + track.isrc)}`;
    const r = await fetch(u, { headers: { Authorization: `Bearer ${token}` } });
    if (r.ok) {
      const d = (await r.json()) as { tracks?: { items?: SpTrack[] } };
      const hit = d.tracks?.items?.[0];
      if (hit?.uri) return hit.uri;
    }
  }
  const q = `${track.title} ${track.artist}`;
  const u2 = `${API}/search?type=track&limit=1&q=${encodeURIComponent(q)}`;
  const r2 = await fetch(u2, { headers: { Authorization: `Bearer ${token}` } });
  if (r2.ok) {
    const d2 = (await r2.json()) as { tracks?: { items?: SpTrack[] } };
    const hit2 = d2.tracks?.items?.[0];
    if (hit2?.uri) return hit2.uri;
  }
  return null;
}

export async function exportPlaylist(env: SpotifyEnv, userID: string, name: string,
                                     tracks: ExportTrack[], existingID: string | null) {
  const token = await accessToken(env, userID);
  if (!token) return { error: "not linked" };

  const uris: string[] = [];
  for (const t of tracks) {
    const uri = await resolveURI(token, t);
    if (uri) uris.push(uri);
  }
  if (uris.length === 0) return { added: 0, total: tracks.length, url: null };

  const meResp = await fetch(`${API}/me`, { headers: { Authorization: `Bearer ${token}` } });
  if (!meResp.ok) return { error: "me failed" };
  const meData = (await meResp.json()) as { id: string };

  let playlistID = existingID || null;
  let playlistURL: string | null = null;
  if (!playlistID) {
    const createResp = await fetch(`${API}/users/${meData.id}/playlists`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ name: name || "The Sesh Playlist", description: "Made in The Sesh", public: false }),
    });
    if (!createResp.ok) return { error: "create failed" };
    const created = (await createResp.json()) as { id: string; external_urls?: { spotify?: string } };
    playlistID = created.id;
    playlistURL = created.external_urls?.spotify || null;
  } else {
    playlistURL = `https://open.spotify.com/playlist/${playlistID}`;
  }

  for (let i = 0; i < uris.length; i += 100) {
    await fetch(`${API}/playlists/${playlistID}/tracks`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
      body: JSON.stringify({ uris: uris.slice(i, i + 100) }),
    });
  }
  return { added: uris.length, total: tracks.length, url: playlistURL };
}
