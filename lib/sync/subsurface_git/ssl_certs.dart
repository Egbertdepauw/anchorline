// CA-certificate setup for libgit2's HTTPS transport.
//
// libgit2 (used by the Subsurface Cloud sync feature) needs to be told
// where its trust anchors live on two platforms:
//
//   * Android — the system trust store is at a path libgit2 can't read.
//     git2dart's own helper extracts a bundled cacert.pem and points
//     libgit2 at it.
//   * macOS — since git2dart_binaries 1.11.2 the shipped libgit2.dylib
//     uses a statically linked OpenSSL instead of SecureTransport, so it
//     no longer sees the system keychain. Its compiled-in cert path is
//     upstream's CI build prefix, which doesn't exist on user machines,
//     and git2dart only configures certs on Android (issue #91).
//   * Linux — the release ships Ubuntu 22.04's OpenSSL 3 next to libgit2,
//     because Fedora and Arch have moved to OpenSSL 4. Its compiled-in
//     cert path (/usr/lib/ssl) only exists on Debian-family systems, so
//     Linux uses the bundled CA file too.
//
// Without this, every HTTPS clone/fetch/push fails with
// "GIT_ERROR_SSL: the SSL certificate is invalid".
//
// iOS has no in-process git (see SubsurfaceRepo.isPlatformSupported), and
// Windows is left on its libgit2 defaults.

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:git2dart/git2dart.dart';
import 'package:path_provider/path_provider.dart';

const _bundledCaAsset = 'packages/git2dart_binaries/assets/certs/cacert.pem';

/// Point libgit2 at a usable CA bundle. Call once at startup, before any
/// git network operation. The setting is process-global in libgit2, so it
/// also covers the background isolates SubsurfaceRepo runs its work on.
///
/// [certDir] is where the bundled CA file is extracted on macOS and Linux; defaults
/// to the application support directory. No-op on platforms that don't
/// need it.
Future<void> configureGitSslCerts({Directory? certDir}) async {
  if (Platform.isAndroid) {
    await PlatformSpecific.androidInitialize();
    return;
  }
  if (!Platform.isMacOS && !Platform.isLinux) return;

  // libgit2 sets up its SSL state on first use; cert locations set before
  // that are overwritten, so force initialization first.
  Libgit2.version;

  final dir = certDir ?? await getApplicationSupportDirectory();
  final certFile = File('${dir.path}/cacert.pem');
  final certData = await rootBundle.load(_bundledCaAsset);
  await certFile.create(recursive: true);
  await certFile.writeAsBytes(
    certData.buffer.asUint8List(certData.offsetInBytes, certData.lengthInBytes),
    flush: true,
  );
  Libgit2.setSSLCertLocations(file: certFile.path);
}
