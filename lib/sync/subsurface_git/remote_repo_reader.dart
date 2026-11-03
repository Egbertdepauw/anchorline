/// App-side directory walk for the checked-out Subsurface repo. Produces
/// the path -> text map the pure [RemoteSnapshot.fromFiles] builder takes,
/// so that builder never touches `dart:io`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads every regular file under [repoRoot] into the map
/// [RemoteSnapshot.fromFiles] takes: keys are POSIX paths relative to
/// [repoRoot]. `.git/` is skipped. A missing root gives an empty map.
/// A file that is not valid UTF-8 is skipped, as the old reader did.
Future<Map<String, String>> readRemoteRepoFiles(Directory repoRoot) async {
  final out = <String, String>{};
  if (!repoRoot.existsSync()) return out;

  for (final entity in repoRoot.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final segments = p.split(p.relative(entity.path, from: repoRoot.path));
    if (segments.first == '.git') continue;
    try {
      out[p.posix.joinAll(segments)] = entity.readAsStringSync();
    } on FormatException {
      // Not valid UTF-8; the file can't be a Subsurface text file.
    } on FileSystemException {
      // Unreadable or vanished mid-walk; skip it like any other bad file.
    }
  }
  return out;
}
