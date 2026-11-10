// Per-account attachment quota.
//
// Usage is measured on the objects actually in R2 under
// `attachments/{sub}/`, not on a database counter. A counter can drift
// (failed uploads, deletes that bypass the Worker, abandoned presigned
// PUTs that still land); the bucket is the one thing that can't lie
// about what is stored. The cost is a list() per sign-upload, which the
// per-account rate limiter keeps cheap.
//
// Limits come from QUOTA_BYTES / QUOTA_FILES, with optional per-account
// overrides in QUOTA_OVERRIDES (JSON: {"<sub>":{"bytes":N,"files":N}}).

import type { Env, Usage } from "./types";

type LimitEnv = Pick<Env, "QUOTA_BYTES" | "QUOTA_FILES" | "QUOTA_OVERRIDES">;

export interface Limit {
  bytes: number;
  files: number;
}

function isCount(x: unknown): x is number {
  return typeof x === "number" && Number.isInteger(x) && x >= 0;
}

function parseDefault(name: string, raw: string | undefined): number {
  // Strict digits only: Number("") is 0 and Number("1e3") is 1000, both
  // of which would silently misconfigure the limit.
  if (raw === undefined || !/^\d+$/.test(raw.trim())) {
    // Fail closed: a throw becomes a 500 and refuses the upload, rather
    // than allowing unlimited storage on a bad deploy.
    throw new Error(`${name} is not a non-negative integer`);
  }
  return Number(raw);
}

export function resolveLimit(env: LimitEnv, sub: string): Limit {
  const fallback: Limit = {
    bytes: parseDefault("QUOTA_BYTES", env.QUOTA_BYTES),
    files: parseDefault("QUOTA_FILES", env.QUOTA_FILES),
  };
  if (!env.QUOTA_OVERRIDES) return fallback;

  let parsed: unknown;
  try {
    parsed = JSON.parse(env.QUOTA_OVERRIDES);
  } catch {
    console.warn("QUOTA_OVERRIDES is not valid JSON; using default limits");
    return fallback;
  }
  if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
    console.warn("QUOTA_OVERRIDES is not a JSON object; using default limits");
    return fallback;
  }

  if (!Object.prototype.hasOwnProperty.call(parsed, sub)) return fallback;
  const entry = (parsed as Record<string, unknown>)[sub] as
    | { bytes?: unknown; files?: unknown }
    | null;
  if (entry && isCount(entry.bytes) && isCount(entry.files)) {
    return { bytes: entry.bytes, files: entry.files };
  }
  console.warn(`QUOTA_OVERRIDES entry for account ${sub} is invalid; using default limits`);
  return fallback;
}

export async function measureUsage(
  bucket: Pick<R2Bucket, "list">,
  sub: string,
): Promise<{ bytes: number; files: number }> {
  let bytes = 0;
  let files = 0;
  let cursor: string | undefined;
  for (;;) {
    const page = await bucket.list({ prefix: `attachments/${sub}/`, cursor });
    for (const obj of page.objects) {
      bytes += obj.size;
      files += 1;
    }
    if (!page.truncated) break;
    cursor = page.cursor;
  }
  return { bytes, files };
}

export async function usageFor(
  env: Pick<Env, "BUCKET" | "QUOTA_BYTES" | "QUOTA_FILES" | "QUOTA_OVERRIDES">,
  sub: string,
): Promise<Usage> {
  const limit = resolveLimit(env, sub);
  const used = await measureUsage(env.BUCKET, sub);
  return {
    used_bytes: used.bytes,
    limit_bytes: limit.bytes,
    used_files: used.files,
    limit_files: limit.files,
  };
}

export function wouldExceed(u: Usage, sizeBytes: number): boolean {
  return u.used_bytes + sizeBytes > u.limit_bytes || u.used_files + 1 > u.limit_files;
}
