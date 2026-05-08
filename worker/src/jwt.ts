// Supabase JWT verification.
//
// Modern Supabase projects sign JWTs with ES256 (asymmetric) using a
// rotating key set published at the project's JWKS endpoint. Older
// projects used HS256 with a shared secret; we don't support that path
// here because publishable-key projects are the default for any new
// install and the asymmetric path is strictly more secure for a public
// edge worker (no shared secret to leak).
//
// We use `jose` for the heavy lifting: JWKS fetch with kid-based key
// selection, signature verification, and standard-claim checks. The
// `createRemoteJWKSet` helper handles caching and refresh-on-miss
// internally, which means a key rotation on the Supabase side just
// works after the next request.
//
// Cold-start cost: one fetch of the JWKS document on the first request
// per isolate. Subsequent requests reuse the cached key set.

import { createRemoteJWKSet, jwtVerify, type JWTPayload } from "jose";

interface CachedJwks {
  url: string;
  jwks: ReturnType<typeof createRemoteJWKSet>;
}

let cached: CachedJwks | null = null;

function getJwks(supabaseUrl: string): ReturnType<typeof createRemoteJWKSet> {
  const url = `${supabaseUrl}/auth/v1/.well-known/jwks.json`;
  if (cached && cached.url === url) {
    return cached.jwks;
  }
  const jwks = createRemoteJWKSet(new URL(url));
  cached = { url, jwks };
  return jwks;
}

export class JwtError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "JwtError";
  }
}

export interface VerifiedJwt {
  sub: string;
  payload: JWTPayload;
}

/**
 * Verify a Supabase JWT and return its `sub` claim (the user UUID).
 *
 * Validates: signature against the project JWKS, `exp` not expired,
 * `iss` equals `${SUPABASE_URL}/auth/v1`, and `sub` is present.
 *
 * Throws `JwtError` on any failure. Callers should map this to a 401.
 */
export async function verifySupabaseJwt(
  token: string,
  supabaseUrl: string,
): Promise<VerifiedJwt> {
  const issuer = `${supabaseUrl}/auth/v1`;
  const jwks = getJwks(supabaseUrl);

  let payload: JWTPayload;
  try {
    const result = await jwtVerify(token, jwks, { issuer });
    payload = result.payload;
  } catch (err) {
    // jose throws specific subclasses (JWTExpired, JWSSignatureVerificationFailed,
    // etc). For the Worker's purposes they all collapse to "invalid token".
    // If we ever need to distinguish, the err.code is on the thrown object.
    throw new JwtError(`jwt verification failed: ${(err as Error).message}`);
  }

  const sub = payload.sub;
  if (typeof sub !== "string" || sub.length === 0) {
    throw new JwtError("jwt missing sub claim");
  }
  return { sub, payload };
}

/**
 * Extract the bearer token from an `Authorization: Bearer <token>`
 * header. Returns null if missing or malformed; callers should map
 * null to a 401.
 */
export function extractBearerToken(request: Request): string | null {
  const header = request.headers.get("Authorization");
  if (!header) return null;
  const match = /^Bearer\s+(.+)$/i.exec(header.trim());
  return match ? match[1].trim() : null;
}
