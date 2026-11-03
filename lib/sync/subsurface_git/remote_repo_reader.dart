/// App-side directory walk for the checked-out Subsurface repo. Produces
/// the path -> text map the pure [RemoteSnapshot.fromFiles] builder takes,
/// so that builder never touches `dart:io`.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Reads every regular file under [repoRoot] into the map
/// [RemoteSnapshot.fromFiles] takes: keys are POSIX paths relative to
/// [repoRoot]. `.git/` is skipped. A missing root gives an empty map.
/// A value of `null` means "present but unreadable" (not valid UTF-8, or
/// the read failed); the snapshot treats it as the old reader treated a
/// read failure, so the planner still aborts on such a dive instead of
/// overwriting it.
Future<Map<String, String?>> readRemoteRepoFiles(Directory repoRoot) async {
  final out = <String, String?>{};
  if (!repoRoot.existsSync()) return out;

  for (final entity in repoRoot.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final segments = p.split(p.relative(entity.path, from: repoRoot.path));
    if (segments.first == '.git') continue;
    final key = p.posix.joinAll(segments);
    try {
      out[key] = entity.readAsStringSync();
    } on FileSystemException {
      // Unreadable, vanished mid-walk, or not valid UTF-8 (which is also
      // what readAsStringSync throws for a decode failure). Keep the path
      // so the snapshot still sees the file exists.
      out[key] = null;
    }
  }
  return out;
}
