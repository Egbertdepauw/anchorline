/// Picking FIT files and folders for the Garmin import.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:path/path.dart' as p;

import '../../devices/fit/fit_disk_errors.dart';
import '../../devices/fit/fit_inputs.dart';

export '../../devices/fit/fit_disk_errors.dart' show isNoSpaceError;

/// What a pick returned. [partial] is true when the picker dropped some of
/// the files (Android could not copy them into the cache).
class FitPick {
  const FitPick(this.inputs, {this.partial = false});

  final List<FitInput> inputs;
  final bool partial;
}

/// Whether the app runs on a desktop, where a whole folder can be picked.
bool get fitFolderPickIsOffered =>
    Platform.isMacOS || Platform.isWindows || Platform.isLinux;

/// The text for files the phone could not copy for reading. file_picker on
/// Android swallows the copy's IOException, so the cause is only guessed.
const String kFitCopyFailedMessage =
    "Some files couldn't be copied for reading. This usually means the phone "
    'is short of free space.';

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

/// The message for a file that could not be copied for lack of space,
/// confirmed. The size is added when it is known.
String fitNoSpaceMessage([int? bytes]) =>
    'Not enough free space to read this file.'
    '${bytes == null ? '' : ' It needs about ${fitSizeLabel(bytes)}.'}';

/// The text for a pick that threw [e]. Only fixed texts: a message could name
/// a file. [android] is a test seam.
String fitPickFailureMessage(Object e, {bool? android, bool? windows}) {
  if (isNoSpaceError(e, windows: windows)) return fitNoSpaceMessage();
  // file_picker on Android reports 'unknown_path' when every file failed to
  // copy into the cache.
  if ((android ?? Platform.isAndroid) &&
      e is PlatformException &&
      e.code == 'unknown_path') {
    return kFitCopyFailedMessage;
  }
  return "Couldn't open the files you picked.";
}

/// The inputs of [result]. A file with no path is one the picker dropped.
FitPick? fitPickFromResult(FilePickerResult? result) {
  if (result == null) return null;
  final inputs = [
    for (final f in result.files)
      if (f.path != null) FitFileInput(f.path!),
  ];
  // Nothing picked at all is a cancel; files that all lost their path are
  // not: the screen says the copy failed.
  if (result.files.isEmpty) return null;
  return FitPick(inputs, partial: inputs.length < result.files.length);
}

/// Lets the user pick several `.fit` and `.zip` files. Null when cancelled.
/// Android's picker cannot filter an extension it does not know (`.fit`), so
/// there it offers every file and the import sorts them out. [pick] is a test
/// seam.
Future<FitPick?> pickFitFiles({
  Future<FilePickerResult?> Function(bool any)? pick,
}) async {
  final any = Platform.isAndroid;
  final result = await (pick ??
      (bool any) => FilePicker.pickFiles(
            allowMultiple: true,
            type: any ? FileType.any : FileType.custom,
            allowedExtensions: any ? null : const ['fit', 'zip'],
          ))(any);
  return fitPickFromResult(result);
}

/// Lets the user pick a folder (desktop). Null when cancelled.
Future<FitPick?> pickFitFolder() async {
  final path = await FilePicker.getDirectoryPath();
  if (path == null) return null;
  return FitPick([FitFolderInput(path)]);
}

/// Deletes the picker's cache copies in [inputs]: exactly the picked files,
/// and only those inside one of [roots] (the app's cache and temp folders).
/// A picked folder and any file elsewhere stay. Never throws.
Future<void> deletePickedCopies(
  List<FitInput> inputs,
  List<Directory> roots, {
  Future<void> Function(String path)? delete,
}) async {
  for (final input in inputs) {
    if (input is! FitFileInput) continue;
    final path = p.normalize(p.absolute(input.path));
    final inside = roots.any((r) => p.isWithin(p.normalize(p.absolute(r.path)), path));
    if (!inside) continue;
    try {
      if (delete != null) {
        await delete(path);
      } else {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (_) {}
  }
}
