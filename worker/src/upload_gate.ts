// Gate in front of sign-upload: kill switch, then rate limit, then quota.
//
// Order matters: the kill switch and the limiter are cheap and must run
// before the bucket list() that the quota check needs. A throw (e.g. a
// misconfigured QUOTA_BYTES) propagates to the Worker's top-level catch,
// which turns it into a 500 and refuses the upload (fail closed).

import { usageFor, wouldExceed } from "./quota";
import type { Env, Usage } from "./types";

export type GateResult = { ok: true; usage: Usage } | { ok: false; response: Response };

// Shared by /sign-upload and /usage. Returns the 429 response when the
// key is over budget, otherwise null. Callers use distinct keys so the
// two routes keep separate budgets on the one limiter binding.
export async function rateLimitResponse(env: Env, key: string): Promise<Response | null> {
  const { success } = await env.SIGN_UPLOAD_LIMITER.limit({ key });
  return success ? null : Response.json({ error: "rate_limited" }, { status: 429 });
}

export async function gateSignUpload(
  env: Env,
  sub: string,
  sizeBytes: number,
): Promise<GateResult> {
  // Only the exact string "true" enables uploads.
  if (env.UPLOADS_ENABLED !== "true") {
    return { ok: false, response: Response.json({ error: "uploads_disabled" }, { status: 503 }) };
  }

  const limited = await rateLimitResponse(env, sub);
  if (limited) return { ok: false, response: limited };

  const usage = await usageFor(env, sub);
  if (wouldExceed(usage, sizeBytes)) {
    return {
      ok: false,
      response: Response.json({ error: "quota_exceeded", ...usage }, { status: 413 }),
    };
  }
  return { ok: true, usage };
}
