// util.ts — shared helpers for the SESH Worker.

export const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Idempotency-Key",
};

export const json = (data: unknown, status = 200): Response =>
  new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });

export const now = (): string => new Date().toISOString();

export const PRESENCE_WINDOW_MS = 5 * 60 * 1000;

export const b64url = (buf: ArrayBuffer | Uint8Array): string => {
  const bytes = buf instanceof ArrayBuffer ? new Uint8Array(buf) : buf;
  let s = "";
  for (let i = 0; i < bytes.length; i++) s += String.fromCharCode(bytes[i]);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
};

export const b64urlDecode = (s: string): Uint8Array => {
  const pad = s.length % 4 === 0 ? "" : "=".repeat(4 - (s.length % 4));
  const b = atob(s.replace(/-/g, "+").replace(/_/g, "/") + pad);
  const out = new Uint8Array(b.length);
  for (let i = 0; i < b.length; i++) out[i] = b.charCodeAt(i);
  return out;
};

export const utf8 = (s: string): Uint8Array => new TextEncoder().encode(s);

/** Minimal runtime schema validation: assert a body has string fields. */
export function str(v: unknown, max = 1000): string {
  return typeof v === "string" ? v.slice(0, max) : "";
}
export function bool(v: unknown): boolean {
  return v === true;
}

// ---- Identity labels -------------------------------------------------------
//
// "You" is a SECOND-PERSON UI label: it is only ever correct on the device that
// owns the identity. Persisting it as a display name — which both the app and
// this Worker used to do as their empty-name fallback — means every OTHER
// device renders that person's messages as "You". Nothing below ever returns
// it.

const SELF_LABELS = new Set(["you", "@you", "me", "@me", "myself", "self"]);

/** True for placeholders that must never be persisted as someone's identity. */
export function isSelfLabel(v: string): boolean {
  return SELF_LABELS.has(v.trim().toLowerCase());
}

/** Stable 4-char tag for a uid (FNV-1a, unambiguous alphabet), e.g. "7K9F". */
export function shortTag(uid: string): string {
  const alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let hash = 0x811c9dc5;
  for (let i = 0; i < uid.length; i++) {
    hash ^= uid.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193) >>> 0;
  }
  let out = "";
  let n = hash;
  for (let i = 0; i < 4; i++) {
    out += alphabet[n % alphabet.length];
    n = Math.floor(n / alphabet.length);
  }
  return out;
}

/** A human display name that is never a second-person placeholder. */
export function displayName(name: unknown, handle: unknown, uid: string): string {
  const n = str(name, 80).trim();
  if (n && !isSelfLabel(n)) return n;
  const h = str(handle, 40).trim().replace(/^@+/, "");
  if (h && !isSelfLabel(h)) return h;
  return `Sesher ${shortTag(uid)}`;
}

/** A handle that is never "@you". */
export function displayHandle(handle: unknown, uid: string): string {
  const h = str(handle, 40).trim().replace(/^@+/, "");
  if (h && !isSelfLabel(h)) return `@${h}`;
  return `@sesher${shortTag(uid).toLowerCase()}`;
}
