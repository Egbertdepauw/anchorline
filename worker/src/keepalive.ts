// TEMPORARY free-tier keep-alive (issue #98).
//
// Supabase pauses a free-tier project that sees too little database
// activity over 7 days. The scheduled handler calls this once a day: one
// cheap read-only REST request. With the anon key and no signed-in user,
// RLS returns an empty list, which is expected and counts as success.
// Remove this file and the cron trigger when the project moves to a paid
// plan.

export interface KeepAliveResult {
  ok: boolean;
  status?: number;
}

export async function keepAlive(
  env: { SUPABASE_URL: string; SUPABASE_ANON_KEY: string },
  fetchFn: typeof fetch = fetch,
): Promise<KeepAliveResult> {
  try {
    const res = await fetchFn(`${env.SUPABASE_URL}/rest/v1/dives?select=id&limit=1`, {
      method: "GET",
      headers: {
        apikey: env.SUPABASE_ANON_KEY,
        Authorization: `Bearer ${env.SUPABASE_ANON_KEY}`,
      },
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
