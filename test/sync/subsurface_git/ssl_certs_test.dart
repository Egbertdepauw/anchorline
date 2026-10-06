// Real-network test for libgit2's CA configuration on macOS (issue #91).
//
// Every other subsurface_git test talks to `file://` remotes, which never
// touch TLS — that's how the git2dart_binaries 1.12.1 bump shipped with
// HTTPS sync broken on macOS. This one clones a small public repo over
// HTTPS, so a binaries bump that loses its trust anchors fails here.
//
// macOS only: CI (Linux) uses the system OpenSSL paths and isn't affected.
// Skips itself when there's no network.

@TestOn('mac-os')
library;

import 'dart:io';

import 'package:ccrlogger/sync/subsurface_git/ssl_certs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:git2dart/git2dart.dart';

const _probeHost = 'github.com';
const _probeUrl = 'https://github.com/octocat/Hello-World.git';

Future<bool> _online() async {
  try {
    return (await InternetAddress.lookup(_probeHost)).isNotEmpty;
  } on SocketException {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('HTTPS clone succeeds once the bundled CA file is configured',
      () async {
    if (!await _online()) {
      markTestSkipped('no network — cannot reach $_probeHost');
      return;
    }

    final certDir = Directory.systemTemp.createTempSync('ccrlog_certs_');
    final cloneDir = Directory.systemTemp.createTempSync('ccrlog_https_');
    addTearDown(() {
      certDir.deleteSync(recursive: true);
      cloneDir.deleteSync(recursive: true);
    });

    await configureGitSslCerts(certDir: certDir);

    expect(File('${certDir.path}/cacert.pem').existsSync(), isTrue);

    final repo = Repository.clone(url: _probeUrl, localPath: cloneDir.path);
    addTearDown(repo.free);
    expect(repo.head.target.sha, isNotEmpty);
  });
}
