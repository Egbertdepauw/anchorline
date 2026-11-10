import { afterEach, describe, expect, it, vi } from "vitest";
import { measureUsage, resolveLimit, usageFor, wouldExceed } from "./quota";

const defaults = { QUOTA_BYTES: "1000000000", QUOTA_FILES: "1000" };

type Page = { objects: { size: number }[]; truncated: boolean; cursor?: string };

// Fake bucket that serves preset pages in order and records each call.
function fakeBucket(pages: Page[]) {
  const list = vi.fn(async (_opts?: R2ListOptions) => pages.shift()!);
  return { list } as unknown as Pick<R2Bucket, "list"> & { list: typeof list };
}

afterEach(() => vi.restoreAllMocks());

describe("resolveLimit", () => {
  it("uses the default when there is no override", () =>
    expect(resolveLimit(defaults, "u1")).toEqual({ bytes: 1_000_000_000, files: 1000 }));

  it("uses the default (silently) when overrides have no entry for this sub", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    expect(
      resolveLimit({ ...defaults, QUOTA_OVERRIDES: '{"other":{"bytes":1,"files":1}}' }, "u1"),
    ).toEqual({ bytes: 1_000_000_000, files: 1000 });
    expect(warn).not.toHaveBeenCalled();
  });

  it("uses a per-account override", () =>
    expect(
      resolveLimit(
        { ...defaults, QUOTA_OVERRIDES: '{"u1":{"bytes":5000000000,"files":5000}}' },
        "u1",
      ),
    ).toEqual({ bytes: 5_000_000_000, files: 5000 }));

  it.each([
    "{not json",
    "[1,2]",
    "null",
    '{"u1":{"bytes":-1,"files":5}}',
    '{"u1":{"bytes":"5","files":5}}',
    '{"u1":{"bytes":5}}',
    '{"u1":{"bytes":1.5,"files":5}}',
    '{"u1":null}',
  ])("falls back to the default and warns once on malformed overrides: %s", (overrides) => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    expect(resolveLimit({ ...defaults, QUOTA_OVERRIDES: overrides }, "u1")).toEqual({
      bytes: 1_000_000_000,
      files: 1000,
    });
    expect(warn).toHaveBeenCalledTimes(1);
    expect(String(warn.mock.calls[0][0])).not.toContain(overrides);
  });

  it.each([
    [{ QUOTA_BYTES: "abc", QUOTA_FILES: "1000" }],
    [{ QUOTA_BYTES: "1000", QUOTA_FILES: "-1" }],
    [{ QUOTA_BYTES: "1000", QUOTA_FILES: "" }],
    [{ QUOTA_BYTES: "1.5", QUOTA_FILES: "10" }],
  ])("throws when the default limits are misconfigured: %o", (env) =>
    expect(() => resolveLimit(env, "u1")).toThrow(/QUOTA_/),
  );
});

describe("measureUsage", () => {
  it("sums sizes across pages", async () => {
    const first = Array.from({ length: 1000 }, () => ({ size: 10 }));
    const bucket = fakeBucket([
      { objects: first, truncated: true, cursor: "c1" },
      { objects: [{ size: 1 }, { size: 2 }, { size: 3 }], truncated: false },
    ]);
    expect(await measureUsage(bucket, "u1")).toEqual({ bytes: 10_006, files: 1003 });
    expect(bucket.list).toHaveBeenCalledTimes(2);
    expect(bucket.list.mock.calls[1][0]?.cursor).toBe("c1");
  });

  it("lists only the caller's prefix", async () => {
    const bucket = fakeBucket([{ objects: [], truncated: false }]);
    expect(await measureUsage(bucket, "u1")).toEqual({ bytes: 0, files: 0 });
    expect(bucket.list.mock.calls[0][0]?.prefix).toBe("attachments/u1/");
  });
});

describe("usageFor", () => {
  it("combines measured usage with the resolved limit", async () => {
    const bucket = fakeBucket([{ objects: [{ size: 7 }, { size: 3 }], truncated: false }]);
    expect(
      await usageFor(
        { BUCKET: bucket as unknown as R2Bucket, ...defaults, QUOTA_OVERRIDES: undefined },
        "u1",
      ),
    ).toEqual({ used_bytes: 10, limit_bytes: 1_000_000_000, used_files: 2, limit_files: 1000 });
  });
});

describe("wouldExceed", () => {
  it("refuses one byte over the byte limit and allows exactly at it", () => {
    const u = { used_bytes: 900, limit_bytes: 1000, used_files: 1, limit_files: 10 };
    expect(wouldExceed(u, 100)).toBe(false);
    expect(wouldExceed(u, 101)).toBe(true);
  });

  it("refuses the file that would exceed the file limit", () =>
    expect(
      wouldExceed({ used_bytes: 0, limit_bytes: 1000, used_files: 10, limit_files: 10 }, 1),
    ).toBe(true));
});
