// CORS handling.
//
// The Flutter app calls this Worker from both native (where CORS does
// not apply) and from the Flutter web build (where it does). The
// allowed-origins list is configured via the ALLOWED_ORIGINS env var
// rather than hard-coded so dev/staging/prod can each lock down to their
// own front-end domain.
//
// Wildcard support is intentionally narrow: `http://localhost:*` matches
// any localhost port, nothing else. We don't support general wildcards
// because they're an easy way to accidentally open the API to the world.

const ALLOWED_METHODS = "GET, POST, OPTIONS";
const ALLOWED_HEADERS = "Authorization, Content-Type";
const PREFLIGHT_MAX_AGE = "600";

export function isOriginAllowed(origin: string | null, allowedList: string): boolean {
  if (!origin) return false;
  const entries = allowedList.split(",").map((s) => s.trim()).filter(Boolean);
  for (const entry of entries) {
    if (entry === origin) return true;
    // Localhost wildcard: `http://localhost:*` matches any port.
    if (entry === "http://localhost:*" && /^http:\/\/localhost(:\d+)?$/.test(origin)) {
      return true;
    }
    if (entry === "https://localhost:*" && /^https:\/\/localhost(:\d+)?$/.test(origin)) {
      return true;
    }
  }
  return false;
}

export function corsHeaders(origin: string | null, allowedList: string): Record<string, string> {
  const headers: Record<string, string> = {
    "Vary": "Origin",
  };
  if (origin && isOriginAllowed(origin, allowedList)) {
    headers["Access-Control-Allow-Origin"] = origin;
    headers["Access-Control-Allow-Methods"] = ALLOWED_METHODS;
    headers["Access-Control-Allow-Headers"] = ALLOWED_HEADERS;
    headers["Access-Control-Max-Age"] = PREFLIGHT_MAX_AGE;
  }
  return headers;
}

export function handlePreflight(request: Request, allowedList: string): Response {
  const origin = request.headers.get("Origin");
  // 204 No Content for preflight is the canonical response. We attach
  // CORS headers only if the origin matches; otherwise the browser will
  // (correctly) refuse to make the real request.
  return new Response(null, {
    status: 204,
    headers: corsHeaders(origin, allowedList),
  });
}

export function withCors(response: Response, request: Request, allowedList: string): Response {
  const origin = request.headers.get("Origin");
  const extra = corsHeaders(origin, allowedList);
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(extra)) {
    headers.set(k, v);
  }
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
