// R2 presigned URL minting.
//
// We sign against R2's S3-compatible endpoint using aws4fetch. The R2
// binding (env.BUCKET) gives the Worker direct read/write/delete access
// to the bucket without IAM, so deletes are a one-liner — but the
// client uploads/downloads the bytes directly to R2 (not proxied
// through the Worker), which means we have to mint a presigned URL the
// client can hit.
//
// Why presigned PUT instead of streaming through the Worker? Two
// reasons: (1) Workers have a request body size cap and cost CPU per
// byte, (2) presigned PUT lets the client retry uploads with HTTP-level
// resumability and the Worker stays out of the data path entirely.
//
// Why a 5-minute TTL? Short enough that a leaked URL has minimal blast
// radius; long enough to cover a slow mobile upload of a 25 MB file
// from a dive boat with marginal LTE. If a client takes >5 minutes per
// chunk it's a bigger problem.

import { AwsClient } from "aws4fetch";

const PRESIGN_TTL_SECONDS = 300;

function r2Endpoint(accountId: string, bucket: string, key: string): string {
  // R2's S3-compatible endpoint. The bucket is part of the path, not
  // the host (path-style addressing). `key` is appended as-is; aws4fetch
  // handles signing the URL-encoded form correctly.
  const safeKey = key
    .split("/")
    .map((segment) => encodeURIComponent(segment))
    .join("/");
  return `https://${accountId}.r2.cloudflarestorage.com/${bucket}/${safeKey}`;
}

function makeClient(accessKeyId: string, secretAccessKey: string): AwsClient {
  // The "auto" region is what R2 expects — it isn't a real AWS region,
  // but the SigV4 algorithm requires *something* there.
  return new AwsClient({
    accessKeyId,
    secretAccessKey,
    service: "s3",
    region: "auto",
  });
}

export interface PresignParams {
  accountId: string;
  bucket: string;
  accessKeyId: string;
  secretAccessKey: string;
  key: string;
}

export interface PresignUploadParams extends PresignParams {
  mimeType: string;
}

export interface PresignedUrl {
  url: string;
  expiresAt: number; // unix timestamp seconds
}

/**
 * Mint a presigned PUT URL for `key`. The client must use the exact
 * Content-Type header it tells us about — that's part of the signature,
 * so a mismatch will get a 403 from R2. We sign Content-Type into the
 * URL deliberately to prevent a client claiming "image/png" and then
 * uploading something else.
 */
export async function presignUpload(params: PresignUploadParams): Promise<PresignedUrl> {
  const client = makeClient(params.accessKeyId, params.secretAccessKey);
  const baseUrl = r2Endpoint(params.accountId, params.bucket, params.key);
  const url = new URL(baseUrl);
  url.searchParams.set("X-Amz-Expires", String(PRESIGN_TTL_SECONDS));

  const signedRequest = await client.sign(
    new Request(url.toString(), {
      method: "PUT",
      headers: {
        "Content-Type": params.mimeType,
      },
    }),
    {
      aws: { signQuery: true },
      // signQuery moves the auth into the URL query string, which is
      // exactly the presigned-URL shape the client needs.
    },
  );

  return {
    url: signedRequest.url,
    expiresAt: Math.floor(Date.now() / 1000) + PRESIGN_TTL_SECONDS,
  };
}

/**
 * Mint a presigned GET URL for `key`. Same TTL as upload.
 */
export async function presignDownload(params: PresignParams): Promise<PresignedUrl> {
  const client = makeClient(params.accessKeyId, params.secretAccessKey);
  const baseUrl = r2Endpoint(params.accountId, params.bucket, params.key);
  const url = new URL(baseUrl);
  url.searchParams.set("X-Amz-Expires", String(PRESIGN_TTL_SECONDS));

  const signedRequest = await client.sign(
    new Request(url.toString(), { method: "GET" }),
    { aws: { signQuery: true } },
  );

  return {
    url: signedRequest.url,
    expiresAt: Math.floor(Date.now() / 1000) + PRESIGN_TTL_SECONDS,
  };
}

/**
 * Build the canonical object key for a fresh upload. The UUID is
 * generated *server-side* — never trust a client-supplied UUID, because
 * a malicious client could collide with another user's key (the
 * per-user prefix already prevents that, but a server-generated UUID is
 * one less thing to reason about).
 */
export function buildObjectKey(ownerId: string, diveId: string, ext: string): string {
  const uuid = crypto.randomUUID();
  const suffix = ext ? `.${ext}` : "";
  return `attachments/${ownerId}/${diveId}/${uuid}${suffix}`;
}
