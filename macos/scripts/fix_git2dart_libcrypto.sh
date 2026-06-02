#!/bin/sh
# git2dart_binaries libcrypto fixup (defect #3) — BUNDLE-LEVEL.
#
# git2dart_binaries (<=1.11.0) ships libssh2.1.dylib linked against the
# absolute Homebrew path /opt/homebrew/opt/openssl@3/lib/libcrypto.3.dylib and
# bundles no libcrypto. A signed/shipped .app can't load that — dyld rejects it
# with a Team-ID mismatch on dev Macs, or "Library not loaded" on Macs without
# Homebrew — so the app SIGABRTs at launch.
#
# We fix this on the *embedded* dylibs inside the built .app, NOT in the shared
# pub-cache pod source. The old Podfile approach (fix_git2dart_libcrypto)
# mutated ~/.pub-cache on every `pod install`, which left libssh2 pointing at
# @rpath/libcrypto with no libcrypto present — breaking the pure-Dart libgit2
# FFI tests (repo_test.dart, sync_orchestrator_test.dart) until `flutter pub
# get` restored the cache. Doing it here keeps the cache pristine: tests and
# the macOS build can both be green at the same time.
#
# This phase MUST run AFTER "[CP] Embed Pods Frameworks" (so the embedded
# libssh2 exists) and BEFORE Xcode's implicit final bundle codesign (so the
# re-signed dylibs are sealed into the app). It is wired in as the last build
# phase of the Runner target in project.pbxproj.
#
# When git2dart_binaries bundles its own libcrypto upstream
# (DartGit-dev/git2dart_binaries#18), delete this script, its build phase, and
# macos/vendored/.
set -e

FW="${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}"
LIBSSH2="${FW}/libssh2.1.dylib"
LIBCRYPTO="${FW}/libcrypto.3.dylib"
VENDORED="${SRCROOT}/vendored/libcrypto.3.dylib"

if [ ! -f "${LIBSSH2}" ]; then
  echo "git2dart libcrypto fixup: ${LIBSSH2} not embedded — nothing to do"
  exit 0
fi
if [ ! -f "${VENDORED}" ]; then
  echo "error: ${VENDORED} is missing — cannot fix git2dart libcrypto" >&2
  exit 1
fi

# 1. Drop our committed libcrypto next to the other pod dylibs, with an
#    @rpath install id so dyld resolves it from Contents/Frameworks.
cp -f "${VENDORED}" "${LIBCRYPTO}"
chmod u+w "${LIBCRYPTO}" "${LIBSSH2}"
install_name_tool -id "@rpath/libcrypto.3.dylib" "${LIBCRYPTO}"

# 2. Repoint the embedded libssh2 at the bundled libcrypto (only if it still
#    carries the absolute Homebrew path).
REF=$(otool -L "${LIBSSH2}" | awk '/libcrypto\.3\.dylib/{print $1; exit}')
if [ -n "${REF}" ] && [ "${REF}" != "@rpath/libcrypto.3.dylib" ]; then
  install_name_tool -change "${REF}" "@rpath/libcrypto.3.dylib" "${LIBSSH2}"
fi

# 3. Re-sign both dylibs — install_name_tool invalidated their signatures, and
#    dyld won't load a code-signed app's framework whose seal is broken. Mirror
#    CocoaPods' own embed-phase signing (same identity + flags) so Team IDs
#    match the app and the final bundle seal accepts them.
if [ "${CODE_SIGNING_ALLOWED}" != "NO" ] && [ -n "${EXPANDED_CODE_SIGN_IDENTITY:-}" ]; then
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" ${OTHER_CODE_SIGN_FLAGS:-} \
    --preserve-metadata=identifier,entitlements "${LIBCRYPTO}" "${LIBSSH2}"
fi

echo "git2dart libcrypto fixup: bundled libcrypto + repointed libssh2 in ${FW}"
