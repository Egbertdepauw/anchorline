import { afterEach, describe, expect, it, vi } from "vitest";
import { presignUpload } from "./r2";

const base = {
  accountId: "acc",
  bucket: "b",
  accessKeyId: "k",
  secretAccessKey: "s",
  key: "attachments/u/d/x.pdf",
  mimeType: "application/pdf",
};

describe("presignUpload", () => {
  afterEach(() => vi.useRealTimers());

  it("signs content-length and content-type into the URL", async () => {
    const { url } = await presignUpload({ ...base, sizeBytes: 1234 });
    const signed = new URL(url).searchParams.get("X-Amz-SignedHeaders")!.split(";");
    expect(signed).toContain("content-length");
    expect(signed).toContain("content-type");
    expect(signed).toContain("host");
  });

  it("binds the declared size into the signature itself", async () => {
    vi.useFakeTimers({ now: new Date("2026-11-10T12:00:00Z") }); // pin X-Amz-Date
    const sig = async (sizeBytes: number) =>
      new URL((await presignUpload({ ...base, sizeBytes })).url).searchParams.get("X-Amz-Signature");
    // Same key + type, different length: the canonical request differs,
    // so the signature must too (not merely list the header name).
    expect(await sig(1234)).not.toEqual(await sig(1235));
    // Positive control: identical inputs are deterministic, so the
    // difference above is caused by the size alone.
    expect(await sig(1234)).toEqual(await sig(1234));
  });
});
