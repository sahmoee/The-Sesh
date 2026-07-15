// apns.ts — APNs over HTTP/2 with token lifecycle handling (#C9).
//
// Secrets: APNS_KEY_ID, APNS_TEAM_ID, APNS_KEY_P8 (wrangler secret put).
// Vars: APNS_BUNDLE_ID (topic), APNS_USE_SANDBOX ("1" for debug builds).
//
// apnsSend now reports WHY a send failed so callers can prune dead tokens:
// APNs answers 410 (Unregistered) or 400/BadDeviceToken for tokens that must
// be deleted; previously those errors were swallowed and dead tokens
// accumulated forever, wasting fan-out work and masking delivery failures.

import { b64url, utf8 } from "./util";

export interface ApnsEnv {
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_P8?: string;
  APNS_BUNDLE_ID?: string;
  APNS_USE_SANDBOX?: string;
}

export interface ApnsResult {
  ok: boolean;
  /** true when the device token is dead and must be removed. */
  tokenInvalid: boolean;
  status: number;
  reason?: string;
}

async function importP8(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey("pkcs8", der.buffer,
    { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
}

let _jwt: { token: string; iat: number } | null = null;

async function apnsToken(env: ApnsEnv): Promise<string | null> {
  const nowSec = Math.floor(Date.now() / 1000);
  if (_jwt && nowSec - _jwt.iat < 50 * 60) return _jwt.token;
  if (!env.APNS_KEY_P8 || !env.APNS_KEY_ID || !env.APNS_TEAM_ID) return null;
  const header = b64url(utf8(JSON.stringify({ alg: "ES256", kid: env.APNS_KEY_ID })));
  const claims = b64url(utf8(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: nowSec })));
  const input = `${header}.${claims}`;
  const key = await importP8(env.APNS_KEY_P8);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(input));
  _jwt = { token: `${input}.${b64url(sig)}`, iat: nowSec };
  return _jwt.token;
}

export async function apnsSend(env: ApnsEnv, deviceToken: string, payload: unknown): Promise<ApnsResult> {
  const jwt = await apnsToken(env);
  if (!jwt || !deviceToken) return { ok: false, tokenInvalid: false, status: 0, reason: "not_configured" };
  const topic = env.APNS_BUNDLE_ID || "com.sowens.The-SESH-";
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
    if (res.status === 200) return { ok: true, tokenInvalid: false, status: 200 };
    let reason = "";
    try { reason = ((await res.json()) as { reason?: string }).reason || ""; } catch { /* noop */ }
    const tokenInvalid = res.status === 410 ||
      reason === "BadDeviceToken" || reason === "Unregistered" || reason === "DeviceTokenNotForTopic";
    console.log(`apns_failure status=${res.status} reason=${reason} tokenInvalid=${tokenInvalid}`);
    return { ok: false, tokenInvalid, status: res.status, reason };
  } catch (e) {
    return { ok: false, tokenInvalid: false, status: 0, reason: String(e) };
  }
}
