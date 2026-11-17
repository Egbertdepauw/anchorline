/// Picking FIT files and folders for the Garmin import.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;

import '../../devices/fit/fit_inputs.dart';

/// Whether the app runs on a desktop, where a whole folder can be picked.
bool get fitFolderPickIsOffered =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// Whether [e] says the disk is full. file_picker copies a picked file into
/// the cache on Android and iOS; when that fails for lack of space the
/// platform reports ENOSPC or "No space left".
bool isNoSpaceError(Object e) {
  if (e is FileSystemException) {
    final code = e.osError?.errorCode;
    // 28 is ENOSPC on Linux, macOS and Android; 112 and 39 are the Windows
    // disk-full codes.
    if (code == 28 || code == 112 || code == 39) return true;
  }
  final text = e is PlatformException
      ? '${e.code} ${e.message} ${e.details}'
      : e.toString();
  final lower = text.toLowerCase();
  return lower.contains('enospc') || lower.contains('no space');
}

/// "12 MB" style size for the free-space message.
String fitSizeLabel(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).round()} MB';
  }
  return '${(bytes / 1024).ceil()} KB';
}

/// The message for a file that could not be copied for lack of space. The
/// size is added when it is known.
String fitNoSpaceMessage([int? bytes]) =>
    'Not enough free space to read this file.'
    '${bytes == null ? '' : ' It needs about ${fitSizeLabel(bytes)}.'}';

/// Lets the user pick several `.fit` and `.zip` files. Null when cancelled.
/// Android's picker cannot filter an extension it does not know (`.fit`), so
/// there it offers every file and the import sorts them out.
Future<List<FitInput>?> pickFitFiles() async {
  final any = Platform.isAndroid;
  final result = await FilePicker.pickFiles(
    allowMultiple: true,
    type: any ? FileType.any : FileType.custom,
    allowedExtensions: any ? null : const ['fit', 'zip'],
  );
  if (result == null) return null;
  final inputs = [
    for (final f in result.files)
      if (f.path != null) FitFileInput(f.path!),
  ];
  return inputs.isEmpty ? null : inputs;
}

/// Lets the user pick a folder (desktop). Null when cancelled.
Future<List<FitInput>?> pickFitFolder() async {
  final path = await FilePicker.getDirectoryPath();
  if (path == null) return null;
  return [FitFolderInput(path)];
}
