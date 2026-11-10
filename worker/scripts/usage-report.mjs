// One-off per-account R2 attachment usage report (bytes and files per owner).
// Run with your own R2 credentials in the environment:
//
//   R2_ACCOUNT_ID=... R2_ACCESS_KEY_ID=... R2_SECRET_ACCESS_KEY=... R2_BUCKET_NAME=... \
//     node worker/scripts/usage-report.mjs > worker/usage-report.csv
//
// stdout is a CSV (owner_id,bytes,files) sorted by bytes descending; the
// totals line goes to stderr. Never prints credentials or signed requests.

import { AwsClient } from "aws4fetch";
import { fileURLToPath } from "node:url";

const decodeXml = (s) =>
  s
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-fA-F]+);/g, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&amp;/g, "&");

// Parses one ListObjectsV2 response page.
export function parseListPage(xml) {
  const objects = [];
  for (const m of xml.matchAll(/<Contents>([\s\S]*?)<\/Contents>/g)) {
    const key = /<Key>([\s\S]*?)<\/Key>/.exec(m[1]);
    const size = /<Size>(\d+)<\/Size>/.exec(m[1]);
    if (key && size) objects.push({ key: decodeXml(key[1]), size: Number(size[1]) });
  }
  const truncated = /<IsTruncated>\s*true\s*<\/IsTruncated>/.test(xml);
  const next = /<NextContinuationToken>([\s\S]*?)<\/NextContinuationToken>/.exec(xml);
  return { objects, truncated, nextToken: next ? decodeXml(next[1]) : null };
}

// attachments/{owner_id}/{dive_id}/{uuid}.{ext} -> owner_id, else "(unparsed)".
export function ownerOf(key) {
  const parts = key.split("/");
  return parts.length >= 4 && parts[1] ? parts[1] : "(unparsed)";
}

async function main() {
  const names = ["R2_ACCOUNT_ID", "R2_ACCESS_KEY_ID", "R2_SECRET_ACCESS_KEY", "R2_BUCKET_NAME"];
  const missing = names.filter((n) => !process.env[n]);
  if (missing.length) {
    console.error(`Missing environment variables: ${missing.join(", ")}`);
    process.exit(2);
  }
  const { R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_NAME } = process.env;

  const client = new AwsClient({
    accessKeyId: R2_ACCESS_KEY_ID,
    secretAccessKey: R2_SECRET_ACCESS_KEY,
    service: "s3",
    region: "auto",
  });
  const base = `https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${R2_BUCKET_NAME}`;

  const byOwner = new Map();
  let token = null;
  do {
    const qs = new URLSearchParams({ "list-type": "2", prefix: "attachments/" });
    if (token) qs.set("continuation-token", token);
    const res = await client.fetch(`${base}?${qs}`);
    const body = await res.text();
    if (!res.ok) {
      const code = /<Code>([\s\S]*?)<\/Code>/.exec(body)?.[1] ?? "";
      const msg = /<Message>([\s\S]*?)<\/Message>/.exec(body)?.[1] ?? "";
      console.error(`ListObjectsV2 failed: ${res.status} ${decodeXml(code)} ${decodeXml(msg)}`.trim());
      process.exit(1);
    }
    const page = parseListPage(body);
    for (const { key, size } of page.objects) {
      const owner = ownerOf(key);
      const e = byOwner.get(owner) ?? { bytes: 0, files: 0 };
      e.bytes += size;
      e.files += 1;
      byOwner.set(owner, e);
    }
    token = page.truncated ? page.nextToken : null;
  } while (token);

  const rows = [...byOwner].sort((a, b) => b[1].bytes - a[1].bytes);
  console.log("owner_id,bytes,files");
  let bytes = 0;
  let files = 0;
  for (const [owner, e] of rows) {
    console.log(`${owner},${e.bytes},${e.files}`);
    bytes += e.bytes;
    files += e.files;
  }
  console.error(
    `Totals: ${rows.length} accounts, ${files} files, ${bytes} bytes (${(bytes / 1e9).toFixed(3)} GB)`,
  );
}

if (process.argv[1] === fileURLToPath(import.meta.url)) await main();
