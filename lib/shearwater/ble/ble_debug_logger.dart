/// Append-only file logger for BLE diagnostics.
///
/// `debugPrint` is unreliable in release / profile builds (Flutter
/// closes the stdout pipe in some configurations), and `developer.log`
/// is suppressed in AOT builds. To capture BLE traffic from a build
/// the user is actually testing (Play Internal, sideloaded APK, Mac
/// App Store TestFlight, etc.), we mirror every BLE event into a
/// rotating log file the user can export via the Settings screen.
///
/// Format: `<ISO8601 timestamp> <message>\n`.
/// Path: `<app docs>/ble-debug.log`.
/// Size cap: 2 MB. When exceeded, the file is rotated to
/// `ble-debug.log.prev` (single generation kept).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class BleDebugLogger {
  BleDebugLogger._();
  static final BleDebugLogger instance = BleDebugLogger._();

  static const _kMaxBytes = 2 * 1024 * 1024;
  static const _fileName = 'ble-debug.log';
  static const _prevFileName = 'ble-debug.log.prev';

  File? _file;
  IOSink? _sink;
  bool _opening = false;
  final _pending = <String>[];

  /// Resolve the log file path on demand. The first write blocks
  /// briefly while path_provider returns; subsequent writes are
  /// effectively non-blocking via the queued sink.
  Future<File> _resolveFile() async {
    if (_file != null) return _file!;
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, _fileName);
    _file = File(path);
    return _file!;
  }

  /// Set to true when we discover path_provider isn't available
  /// (e.g. unit tests with no platform binding). In that mode the
  /// logger silently degrades to debugPrint-only and stops trying
  /// to touch the filesystem.
  bool _fileBackingDisabled = false;

  Future<void> _openSink() async {
    if (_sink != null || _opening || _fileBackingDisabled) return;
    _opening = true;
    try {
      final file = await _resolveFile();
      // Rotate if oversize before opening.
      if (await file.exists()) {
        final size = await file.length();
        if (size > _kMaxBytes) {
          final prev = File(p.join(file.parent.path, _prevFileName));
          if (await prev.exists()) await prev.delete();
          await file.rename(prev.path);
          _file = File(p.join(file.parent.path, _fileName));
        }
      }
      _sink = _file!.openWrite(mode: FileMode.writeOnlyAppend);
      // Drain anything that came in while we were opening.
      for (final line in _pending) {
        _sink!.writeln(line);
      }
      _pending.clear();
    } catch (_) {
      // path_provider unavailable (unit tests) or filesystem unwritable.
      // Stop pestering; debugPrint side of `log()` still functions.
      _fileBackingDisabled = true;
      _pending.clear();
    } finally {
      _opening = false;
    }
  }

  /// Write [message] to the log file with a timestamp. Returns
  /// immediately — the underlying file IO is fire-and-forget. Also
  /// mirrors to `debugPrint` so it shows up in `flutter run` output
  /// when that pipe IS available.
  void log(String message) {
    final ts = DateTime.now().toIso8601String();
    final line = '$ts $message';
    debugPrint('[BLE] $message');
    if (_sink != null) {
      _sink!.writeln(line);
    } else {
      _pending.add(line);
      unawaited(_openSink());
    }
  }

  /// Force-flush the underlying sink. Call before reading or sharing
  /// the file from another path to make sure recent writes are durable.
  Future<void> flush() async {
    if (_sink == null) await _openSink();
    await _sink?.flush();
  }

  /// Absolute path of the current log file, for share/export UI.
  /// Resolves the documents directory if it hasn't been touched yet.
  Future<String> filePath() async {
    final file = await _resolveFile();
    return file.path;
  }
}
