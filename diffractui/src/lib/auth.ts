// Phase-0 admin authentication for the Diffract control surface.
//
// A single shared admin password gates the dashboard and all mutating APIs.
// Sessions are stateless, HMAC-SHA256-signed cookies (no DB). This is the
// minimum "no unauthenticated control surface" gate from the enterprise
// readiness plan (Phase 0); per-tenant auth/RBAC/SSO arrive in Phase 2.
//
// Uses Web Crypto (crypto.subtle) so the same helpers work in both the
// proxy (next/server) and Route Handlers. Configured via env:
//   DIFFRACT_ADMIN_PASSWORD  — the admin password
//   DIFFRACT_AUTH_SECRET     — HMAC signing secret (>= 16 chars)
// If either is unset the app fails CLOSED (deny), never open.

export const SESSION_COOKIE = "diffract_session";
const DEFAULT_TTL_SECONDS = 60 * 60 * 12; // 12h

function getSecret(): string | null {
  const s = process.env.DIFFRACT_AUTH_SECRET;
  return s && s.length >= 16 ? s : null;
}

function getAdminPassword(): string | null {
  const p = process.env.DIFFRACT_ADMIN_PASSWORD;
  return p && p.length > 0 ? p : null;
}

/** True only when both the admin password and signing secret are configured. */
export function authConfigured(): boolean {
  return getSecret() !== null && getAdminPassword() !== null;
}

// ── base64url helpers (no Buffer; runtime-agnostic) ──────────────────────
function b64urlEncode(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlToBytes(s: string): Uint8Array {
  let t = s.replace(/-/g, "+").replace(/_/g, "/");
  while (t.length % 4) t += "=";
  const bin = atob(t);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

async function hmac(secret: string, data: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(data));
  return new Uint8Array(sig);
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

/** Mint a signed session token, or null if auth isn't configured. */
export async function createSessionToken(ttlSeconds = DEFAULT_TTL_SECONDS): Promise<string | null> {
  const secret = getSecret();
  if (!secret) return null;
  const payload = JSON.stringify({ exp: Date.now() + ttlSeconds * 1000 });
  const payloadB64 = b64urlEncode(new TextEncoder().encode(payload));
  const sig = await hmac(secret, payloadB64);
  return `${payloadB64}.${b64urlEncode(sig)}`;
}

/** Verify a session token's signature and expiry. */
export async function verifySessionToken(token: string | undefined | null): Promise<boolean> {
  if (!token) return false;
  const secret = getSecret();
  if (!secret) return false;
  const parts = token.split(".");
  if (parts.length !== 2) return false;
  const [payloadB64, sigB64] = parts;
  const expected = await hmac(secret, payloadB64);
  let provided: Uint8Array;
  try {
    provided = b64urlToBytes(sigB64);
  } catch {
    return false;
  }
  if (!constantTimeEqual(expected, provided)) return false;
  try {
    const payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(payloadB64)));
    return typeof payload.exp === "number" && payload.exp > Date.now();
  } catch {
    return false;
  }
}

/** Constant-time, length-independent password check (compares HMAC digests). */
export async function verifyPassword(input: string): Promise<boolean> {
  const secret = getSecret();
  const expected = getAdminPassword();
  if (!secret || !expected) return false;
  const a = await hmac(secret, input);
  const b = await hmac(secret, expected);
  return constantTimeEqual(a, b);
}
