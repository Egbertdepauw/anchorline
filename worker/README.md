# ccrlogger-attachments Worker

Cloudflare Worker that mints presigned R2 URLs for CCRLog dive
attachments and validates Supabase JWTs. The Flutter app calls this
Worker before each upload (to get a presigned PUT URL) or download (to
get a presigned GET URL), and to delete attachments.

This Worker owns the R2 bucket. Attachment metadata still lives in
Postgres and syncs through PowerSync — the Worker does **not** touch
the database.

## Architecture in one paragraph

Object key layout is `attachments/{owner_id}/{dive_id}/{uuid}.{ext}`.
The owner_id is the Supabase user UUID (`sub` claim from the JWT) and
is the load-bearing per-user prefix: download/delete requests are
rejected unless the requested key starts with the calling user's
prefix. Presigned URLs expire in 5 minutes. Uploads are PUT directly
to R2 by the client; deletes go through the Worker's R2 binding (no
presign needed because the binding has direct write access).

## Routes

| Method | Path             | Body                                                                    | Returns                                              |
| ------ | ---------------- | ----------------------------------------------------------------------- | ---------------------------------------------------- |
| POST   | `/sign-upload`   | `{ dive_id, filename, mime_type, size_bytes }`                          | `{ object_key, upload_url, expires_at, ...usage }`   |
| POST   | `/sign-download` | `{ object_key }`                                                        | `{ download_url, expires_at }`                       |
| POST   | `/delete`        | `{ object_key }`                                                        | `{ ok: true }`                                       |
| POST   | `/usage`         | (none)                                                                  | `{ used_bytes, limit_bytes, used_files, limit_files, uploads_enabled }` |
| OPTIONS| `*`              | —                                                                       | 204 + CORS headers                                   |

All routes require `Authorization: Bearer <supabase-jwt>`. Errors are
JSON `{ error: "..." }` with appropriate 4xx/5xx status codes.

`/sign-upload` additionally refuses with:

| Status | Body                                                                                     | Meaning                                  |
| ------ | ---------------------------------------------------------------------------------------- | ---------------------------------------- |
| 503    | `{ "error": "uploads_disabled" }`                                                        | kill switch (`UPLOADS_ENABLED`) is off   |
| 429    | `{ "error": "rate_limited" }`                                                            | per-account rate limit hit               |
| 413    | `{ "error": "quota_exceeded", used_bytes, limit_bytes, used_files, limit_files }`        | the file would exceed the account quota  |

Checks run in that order. A misconfigured `QUOTA_BYTES`/`QUOTA_FILES`
fails closed with a 500 `internal_error`. `/usage` is read-only, so the kill
switch does not affect it, but it does a full R2 list and is rate-limited
on the same binding with its own budget (key `usage:<sub>`), returning
the same 429.

## Upload limits (issue #196)

Configured in `wrangler.toml`:

- `QUOTA_BYTES` / `QUOTA_FILES`: default per-account limits (integers as strings).
- `QUOTA_OVERRIDES`: JSON `{ "<user uuid>": { "bytes": n, "files": n } }`
  for accounts with their own limits. `wrangler deploy` replaces
  dashboard-edited vars, so edit it in `wrangler.toml`, not the dashboard.
- `UPLOADS_ENABLED`: kill switch; only the exact string `"true"` allows uploads.
- `SIGN_UPLOAD_LIMITER`: Workers Rate Limiting binding (20 requests per
  60 s per account) on `/sign-upload`, declared as `[[unsafe.bindings]]`
  because wrangler 3 has no first-class key for it.

Usage is measured by listing the account's objects in R2, not from a
counter, so it cannot drift.

### Kill switch runbook

To stop all uploads (abuse, a runaway client, an R2 bill spike):

1. Set `UPLOADS_ENABLED = "false"` in `wrangler.toml`.
2. Run `wrangler deploy`.

From then on every `/sign-upload` returns 503 `uploads_disabled`; the
app shows "Uploads are paused right now" and keeps the rows `failed` so
they can be retried later. Downloads, deletes and `/usage` keep working.
To turn uploads back on, set it to `"true"` and deploy again.

Editing the variable in the Cloudflare dashboard takes effect at once,
which is handy in an emergency, but the next `wrangler deploy` resets
it to the value in `wrangler.toml` (the same caveat as
`QUOTA_OVERRIDES`). After a dashboard edit, change `wrangler.toml` to
match before anyone deploys.

Second exception to the Worker freeze (2026-11-10, #196): upload limits
only. Moves to the Dart service when it takes over signing.

## Deployment

### Prerequisites

- A Cloudflare account with R2 enabled.
- `wrangler` installed: `npm i -g wrangler`.
- `wrangler login` to authenticate.

### 1. Install local deps

```bash
cd worker/
npm install
```

### 2. Create the R2 bucket

```bash
wrangler r2 bucket create ccrlogger-attachments
```

The bucket name in `wrangler.toml` (`[[r2_buckets]]` block) must match.
Change both if you want a different name.

### 3. Generate an R2 API token

In the Cloudflare dashboard:

1. Go to **R2 → Manage R2 API Tokens → Create API token**.
2. Scope it to **the `ccrlogger-attachments` bucket only**.
3. Permissions: **Object Read & Write**.
4. Copy the **Access Key ID** and **Secret Access Key** — the secret
   is only shown once.
5. Note your **Account ID** (top-right of the dashboard).

### 4. Set secrets

```bash
wrangler secret put R2_ACCESS_KEY_ID
wrangler secret put R2_SECRET_ACCESS_KEY
wrangler secret put R2_ACCOUNT_ID
wrangler secret put R2_BUCKET_NAME      # ccrlogger-attachments
wrangler secret put ALLOWED_ORIGINS     # comma-separated, e.g.:
                                        # https://app.ccrlog.example,http://localhost:*
```

### 5. Set the Supabase project URL

Either edit `wrangler.toml`'s `[vars]` block in place, or:

```bash
wrangler secret put SUPABASE_URL        # https://<project-ref>.supabase.co
```

The Worker fetches `${SUPABASE_URL}/auth/v1/.well-known/jwks.json` for
JWT verification and validates `iss == ${SUPABASE_URL}/auth/v1`.

### 6. Deploy

```bash
wrangler deploy
```

Note the deployed URL (e.g. `https://ccrlogger-attachments.<your-subdomain>.workers.dev`).

### 7. Smoke test

```bash
# Get a Supabase access token for a real user. From the Flutter app
# you can dump `Supabase.instance.client.auth.currentSession?.accessToken`,
# or use the supabase-js CLI / a curl against the auth endpoint.
TOKEN="eyJhbGciOi..."
WORKER="https://ccrlogger-attachments.<your-subdomain>.workers.dev"

# Mint an upload URL.
curl -sS -X POST "$WORKER/sign-upload" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "dive_id": "test-dive-001",
    "filename": "hello.txt",
    "mime_type": "text/plain",
    "size_bytes": 11
  }'
# => { "object_key": "attachments/<sub>/test-dive-001/<uuid>.txt",
#      "upload_url": "https://<account>.r2.cloudflarestorage.com/...",
#      "expires_at": 1700000000,
#      "used_bytes": 0, "limit_bytes": 1000000000,
#      "used_files": 0, "limit_files": 1000 }
# The four usage fields describe the account before this upload.

# PUT the file to the upload_url. Both Content-Type and Content-Length
# are part of the signature: Content-Type MUST equal the mime_type
# above and Content-Length MUST equal size_bytes (11 here), or R2
# answers 403. curl sets Content-Length from the body.
echo -n "hello world" | curl -sS -X PUT \
  -H "Content-Type: text/plain" \
  --data-binary @- \
  "<upload_url from previous response>"
# => HTTP 200, empty body.

# Mint a download URL for the same key.
curl -sS -X POST "$WORKER/sign-download" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "object_key": "<object_key from sign-upload>" }'

# Verify it: curl the returned download_url with no auth headers.

# Delete:
curl -sS -X POST "$WORKER/delete" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "object_key": "<object_key>" }'
# => { "ok": true }
```

### 8. Wire the Flutter app

Update the Flutter app's `CloudConfig.attachmentsSignerUrl` to the
deployed Worker URL. The Flutter side uses the same JWT (from the
active Supabase session) for the `Authorization: Bearer` header.

## Local dev

```bash
wrangler dev
```

`wrangler dev` reads secrets from `.dev.vars` (gitignored) — create one
with the same keys as the production secrets. The Supabase URL must
point at a real project so JWKS fetch works.

## Notes

- **Why server-generated UUIDs?** The per-user object-key prefix
  already prevents cross-user collisions, but generating UUIDs server-
  side means a buggy or malicious client can't accidentally (or
  deliberately) reuse a key from another upload.
- **Why a 5-minute presign TTL?** Short enough that a leaked URL has a
  small blast radius, long enough to cover a 25 MB upload from a dive
  boat with marginal LTE.
- **Why are deletes via the binding instead of presigned?** The R2
  binding gives the Worker direct write access without an IAM
  roundtrip, and `R2.delete` is idempotent — deleting a missing key
  succeeds. That's the right behavior for client retry paths.
- **JWKS caching:** the Worker caches the JWKS per-isolate via
  `jose`'s `createRemoteJWKSet`. Key rotations on the Supabase side
  are handled transparently on the next request.

## Adding a new MIME type

Edit `src/validation.ts` (`ALLOWED_MIME_TYPES`) and redeploy. There is
no remote-config knob on purpose — every new MIME is a new surface for
parser/preview bugs in the Flutter app, so it should be a deliberate
code change.

## Scheduled keep-alive (temporary, issue #98)

Supabase pauses a free-tier project that sees too little database
activity over 7 days. The Worker has a `scheduled` handler (cron
`23 4 * * *`, daily, set in `wrangler.toml`) that makes one read-only
request with the public anon key (`SUPABASE_ANON_KEY` in `[vars]`): a
call to the `keepalive()` database function at
`${SUPABASE_URL}/rest/v1/rpc/keepalive`, which touches no data and
returns 1 (`supabase/migrations/0018_keepalive_function.sql`). It is a
function and not a table read because the anon role has no access to any
table. Failures are logged with `console.warn` and never throw. Remove
`src/keepalive.ts`, the `scheduled` handler, the `[triggers]` block and
the `keepalive()` function when the project moves to a paid plan.

## Tests

```bash
cd worker/
npm test
```

Plain vitest in Node (no Workers test pool); `fetch` is injected, so no
network is needed.
