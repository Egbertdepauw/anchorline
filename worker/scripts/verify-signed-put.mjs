// Verifies that R2 enforces the Content-Length / Content-Type bound into
// presigned upload URLs. Run manually AFTER deploying the Worker:
//
//   WORKER=https://<worker> TOKEN=<supabase access token> node worker/scripts/verify-signed-put.mjs
//   (or instead of TOKEN: SUPABASE_URL, SUPABASE_ANON_KEY, ANCHORLINE_EMAIL, ANCHORLINE_PASSWORD)
//
// Never prints the token, password or presigned URLs.

const { WORKER: WORKER_RAW, TOKEN, SUPABASE_URL, SUPABASE_ANON_KEY, ANCHORLINE_EMAIL, ANCHORLINE_PASSWORD } = process.env;
const WORKER = WORKER_RAW?.replace(/\/+$/, "");
const DIVE_ID = "00000000-0000-4000-8000-000000000196"; // synthetic

if (!WORKER) {
  console.error("Set WORKER to the Worker base URL.");
  process.exit(2);
}

async function getToken() {
  if (TOKEN) return TOKEN;
  if (!SUPABASE_URL || !SUPABASE_ANON_KEY || !ANCHORLINE_EMAIL || !ANCHORLINE_PASSWORD) {
    console.error("Set TOKEN, or SUPABASE_URL + SUPABASE_ANON_KEY + ANCHORLINE_EMAIL + ANCHORLINE_PASSWORD.");
    process.exit(2);
  }
  const res = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: { apikey: SUPABASE_ANON_KEY, "Content-Type": "application/json" },
    body: JSON.stringify({ email: ANCHORLINE_EMAIL, password: ANCHORLINE_PASSWORD }),
  });
  if (!res.ok) {
    console.error(`Supabase sign-in failed: ${res.status}`);
    process.exit(2);
  }
  return (await res.json()).access_token;
}

const token = await getToken();

async function workerPost(path, body) {
  return fetch(`${WORKER}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

// Signs for (signedMime, signedSize), PUTs `body` with `putMime`, returns
// the PUT status and the object key; deletes the object if it was stored.
async function attempt(signedMime, signedSize, putMime, body) {
  const res = await workerPost("/sign-upload", {
    dive_id: DIVE_ID,
    filename: "verify.txt",
    mime_type: signedMime,
    size_bytes: signedSize,
  });
  if (!res.ok) throw new Error(`/sign-upload failed: ${res.status}`);
  const { object_key, upload_url } = await res.json();
  const put = await fetch(upload_url, { method: "PUT", headers: { "Content-Type": putMime }, body });
  if (put.status >= 200 && put.status < 300) {
    const del = await workerPost("/delete", { object_key });
    if (!del.ok) console.warn(`  warning: cleanup of ${object_key} failed (${del.status}) - delete it manually`);
  }
  return { status: put.status };
}

const cases = [
  { name: "matching size and type", expect: 200, run: () => attempt("text/plain", 11, "text/plain", "hello world") },
  { name: "body larger than signed size", expect: 403, run: () => attempt("text/plain", 11, "text/plain", "hello world!!") },
  { name: "Content-Type differs from signed", expect: 403, run: () => attempt("text/plain", 11, "text/html", "hello world") },
];

let failed = false;
let sizeNotEnforced = false;
for (const [i, c] of cases.entries()) {
  try {
    const { status } = await c.run();
    const pass = status === c.expect;
    if (!pass) failed = true;
    if (i === 1 && status >= 200 && status < 300) sizeNotEnforced = true;
    console.log(`case ${i + 1} (${c.name}): expected ${c.expect}, got ${status} ${pass ? "PASS" : "FAIL"}`);
  } catch (err) {
    failed = true;
    console.log(`case ${i + 1} (${c.name}): ERROR ${err.message} FAIL`);
  }
}

if (sizeNotEnforced) {
  console.error("R2 does NOT enforce the signed Content-Length - roll back (npx wrangler rollback)");
}
process.exit(failed ? 1 : 0);
