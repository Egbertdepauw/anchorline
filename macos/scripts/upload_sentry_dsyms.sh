#!/usr/bin/env bash
#
# Upload macOS (and any present iOS) debug symbols to Sentry so native crash
# and app-hang frames in production reports symbolicate, instead of showing
# "<redacted> in unknown file" (issue #4, part 2).
#
# Run this AFTER building a release archive, e.g.:
#   flutter build macos --release
#   # then archive in Xcode Organizer, or `xcodebuild -workspace ... archive`
#
# The Sentry auth token is a secret and never lives in the repo. Put it in a
# gitignored env file once:
#   cp macos/scripts/sentry.env.example macos/scripts/sentry.env.local
#   # edit sentry.env.local, paste your sntrys_… org token
# then simply run:
#   ./macos/scripts/upload_sentry_dsyms.sh
#
# Org / project slugs default from pubspec.yaml's `sentry:` block; override
# with SENTRY_ORG / SENTRY_PROJECT (or the env file) if they ever change.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"

ENV_FILE="${SENTRY_ENV_FILE:-macos/scripts/sentry.env.local}"
if [[ -f "$ENV_FILE" ]]; then
  # `set -a` exports everything the file defines without echoing any values.
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
  cat >&2 <<EOF
error: SENTRY_AUTH_TOKEN is not set.

  Create the gitignored token file and paste your Sentry ORG token into it:
    cp macos/scripts/sentry.env.example $ENV_FILE

  The token starts with 'sntrys_' (~200 chars, scope project:releases). A
  short 32-hex value is NOT a token and will fail with 401.
EOF
  exit 1
fi

# A modern 'sntrys_' org token embeds and self-routes its own region, so
# forcing SENTRY_URL can mis-route the upload — make sure it is unset.
unset SENTRY_URL 2>/dev/null || true

echo "→ Uploading debug symbols via sentry_dart_plugin"
echo "  org=${SENTRY_ORG:-<from pubspec>} project=${SENTRY_PROJECT:-<from pubspec>}"
dart run sentry_dart_plugin
echo "✓ Done. Verify in Sentry → Settings → Debug Files (look for the new UUIDs)."
