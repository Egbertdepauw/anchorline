// Shared types for the attachments Worker.
//
// `Env` mirrors the bindings declared in wrangler.toml plus any secrets
// set via `wrangler secret put`. Only `BUCKET` is a binding; everything
// else is a string env var. Keeping this in one place means a missing
// secret produces a TypeScript error at the point of use rather than an
// undefined-at-runtime mystery.

export interface Env {
  // R2 bucket binding (used for direct delete; presigning still goes
  // through the S3-compatible endpoint via aws4fetch).
  BUCKET: R2Bucket;

  // Supabase project URL, e.g. https://abcd.supabase.co. JWKS lives at
  // `${SUPABASE_URL}/auth/v1/.well-known/jwks.json` and `iss` claim is
  // `${SUPABASE_URL}/auth/v1`.
  SUPABASE_URL: string;

  // Supabase anon key (public by design). Used by the scheduled keep-alive.
  SUPABASE_ANON_KEY: string;

  // R2 S3-compatible credentials. These are scoped per-bucket via the
  // CF dashboard (R2 → Manage R2 API Tokens).
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  R2_ACCOUNT_ID: string;
  R2_BUCKET_NAME: string;

  // Comma-separated list of allowed CORS origins. `http://localhost:*`
  // matches any localhost port for dev convenience.
  ALLOWED_ORIGINS: string;
}

// ---- Route request/response shapes -----------------------------------------

export interface SignUploadRequest {
  dive_id: string;
  filename: string;
  mime_type: string;
  size_bytes: number;
}

export interface SignUploadResponse {
  object_key: string;
  upload_url: string;
  expires_at: number;
}

export interface SignDownloadRequest {
  object_key: string;
}

export interface SignDownloadResponse {
  download_url: string;
  expires_at: number;
}

export interface DeleteRequest {
  object_key: string;
}

export interface DeleteResponse {
  ok: true;
}

export interface ErrorResponse {
  error: string;
}
