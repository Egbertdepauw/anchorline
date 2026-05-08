/// Tiny key-value mapping `attachmentId → local file path` for
/// resumable uploads.
///
/// When the notifier hands the uploader a freshly-picked file, the
/// uploader stashes the file's local path here keyed by attachment id
/// so a later `retry(row)` (network back, app restarted, etc.) can
/// rediscover the bytes without help from the notifier — which only
/// has the DAO row, never the [File].
///
/// Backed by SharedPreferences for v1: a single JSON blob under one
/// preference key. The expected cardinality is "small handful at any
/// given time", so we don't need a Drift table. If this grows beyond
/// dozens of entries we can graduate it then; pulling in Drift now
/// would be premature.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Abstract seam — the uploader takes one of these so tests can use
/// the [InMemoryPendingUploadStore] without booting SharedPreferences.
abstract class PendingUploadStore {
  Future<void> set(String attachmentId, String localPath);
  Future<String?> pathFor(String attachmentId);
  Future<void> clear(String attachmentId);
  Future<void> clearAll();
}

/// SharedPreferences-backed implementation. The whole map lives under
/// one key so reads and writes are atomic with respect to the
/// preferences API; we never have to reason about partial-write states.
class SharedPrefsPendingUploadStore implements PendingUploadStore {
  static const _kPrefsKey = 'pending_attachment_uploads';

  final Future<SharedPreferences> Function() _prefs;

  /// Production callers omit [prefsLoader] and get the singleton
  /// SharedPreferences. Tests inject `() async => fakePrefs`.
  SharedPrefsPendingUploadStore({
    Future<SharedPreferences> Function()? prefsLoader,
  }) : _prefs = prefsLoader ?? SharedPreferences.getInstance;

  @override
  Future<void> set(String attachmentId, String localPath) async {
    final map = await _read();
    map[attachmentId] = localPath;
    await _write(map);
  }

  @override
  Future<String?> pathFor(String attachmentId) async {
    final map = await _read();
    return map[attachmentId];
  }

  @override
  Future<void> clear(String attachmentId) async {
    final map = await _read();
    if (map.remove(attachmentId) == null) return;
    await _write(map);
  }

  @override
  Future<void> clearAll() async {
    final prefs = await _prefs();
    await prefs.remove(_kPrefsKey);
  }

  Future<Map<String, String>> _read() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_kPrefsKey);
    if (raw == null || raw.isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      return decoded.map<String, String>(
          (k, v) => MapEntry(k.toString(), v?.toString() ?? ''));
    } catch (_) {
      // Corrupt / partially-written entry — start fresh rather than
      // wedge the upload pipeline on a parse failure forever.
      return <String, String>{};
    }
  }

  Future<void> _write(Map<String, String> map) async {
    final prefs = await _prefs();
    await prefs.setString(_kPrefsKey, jsonEncode(map));
  }
}

/// Map-backed store for tests. No persistence, no async I/O of note.
class InMemoryPendingUploadStore implements PendingUploadStore {
  final Map<String, String> _entries = {};

  @override
  Future<void> set(String attachmentId, String localPath) async {
    _entries[attachmentId] = localPath;
  }

  @override
  Future<String?> pathFor(String attachmentId) async => _entries[attachmentId];

  @override
  Future<void> clear(String attachmentId) async {
    _entries.remove(attachmentId);
  }

  @override
  Future<void> clearAll() async {
    _entries.clear();
  }
}
