import 'dart:io';

import 'package:ccrlogger/devices/fit/fit_inputs.dart';
import 'package:ccrlogger/ui/util/fit_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The shape file_picker 11 throws on Android when every cache copy failed.
  final unknownPath =
      PlatformException(code: 'unknown_path', message: 'Failed to retrieve path.');

  test('on Android unknown_path says the phone is short of space', () {
    expect(fitPickFailureMessage(unknownPath, android: true),
        "Some files couldn't be copied for reading. This usually means the "
        'phone is short of free space.');
    // Elsewhere it is not a guess about space.
    expect(fitPickFailureMessage(unknownPath, android: false),
        "Couldn't open the files you picked.");
  });

  test('a result with a dropped file is partial; its other files are kept',
      () {
    final pick = fitPickFromResult(FilePickerResult([
      PlatformFile(name: 'a.fit', size: 1, path: '/c/a.fit'),
      PlatformFile(name: 'b.fit', size: 1),
    ]));
    expect(pick!.partial, isTrue);
    expect(pick.inputs.map((i) => i.path), ['/c/a.fit']);

    final whole = fitPickFromResult(FilePickerResult([
      PlatformFile(name: 'a.fit', size: 1, path: '/c/a.fit'),
    ]));
    expect(whole!.partial, isFalse);
    expect(fitPickFromResult(FilePickerResult([PlatformFile(name: 'x', size: 1)])),
        isNull);
  });

  test('a confirmed ENOSPC keeps the exact free-space message', () {
    expect(
        fitPickFailureMessage(
            FileSystemException('write failed', '/c/a', const OSError('No space left on device', 28)),
            android: true,
            windows: false),
        'Not enough free space to read this file.');
    expect(
        fitPickFailureMessage(PlatformException(code: 'x', message: 'ENOSPC'),
            android: true),
        'Not enough free space to read this file.');
    expect(fitNoSpaceMessage(5 * 1024 * 1024),
        'Not enough free space to read this file. It needs about 5 MB.');
  });

  test('errno 39 is no-space only on Windows (ENOTEMPTY on Linux)', () {
    final e = FileSystemException('x', '/c', const OSError('', 39));
    expect(isNoSpaceError(e, windows: false), isFalse);
    expect(isNoSpaceError(e, windows: true), isTrue);
    expect(isNoSpaceError(FileSystemException('x', '/c', const OSError('', 28)),
            windows: false),
        isTrue);
  });

  test('only the picked files inside the cache are deleted', () async {
    final deleted = <String>[];
    await deletePickedCopies(
      const [
        FitFileInput('/cache/file_picker/a.fit'),
        FitFileInput('/cache/file_picker/b.zip'),
        FitFileInput('/home/me/Downloads/c.fit'),
        FitFileInput('/cache/../home/d.fit'),
        FitFolderInput('/cache/file_picker'),
      ],
      [Directory('/cache')],
      delete: (path) async => deleted.add(path),
    );
    expect(deleted, ['/cache/file_picker/a.fit', '/cache/file_picker/b.zip']);
  });
}
