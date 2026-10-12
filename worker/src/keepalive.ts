// TEMPORARY free-tier keep-alive (issue #98).
//
// Supabase pauses a free-tier project that sees too little database
// activity over 7 days. The scheduled handler calls this once a day: one
// call to the `keepalive()` database function (migration 0018), which
// touches no data and returns 1. It is a function and not a table read
// because the anon role, the only key this Worker holds, has no access to
// any table (migration 0016).
// Remove this file, the cron trigger and the function when the project
// moves to a paid plan.

export interface KeepAliveResult {
  ok: boolean;
  status?: number;
}

export async function keepAlive(
  env: { SUPABASE_URL: string; SUPABASE_ANON_KEY: string },
  fetchFn: typeof fetch = fetch,
): Promise<KeepAliveResult> {
  try {
    const res = await fetchFn(`${env.SUPABASE_URL}/rest/v1/rpc/keepalive`, {
      method: "POST",
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
        "Content-Type": "application/json",
      },
      body: "{}",
    });
    if (!res.ok) {
      console.warn(`keepalive: Supabase returned ${res.status}`);
      return { ok: false, status: res.status };
    }
    return { ok: true, status: res.status };
  } catch (err) {
    console.warn("keepalive: request failed:", err);
    return { ok: false };
  }
}
