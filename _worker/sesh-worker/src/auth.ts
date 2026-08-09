// auth.ts — (#C1) Server-side identity.
//
// The Worker previously trusted whatever userID/handle/name the client put in
// headers or the body, which let anyone impersonate anyone. Now:
//
//   POST /api/auth/apple  { identityToken, handle?, name? }
//     -> verifies the Sign in with Apple identity token against Apple's JWKS
//        (issuer, audience, expiry, RS256 signature) and issues a short-lived
//        SESH session token bound to the verified Apple `sub`.
//
//   POST /api/auth/guest  { deviceID, handle?, name? }
//     -> for "continue without signing in". Issues a session for a
//        device-scoped guest id. Rate limited; upgradeable to App Attest later.
//
//   Every other endpoint requires `Authorization: Bearer <session>` and the
//   verified uid is the ONLY identity the handlers use.
//
// Session tokens: compact HMAC-SHA256 tokens `b64url(payload).b64url(sig)`
// signed with env.SESSION_SECRET (wrangler secret put SESSION_SECRET).
// Lifetime is 24h; the app silently re-exchanges when it gets a 401.

import { b64url, b64urlDecode, utf8 } from "./util";

export interface Env {
  SESSION_SECRET: string;
  APPLE_BUNDLE_ID?: string;      // audience for SIWA tokens
}

export interface SessionClaims {
  uid: string;        // verified user id ("apple:<sub>" or "guest:<deviceID>")
  handle: string;
  name: string;
  exp: number;        // unix seconds
}

const SESSION_TTL_S = 24 * 60 * 60;

// ---- Session tokens --------------------------------------------------------

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", utf8(secret),
    { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}

export async function mintSession(env: Env, uid: string, handle: string, name: string): Promise<string> {
  const claims: SessionClaims = {
    uid, handle, name,
    exp: Math.floor(Date.now() / 1000) + SESSION_TTL_S,
  };
  const payload = b64url(utf8(JSON.stringify(claims)));
  const key = await hmacKey(env.SESSION_SECRET);
  const sig = await crypto.subtle.sign("HMAC", key, utf8(payload));
  return `${payload}.${b64url(sig)}`;
}

export async function verifySession(env: Env, token: string): Promise<SessionClaims | null> {
  if (!env.SESSION_SECRET || !token) return null;
  const dot = token.lastIndexOf(".");
  if (dot < 0) return null;
  const payload = token.slice(0, dot);
  const sig = token.slice(dot + 1);
  try {
    const key = await hmacKey(env.SESSION_SECRET);
    const ok = await crypto.subtle.verify("HMAC", key, b64urlDecode(sig), utf8(payload));
    if (!ok) return null;
    const claims = JSON.parse(new TextDecoder().decode(b64urlDecode(payload))) as SessionClaims;
    if (!claims.uid || claims.exp < Math.floor(Date.now() / 1000)) return null;
    return claims;
  } catch {
    return null;
  }
}

/** Extract and verify the caller's session. Null -> respond 401.
 *  The `?token=` fallback exists only because WebSocket upgrades can't set an
 *  Authorization header — restrict it to /ws paths so bearer tokens don't end
 *  up in request logs for every other route. */
export async function requireAuth(env: Env, request: Request): Promise<SessionClaims | null> {
  const h = request.headers.get("Authorization") || "";
  const url = new URL(request.url);
  const token = h.startsWith("Bearer ")
    ? h.slice(7)
    : (url.pathname.endsWith("/ws") ? url.searchParams.get("token") || "" : "");
  return verifySession(env, token);
}

// ---- Sign in with Apple verification ---------------------------------------

const APPLE_JWKS_URL = "https://appleid.apple.com/auth/keys";
const APPLE_ISS = "https://appleid.apple.com";

interface JWK { kid: string; n: string; e: string; kty: string }
let _jwksCache: { keys: JWK[]; at: number } | null = null;

async function appleJWKS(): Promise<JWK[]> {
  if (_jwksCache && Date.now() - _jwksCache.at < 12 * 60 * 60 * 1000) return _jwksCache.keys;
  const resp = await fetch(APPLE_JWKS_URL);
  if (!resp.ok) return _jwksCache?.keys ?? [];
  const data = (await resp.json()) as { keys: JWK[] };
  _jwksCache = { keys: data.keys || [], at: Date.now() };
  return _jwksCache.keys;
}

/**
 * Verify a SIWA identity token. Returns the stable Apple user id (`sub`)
 * or null. Checks: RS256 signature against Apple's JWKS, iss, aud, exp.
 */
export async function verifyAppleIdentityToken(env: Env, idToken: string): Promise<string | null> {
  const parts = idToken.split(".");
  if (parts.length !== 3) return null;
  let header: { kid?: string; alg?: string };
  let claims: { iss?: string; aud?: string; exp?: number; sub?: string };
  try {
    header = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[0])));
    claims = JSON.parse(new TextDecoder().decode(b64urlDecode(parts[1])));
  } catch {
    return null;
  }
  if (header.alg !== "RS256" || !header.kid) return null;
  if (claims.iss !== APPLE_ISS) return null;
  if (!claims.exp || claims.exp < Math.floor(Date.now() / 1000)) return null;
  // Fail closed: without a configured audience we cannot validate `aud`, so
  // reject rather than accept tokens minted for any other app.
  if (!env.APPLE_BUNDLE_ID || claims.aud !== env.APPLE_BUNDLE_ID) return null;
  if (!claims.sub) return null;

  const jwk = (await appleJWKS()).find((k) => k.kid === header.kid);
  if (!jwk) return null;
  try {
    const key = await crypto.subtle.importKey(
      "jwk", { kty: jwk.kty, n: jwk.n, e: jwk.e },
      { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
    const ok = await crypto.subtle.verify(
      "RSASSA-PKCS1-v1_5", key,
      b64urlDecode(parts[2]), utf8(`${parts[0]}.${parts[1]}`));
    return ok ? claims.sub : null;
  } catch {
    return null;
  }
}
