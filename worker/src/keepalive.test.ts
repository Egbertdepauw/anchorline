import { describe, expect, it, vi } from "vitest";
import { keepAlive } from "./keepalive";

const env = { SUPABASE_URL: "https://x.supabase.co", SUPABASE_ANON_KEY: "anon-key" };

describe("keepAlive", () => {
  it("returns success on a 200 response", async () => {
    const f = vi.fn().mockResolvedValue(new Response("[]", { status: 200 }));
    expect(await keepAlive(env, f)).toEqual({ ok: true, status: 200 });
  });

  it("returns a failed result on non-2xx without throwing", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const f = vi.fn().mockResolvedValue(new Response("nope", { status: 503 }));
    expect(await keepAlive(env, f)).toEqual({ ok: false, status: 503 });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it("returns a failed result when fetch rejects", async () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    const f = vi.fn().mockRejectedValue(new Error("offline"));
    const r = await keepAlive(env, f);
    expect(r.ok).toBe(false);
    expect(r.status).toBeUndefined();
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
  });

  it("calls the keepalive RPC with both auth headers", async () => {
    const f = vi.fn().mockResolvedValue(new Response("1", { status: 200 }));
    await keepAlive(env, f);
    const [url, init] = f.mock.calls[0];
    // The anon role has no access to any table (migration 0016), so the
    // keep-alive calls a function granted to anon instead.
    expect(url).toBe("https://x.supabase.co/rest/v1/rpc/keepalive");
    expect(init.method).toBe("POST");
    const h = new Headers(init.headers);
    expect(h.get("apikey")).toBe("anon-key");
    expect(h.get("Authorization")).toBe("Bearer anon-key");
  });
});
