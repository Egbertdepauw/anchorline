/// A small Bluetooth log for the desktop builds.
///
/// Release builds on Windows and Linux have no console, so `debugPrint`
/// output is lost. [bleLog] prints as before and, on those two platforms,
/// also appends the line to `ble.log` in the app's support folder, so a
/// failed connect can be read back. The file is cut to its last half when it
/// passes [kBleLogMaxBytes].
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// The log file keeps at most this many bytes.
const int kBleLogMaxBytes = 256 * 1024;

/// Where [bleLog] writes; null until known, or on platforms without a file.
/// Tests may set it.
@visibleForTesting
File? bleLogFile;

bool _resolving = false;
final List<String> _pending = [];

bool get _fileLogging =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Prints [message] and, on Windows and Linux, appends it with a timestamp
/// to the log file. Never throws.
void bleLog(String message) {
  debugPrint(message);
  if (bleLogFile == null && !_fileLogging) return;
  final line = '${DateTime.now().toIso8601String()} $message\n';
  final file = bleLogFile;
  if (file != null) {
    appendBleLogLine(file, line);
    return;
  }
  _pending.add(line);
  if (_resolving) return;
  _resolving = true;
  getApplicationSupportDirectory().then((dir) {
    final f = bleLogFile = File('${dir.path}${Platform.pathSeparator}ble.log');
    for (final l in _pending) {
      appendBleLogLine(f, l);
    }
    _pending.clear();
  }).catchError((Object _) {
    _pending.clear();
  });
}

/// Appends [line] to [file], first cutting the file to its last half when it
/// has grown past [maxBytes]. Never throws.
@visibleForTesting
void appendBleLogLine(File file, String line, {int maxBytes = kBleLogMaxBytes}) {
  try {
    if (file.existsSync() && file.lengthSync() > maxBytes) {
      final bytes = file.readAsBytesSync();
      file.writeAsBytesSync(bytes.sublist(bytes.length - maxBytes ~/ 2));
    }
    file.writeAsStringSync(line, mode: FileMode.append, flush: true);
  } catch (_) {
    // A log must never break Bluetooth.
  }
}
