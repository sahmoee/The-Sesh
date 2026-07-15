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
