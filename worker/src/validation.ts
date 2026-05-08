// Request body validation + the MIME allowlist.
//
// The MIME allowlist is intentionally small. Adding new types is a code
// change rather than a config change because each new type means a new
// surface for parser/preview bugs in the Flutter side. Better to grow
// the list deliberately than to wildcard "any MIME you like".

export const ALLOWED_MIME_TYPES: readonly string[] = [
  "application/pdf",
  "image/jpeg",
  "image/png",
  "image/heic",
  "image/webp",
  "image/gif",
  "application/msword",
  "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  "application/vnd.ms-excel",
  "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  "text/plain",
  "application/zip",
] as const;

export const MAX_SIZE_BYTES = 25 * 1024 * 1024; // 25 MB
export const MAX_FILENAME_LEN = 255;
export const MAX_DIVE_ID_LEN = 128;

const DIVE_ID_REGEX = /^[a-zA-Z0-9_:-]+$/;
const EXT_REGEX = /^[a-z0-9]{1,6}$/;

export class ValidationError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ValidationError";
  }
}

export interface ParsedSignUpload {
  diveId: string;
  filename: string;
  mimeType: string;
  sizeBytes: number;
  ext: string; // empty string when not extractable
}

/**
 * Parse + validate the body of POST /sign-upload. Throws
 * `ValidationError` with a human-readable message on failure.
 */
export function parseSignUpload(body: unknown): ParsedSignUpload {
  if (!body || typeof body !== "object") {
    throw new ValidationError("body must be a JSON object");
  }
  const b = body as Record<string, unknown>;

  const diveId = b.dive_id;
  if (typeof diveId !== "string" || diveId.length === 0 || diveId.length > MAX_DIVE_ID_LEN) {
    throw new ValidationError("dive_id must be 1..128 chars");
  }
  if (!DIVE_ID_REGEX.test(diveId)) {
    throw new ValidationError("dive_id contains invalid characters");
  }

  const filename = b.filename;
  if (typeof filename !== "string" || filename.length === 0 || filename.length > MAX_FILENAME_LEN) {
    throw new ValidationError("filename must be 1..255 chars");
  }
  if (filename.includes("/") || filename.includes("\\")) {
    throw new ValidationError("filename must not contain path separators");
  }

  const mimeType = b.mime_type;
  if (typeof mimeType !== "string" || !ALLOWED_MIME_TYPES.includes(mimeType)) {
    throw new ValidationError("mime_type not allowed");
  }

  const sizeBytes = b.size_bytes;
  if (
    typeof sizeBytes !== "number" ||
    !Number.isInteger(sizeBytes) ||
    sizeBytes < 1 ||
    sizeBytes > MAX_SIZE_BYTES
  ) {
    throw new ValidationError(`size_bytes must be an integer in [1, ${MAX_SIZE_BYTES}]`);
  }

  return {
    diveId,
    filename,
    mimeType,
    sizeBytes,
    ext: extractExtension(filename),
  };
}

export function parseObjectKeyBody(body: unknown): string {
  if (!body || typeof body !== "object") {
    throw new ValidationError("body must be a JSON object");
  }
  const key = (body as Record<string, unknown>).object_key;
  if (typeof key !== "string" || key.length === 0 || key.length > 1024) {
    throw new ValidationError("object_key must be 1..1024 chars");
  }
  // No path traversal. Also no leading slash — R2 keys are bare strings,
  // and any client-side bug that emits "//foo" should be a hard reject.
  if (key.includes("..") || key.startsWith("/")) {
    throw new ValidationError("object_key has invalid shape");
  }
  return key;
}

/**
 * Extract a lowercase, alphanumeric, ≤6-char extension from a filename.
 * Returns "" if extraction fails — the caller stores extensionless
 * objects under the {uuid} alone, which is fine, R2 doesn't care.
 */
export function extractExtension(filename: string): string {
  const dot = filename.lastIndexOf(".");
  if (dot < 0 || dot === filename.length - 1) return "";
  const ext = filename.slice(dot + 1).toLowerCase();
  return EXT_REGEX.test(ext) ? ext : "";
}

/**
 * Confirm `key` is owned by `sub` — i.e. starts with the per-user
 * prefix. This is the only authorization check the Worker can make on
 * download/delete, since the database row lives in Postgres which the
 * Worker doesn't touch. The per-user prefix is the load-bearing part.
 */
export function objectKeyBelongsToUser(key: string, sub: string): boolean {
  return key.startsWith(`attachments/${sub}/`);
}
