import { describe, expect, it, vi } from "vitest";
import { gateSignUpload } from "./upload_gate";
import type { Env } from "./types";

function fakeEnv(opts: { enabled?: string; allowed?: boolean; usedBytes?: number } = {}) {
  const list = vi.fn(async () => ({
    objects: [{ size: opts.usedBytes ?? 0 }],
    truncated: false,
  }));
  const limit = vi.fn(async (_o: { key: string }) => ({ success: opts.allowed ?? true }));
  const env = {
    BUCKET: { list },
    SIGN_UPLOAD_LIMITER: { limit },
    QUOTA_BYTES: "1000000000",
    QUOTA_FILES: "1000",
    UPLOADS_ENABLED: "enabled" in opts ? opts.enabled : "true",
  } as unknown as Env;
  return { env, list, limit };
}

describe("gateSignUpload", () => {
  it("returns 503 uploads_disabled without touching limiter or bucket", async () => {
    const { env, list, limit } = fakeEnv({ enabled: "false" });
    const r = await gateSignUpload(env, "u1", 10);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.response.status).toBe(503);
    expect(await r.response.json()).toEqual({ error: "uploads_disabled" });
    expect(limit).not.toHaveBeenCalled();
    expect(list).not.toHaveBeenCalled();
  });

  it.each([undefined, "TRUE", "1", ""])("treats UPLOADS_ENABLED=%j as disabled", async (v) => {
    const { env } = fakeEnv({ enabled: v });
    const r = await gateSignUpload(env, "u1", 10);
    expect(r.ok).toBe(false);
    if (!r.ok) expect(r.response.status).toBe(503);
  });

  it("returns 429 rate_limited and does not list the bucket", async () => {
    const { env, list } = fakeEnv({ allowed: false });
    const r = await gateSignUpload(env, "u1", 10);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.response.status).toBe(429);
    expect(await r.response.json()).toEqual({ error: "rate_limited" });
    expect(list).not.toHaveBeenCalled();
  });

  it("calls the limiter keyed by sub", async () => {
    const { env, limit } = fakeEnv();
    await gateSignUpload(env, "user-42", 10);
    expect(limit).toHaveBeenCalledWith({ key: "user-42" });
  });

  it("returns 413 quota_exceeded with the five fields", async () => {
    const { env } = fakeEnv({ usedBytes: 999_999_990 });
    const r = await gateSignUpload(env, "u1", 11);
    expect(r.ok).toBe(false);
    if (r.ok) return;
    expect(r.response.status).toBe(413);
    expect(await r.response.json()).toEqual({
      error: "quota_exceeded",
      used_bytes: 999_999_990,
      limit_bytes: 1_000_000_000,
      used_files: 1,
      limit_files: 1000,
    });
  });

  it("passes under the limit with usage excluding the new file", async () => {
    const { env } = fakeEnv({ usedBytes: 500 });
    const r = await gateSignUpload(env, "u1", 10);
    expect(r).toEqual({
      ok: true,
      usage: { used_bytes: 500, limit_bytes: 1_000_000_000, used_files: 1, limit_files: 1000 },
    });
  });

  it("throws (fail closed) on misconfigured quota", async () => {
    const { env } = fakeEnv();
    (env as { QUOTA_BYTES: string }).QUOTA_BYTES = "";
    await expect(gateSignUpload(env, "u1", 10)).rejects.toThrow();
  });
});
