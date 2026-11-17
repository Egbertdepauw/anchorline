/// Telling a full disk from other file errors.
library;

import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;

/// Whether [e] says the disk is full, with certainty. Error number 28 is
/// ENOSPC on Linux, macOS and Android; 39 and 112 are Windows disk-full codes
/// (on Linux 39 is ENOTEMPTY, which is no space problem). [windows] is a test
/// seam.
bool isNoSpaceError(Object e, {bool? windows}) {
  final win = windows ?? Platform.isWindows;
  if (e is FileSystemException) {
    final code = e.osError?.errorCode;
    if (win ? (code == 39 || code == 112) : code == 28) return true;
  }
  final text = e is PlatformException
      ? '${e.code} ${e.message} ${e.details}'
      : e.toString();
  final lower = text.toLowerCase();
  return lower.contains('enospc') || lower.contains('no space');
}
