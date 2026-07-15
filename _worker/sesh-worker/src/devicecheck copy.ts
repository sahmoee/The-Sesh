// devicecheck.ts — (#C2) Apple DeviceCheck validation.
//
// The app sends a DCDevice token with each auth exchange; we validate it with
// Apple before minting a session, which gates account creation (and therefore
// messaging, friend requests, reporting, and push registration) behind proof
// of a genuine Apple device. Scripted abuse from curl gets 403.
//
// Enforcement is opt-in via DEVICECHECK_REQUIRED="1" so the rollout can be
// monitored first (tokens are validated and logged either way when present).
// Simulator builds can't generate tokens, so keep enforcement off for dev
// workers. App Attest (per-request assertions) is the stronger follow-up.
//
// Secrets: DC_KEY_ID / DC_TEAM_ID / DC_KEY_P8 — a DeviceCheck-enabled .p8.
// Falls back to the APNs key if those aren't set (the same key can carry both
// capabilities).

import { b64url, utf8 } from "./util";

export interface DeviceCheckEnv {
  DC_KEY_ID?: string;
  DC_TEAM_ID?: string;
  DC_KEY_P8?: string;
  APNS_KEY_ID?: string;
  APNS_TEAM_ID?: string;
  APNS_KEY_P8?: string;
  DEVICECHECK_REQUIRED?: string;
  DEVICECHECK_USE_SANDBOX?: string;
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

async function dcJWT(env: DeviceCheckEnv): Promise<string | null> {
  const keyID = env.DC_KEY_ID || env.APNS_KEY_ID;
  const teamID = env.DC_TEAM_ID || env.APNS_TEAM_ID;
  const p8 = env.DC_KEY_P8 || env.APNS_KEY_P8;
  if (!keyID || !teamID || !p8) return null;
  const nowSec = Math.floor(Date.now() / 1000);
  if (_jwt && nowSec - _jwt.iat < 50 * 60) return _jwt.token;
  const header = b64url(utf8(JSON.stringify({ alg: "ES256", kid: keyID })));
  const claims = b64url(utf8(JSON.stringify({ iss: teamID, iat: nowSec })));
  const input = `${header}.${claims}`;
  const key = await importP8(p8);
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, utf8(input));
  _jwt = { token: `${input}.${b64url(sig)}`, iat: nowSec };
  return _jwt.token;
}

export type DeviceCheckVerdict = "valid" | "invalid" | "unavailable";

/** Validate a DCDevice token with Apple. */
export async function validateDeviceToken(env: DeviceCheckEnv, deviceToken: string): Promise<DeviceCheckVerdict> {
  if (!deviceToken) return "invalid";
  const jwt = await dcJWT(env);
  if (!jwt) return "unavailable";
  const host = env.DEVICECHECK_USE_SANDBOX === "1"
    ? "https://api.development.devicecheck.apple.com"
    : "https://api.devicecheck.apple.com";
  try {
    const resp = await fetch(`${host}/v1/validate_device_token`, {
      method: "POST",
      headers: { "Authorization": `Bearer ${jwt}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        device_token: deviceToken,
        transaction_id: crypto.randomUUID(),
        timestamp: Date.now(),
      }),
    });
    if (resp.status === 200) return "valid";
    console.log(`devicecheck_invalid status=${resp.status}`);
    return "invalid";
  } catch (e) {
    console.log(`devicecheck_unavailable error=${String(e)}`);
    return "unavailable";
  }
}

/**
 * Gate an auth exchange. Returns null when the request may proceed, or an
 * error string when it must be rejected (enforcement on + token missing/bad).
 * "unavailable" (Apple down / not configured) fails open by design.
 */
export async function deviceCheckGate(env: DeviceCheckEnv, dcToken: string): Promise<string | null> {
  const required = env.DEVICECHECK_REQUIRED === "1";
  if (!dcToken) return required ? "device_check_required" : null;
  const verdict = await validateDeviceToken(env, dcToken);
  if (verdict === "invalid" && required) return "device_check_failed";
  return null;
}
