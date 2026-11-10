// Verifies that R2 enforces the Content-Length / Content-Type bound into
// presigned upload URLs. Run manually AFTER deploying the Worker. Two modes:
//
// 1. Worker mode (exercises /sign-upload end to end):
//    WORKER=https://<worker> TOKEN=<supabase access token> node worker/scripts/verify-signed-put.mjs
//    (or instead of TOKEN: SUPABASE_URL, SUPABASE_ANON_KEY, ANCHORLINE_EMAIL, ANCHORLINE_PASSWORD)
//
// 2. R2-direct mode (no login; presigns locally, keys under verify/):
//    R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_BUCKET_NAME=... \
//      node worker/scripts/verify-signed-put.mjs
//    Used when WORKER is not set. Tests R2's enforcement, not the Worker's code.
//
// Never prints credentials, tokens or presigned URLs.

import { AwsClient, AwsV4Signer } from "aws4fetch";

const {
  WORKER: WORKER_RAW, TOKEN, SUPABASE_URL, SUPABASE_ANON_KEY, ANCHORLINE_EMAIL, ANCHORLINE_PASSWORD,
  R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME,
} = process.env;
const WORKER = WORKER_RAW?.replace(/\/+$/, "");
const DIVE_ID = "00000000-0000-4000-8000-000000000196"; // synthetic
const R2_DIRECT = !WORKER && R2_ACCOUNT_ID && R2_ACCESS_KEY_ID && R2_SECRET_ACCESS_KEY && R2_BUCKET_NAME;

if (!WORKER && !R2_DIRECT) {
  console.error("Set WORKER (Worker mode) or R2_ACCOUNT_ID + R2_ACCESS_KEY_ID + R2_SECRET_ACCESS_KEY + R2_BUCKET_NAME (R2-direct mode).");
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

const token = R2_DIRECT ? null : await getToken();

async function workerPost(path, body) {
  return fetch(`${WORKER}${path}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
}

// R2-direct signing. Must stay in step with presignUpload / r2Endpoint in
// worker/src/r2.ts (same signer options, headers, TTL and key encoding).
async function presignLocal(key, mimeType, sizeBytes) {
  const safeKey = key.split("/").map((s) => encodeURIComponent(s)).join("/");
  const url = new URL(`https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${R2_BUCKET_NAME}/${safeKey}`);
  url.searchParams.set("X-Amz-Expires", "300");
  const signed = await new AwsV4Signer({
    method: "PUT",
    url: url.toString(),
    headers: { "Content-Type": mimeType, "Content-Length": String(sizeBytes) },
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
    signQuery: true,
    allHeaders: true,
  }).sign();
  return signed.url.toString();
}

async function cleanup(key) {
  let status;
  if (R2_DIRECT) {
    const client = new AwsClient({
      accessKeyId: R2_ACCESS_KEY_ID, secretAccessKey: R2_SECRET_ACCESS_KEY, service: "s3", region: "auto",
    });
    const safeKey = key.split("/").map((s) => encodeURIComponent(s)).join("/");
    status = (await client.fetch(
      `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${R2_BUCKET_NAME}/${safeKey}`,
      { method: "DELETE" },
    )).status;
  } else {
    status = (await workerPost("/delete", { object_key: key })).status;
  }
  if (status < 200 || status >= 300) console.warn(`  warning: cleanup of ${key} failed (${status}) - delete it manually`);
}

// Signs for (signedMime, signedSize), PUTs `body` with `putMime`, returns
// the PUT status; deletes the object if it was stored.
async function attempt(signedMime, signedSize, putMime, body) {
  let object_key, upload_url;
  if (R2_DIRECT) {
    object_key = `verify/signed-put-${crypto.randomUUID()}.txt`;
    upload_url = await presignLocal(object_key, signedMime, signedSize);
  } else {
    const res = await workerPost("/sign-upload", {
      dive_id: DIVE_ID,
      filename: "verify.txt",
      mime_type: signedMime,
      size_bytes: signedSize,
    });
    if (!res.ok) throw new Error(`/sign-upload failed: ${res.status}`);
    ({ object_key, upload_url } = await res.json());
  }
  const put = await fetch(upload_url, { method: "PUT", headers: { "Content-Type": putMime }, body });
  if (put.status >= 200 && put.status < 300) await cleanup(object_key);
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
