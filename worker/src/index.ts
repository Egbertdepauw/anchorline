// CCRLog attachments Worker — entry point.
//
// Routes:
//   POST   /sign-upload     mint a presigned R2 PUT URL
//   POST   /sign-download   mint a presigned R2 GET URL
//   POST   /delete          delete an R2 object via the BUCKET binding
//   OPTIONS *               CORS preflight
//
// Every non-preflight route requires `Authorization: Bearer <jwt>`.
// The JWT is verified against the Supabase project's JWKS; its `sub`
// claim is the owner_id used for the per-user object-key prefix.
//
// The Worker does NOT touch Postgres. Attachment metadata syncs through
// PowerSync on the Flutter side. The Worker owns R2 and only R2.

import { handlePreflight, withCors } from "./cors";
import { keepAlive } from "./keepalive";
import { extractBearerToken, JwtError, verifySupabaseJwt } from "./jwt";
import { buildObjectKey, presignDownload, presignUpload } from "./r2";
import {
  objectKeyBelongsToUser,
  parseObjectKeyBody,
  parseSignUpload,
  ValidationError,
} from "./validation";
import type {
  DeleteResponse,
  Env,
  ErrorResponse,
  SignDownloadResponse,
  SignUploadResponse,
} from "./types";

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const allowed = env.ALLOWED_ORIGINS ?? "";

    if (request.method === "OPTIONS") {
      return handlePreflight(request, allowed);
    }

    let response: Response;
    try {
      response = await dispatch(request, env, url);
    } catch (err) {
      console.error("worker error:", err);
      response = jsonError(500, "internal_error");
    }
    return withCors(response, request, allowed);
  },

  // Daily cron (see wrangler.toml, issue #98): temporary free-tier
  // keep-alive so Supabase doesn't pause the project.
  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(keepAlive(env));
  },
} satisfies ExportedHandler<Env>;

// Top-level route dispatch. Kept tiny — each handler owns its own
// validation + execution.
async function dispatch(request: Request, env: Env, url: URL): Promise<Response> {
  if (request.method !== "POST") {
    return jsonError(405, "method_not_allowed");
  }
  switch (url.pathname) {
    case "/sign-upload":
      return handleSignUpload(request, env);
    case "/sign-download":
      return handleSignDownload(request, env);
    case "/delete":
      return handleDelete(request, env);
    default:
      return jsonError(404, "not_found");
  }
}

async function handleSignUpload(request: Request, env: Env): Promise<Response> {
  const auth = await authenticate(request, env);
  if (auth instanceof Response) return auth;

  const body = await readJson(request);
  if (body instanceof Response) return body;

  let parsed;
  try {
    parsed = parseSignUpload(body);
  } catch (err) {
    return jsonError(400, (err as ValidationError).message);
  }

  const objectKey = buildObjectKey(auth.sub, parsed.diveId, parsed.ext);
  const presigned = await presignUpload({
    accountId: env.R2_ACCOUNT_ID,
    bucket: env.R2_BUCKET_NAME,
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    key: objectKey,
    mimeType: parsed.mimeType,
  });

  const payload: SignUploadResponse = {
    object_key: objectKey,
    upload_url: presigned.url,
    expires_at: presigned.expiresAt,
  };
  return Response.json(payload);
}

async function handleSignDownload(request: Request, env: Env): Promise<Response> {
  const auth = await authenticate(request, env);
  if (auth instanceof Response) return auth;

  const body = await readJson(request);
  if (body instanceof Response) return body;

  let key: string;
  try {
    key = parseObjectKeyBody(body);
  } catch (err) {
    return jsonError(400, (err as ValidationError).message);
  }
  if (!objectKeyBelongsToUser(key, auth.sub)) {
    return jsonError(403, "forbidden");
  }

  const presigned = await presignDownload({
    accountId: env.R2_ACCOUNT_ID,
    bucket: env.R2_BUCKET_NAME,
    accessKeyId: env.R2_ACCESS_KEY_ID,
    secretAccessKey: env.R2_SECRET_ACCESS_KEY,
    key,
  });

  const payload: SignDownloadResponse = {
    download_url: presigned.url,
    expires_at: presigned.expiresAt,
  };
  return Response.json(payload);
}

async function handleDelete(request: Request, env: Env): Promise<Response> {
  const auth = await authenticate(request, env);
  if (auth instanceof Response) return auth;

  const body = await readJson(request);
  if (body instanceof Response) return body;

  let key: string;
  try {
    key = parseObjectKeyBody(body);
  } catch (err) {
    return jsonError(400, (err as ValidationError).message);
  }
  if (!objectKeyBelongsToUser(key, auth.sub)) {
    return jsonError(403, "forbidden");
  }

  // The R2 binding gives the Worker direct delete access. No presign
  // dance, no extra HTTP roundtrip. R2.delete is idempotent — deleting
  // a missing key is a successful no-op, which is the right behavior
  // for a "make sure this is gone" call from a client retry path.
  await env.BUCKET.delete(key);

  const payload: DeleteResponse = { ok: true };
  return Response.json(payload);
}

// ---- helpers ---------------------------------------------------------------

interface Authed {
  sub: string;
}

async function authenticate(request: Request, env: Env): Promise<Authed | Response> {
  const token = extractBearerToken(request);
  if (!token) return jsonError(401, "missing_token");
  try {
    const verified = await verifySupabaseJwt(token, env.SUPABASE_URL);
    return { sub: verified.sub };
  } catch (err) {
    if (err instanceof JwtError) return jsonError(401, "invalid_token");
    throw err;
  }
}

async function readJson(request: Request): Promise<unknown | Response> {
  const ct = request.headers.get("Content-Type") ?? "";
  if (!ct.toLowerCase().includes("application/json")) {
    return jsonError(415, "unsupported_media_type");
  }
  try {
    return await request.json();
  } catch {
    return jsonError(400, "malformed_json");
  }
}

function jsonError(status: number, error: string): Response {
  const body: ErrorResponse = { error };
  return Response.json(body, { status });
}
