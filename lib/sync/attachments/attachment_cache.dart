/// On-disk LRU cache for downloaded attachment bytes.
///
/// Backed by a flat directory of files named after a sanitized form of
/// the R2 object key. Eviction is by `lastModified` — every successful
/// `get` also touches the file's mtime so freshly-read files survive
/// the next eviction sweep.
///
/// Capped at 500 MB by default. The cap is approximate: we evict on
/// every `put` until the total drops below the cap, but we don't
/// re-evict on `get`, and a single file larger than the cap will be
/// stored anyway (the alternative — refusing to cache it — would force
/// every read of that one big file to re-download, which is worse).
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AttachmentCache {
  static const int defaultMaxBytes = 500 * 1024 * 1024;

  final int _maxBytes;
  Directory? _root;
  // When the caller passes a directory in (tests, mainly) we use it
  // verbatim and skip the path_provider lookup. The Future is memoized
  // so concurrent first-time `get`/`put` calls don't race init().
  final Directory? _injectedRoot;
  Future<void>? _initFuture;

  /// [rootDirectory] overrides the default `getApplicationCacheDirectory()/
  /// attachments/` location — handy for tests pointing at a tmpdir.
  AttachmentCache({
    Directory? rootDirectory,
    int? maxBytes,
  })  : _maxBytes = maxBytes ?? defaultMaxBytes,
        _injectedRoot = rootDirectory;

  /// Resolves the cache root, creating the directory if needed. Idempotent.
  Future<void> init() {
    return _initFuture ??= _doInit();
  }

  Future<void> _doInit() async {
    final root = _injectedRoot ??
        Directory(p.join(
          (await getApplicationCacheDirectory()).path,
          'attachments',
        ));
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    _root = root;
  }

  /// Returns the cached file for [key] or null if not cached.
  /// On a hit, touches the file's mtime so subsequent eviction sees it
  /// as recently-used.
  Future<File?> get(String key) async {
    await init();
    final file = _fileFor(key);
    if (!await file.exists()) return null;
    try {
      // Touch mtime — the cheapest cross-platform LRU bump.
      await file.setLastModified(DateTime.now());
    } catch (_) {
      // Some test FS layers don't implement setLastModified; the cache
      // still works, eviction order is just less precise.
    }
    return file;
  }

  /// Moves [source] into the cache under [key], evicting older entries
  /// if the cache exceeds its byte cap. Returns the new cached file.
  ///
  /// We rename when possible (single inode op, atomic on POSIX) and
  /// fall back to copy+delete if rename fails — `tmpdir` and the cache
  /// can be on different filesystems on some hosts.
  Future<File> put(String key, File source) async {
    await init();
    final dest = _fileFor(key);
    if (await dest.exists()) {
      await dest.delete();
    }
    try {
      await source.rename(dest.path);
    } on FileSystemException {
      await source.copy(dest.path);
      try {
        await source.delete();
      } catch (_) {
        // Source was probably the caller's responsibility; their
        // failure to clean it up isn't our problem.
      }
    }
    await _evictIfOverCap();
    return dest;
  }

  /// Removes everything under the cache root. Safe to call on a fresh
  /// cache (no-ops on an empty/missing dir).
  Future<void> clear() async {
    await init();
    final root = _root!;
    if (await root.exists()) {
      // List + delete-each rather than recursive root delete: a recursive
      // delete on an unrelated cache root (e.g. a misconfigured
      // injectedRoot in a dev build) would be very bad. Keeping the
      // root directory itself preserves the init() contract.
      await for (final entity in root.list(followLinks: false)) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {
          // Best effort — a stuck file shouldn't prevent the rest.
        }
      }
    }
  }

  // ── internals ───────────────────────────────────────────────────────

  /// Object keys look like `attachments/<owner>/<dive>/<uuid>.<ext>` —
  /// flatten them to a single safe filename. Filesystems that allow
  /// `/` in names are rare but the simplest safe rule is "no separators".
  /// We don't need reversibility; the cache is content-addressed by key
  /// and the original key is what callers always pass.
  File _fileFor(String key) {
    final flat = key.replaceAll('/', '_').replaceAll('\\', '_');
    return File(p.join(_root!.path, flat));
  }

  Future<void> _evictIfOverCap() async {
    final root = _root!;
    final entries = <_Entry>[];
    var total = 0;
    await for (final ent in root.list(followLinks: false)) {
      if (ent is! File) continue;
      try {
        final stat = await ent.stat();
        entries.add(_Entry(ent, stat.size, stat.modified));
        total += stat.size;
      } catch (_) {
        // Stat failure means the file vanished mid-listing; skip.
      }
    }
    if (total <= _maxBytes) return;
    // Oldest first.
    entries.sort((a, b) => a.modified.compareTo(b.modified));
    for (final e in entries) {
      if (total <= _maxBytes) break;
      try {
        await e.file.delete();
        total -= e.size;
      } catch (_) {
        // If we can't delete one, skip and keep trying others.
      }
    }
  }
}

class _Entry {
  final File file;
  final int size;
  final DateTime modified;
  _Entry(this.file, this.size, this.modified);
}
