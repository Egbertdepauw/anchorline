/// One-time move of the app's local files out of the user's Documents
/// folder into the per-app data folder (Windows and Linux, issue #135).
///
/// Early desktop builds kept their databases, the Subsurface clone and the
/// BLE debug log loose in Documents. [AppDataMigration] moves each of them
/// into the data folder chosen by `app_data_folder.dart`, on every start
/// until nothing is left to move.
///
/// The rule that keeps a database safe: **until an item's main file exists
/// in the data folder, the copy in Documents is the real one.** Its
/// companion files (`-wal`, `-shm`, `-journal`) hold committed data and
/// always travel with it. They move first and the main file moves last, so
/// a crash part-way leaves the main file in Documents and the next start
/// finishes the job. When the main file can't follow (locked, no access),
/// its companions go back to Documents and the app keeps using the item
/// there for this launch. Nothing is ever copied while an original stays in
/// use, and nothing is deleted from Documents until its copy is complete.
///
/// Pure `dart:io`: no Flutter, no path_provider. Tests drive it with
/// temporary folders and a fault-injecting [AppDataFileOps].
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// A file or folder the app keeps in its data folder.
///
/// [fileName] is the single source of these names: the code that opens
/// them gets its paths from `AppDataPaths`.
enum AppDataItem {
  driftDatabase('ccrlogger.sqlite', _sqliteCompanions),
  powerSyncDatabase('powersync.db', _sqliteCompanions),
  subsurfaceClone('subsurface_clone', []),
  bleDebugLog('ble-debug.log', ['.prev']);

  const AppDataItem(this.fileName, this._companionSuffixes);

  /// Name of the item's main file (or folder, for the Subsurface clone).
  final String fileName;
  final List<String> _companionSuffixes;

  /// Files that belong to the main file and must stay next to it.
  List<String> get companionNames => [
    for (final suffix in _companionSuffixes) '$fileName$suffix',
  ];
}

/// SQLite keeps committed transactions in these until it checkpoints them
/// into the main file. Moving a database without them loses data.
const _sqliteCompanions = ['-wal', '-shm', '-journal'];

/// Suffix for copies still in progress when moving across volumes.
const _stagingSuffix = '.migrating';

/// The file operations the migration uses. Tests override them to inject
/// failures; the defaults are plain `dart:io`.
class AppDataFileOps {
  const AppDataFileOps();

  /// Renames a file or folder. [to] must not be a folder that exists; an
  /// existing file at [to] is replaced.
  Future<void> rename(String from, String to) async {
    final type = await FileSystemEntity.type(from, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }
  }

  /// Copies a file, or a folder with everything in it.
  Future<void> copy(String from, String to) async {
    switch (await FileSystemEntity.type(from, followLinks: false)) {
      case FileSystemEntityType.directory:
        await Directory(to).create(recursive: true);
        await for (final entity in Directory(from).list(followLinks: false)) {
          await copy(entity.path, p.join(to, p.basename(entity.path)));
        }
      case FileSystemEntityType.link:
        await Link(to).create(await Link(from).target());
      default:
        await File(from).copy(to);
    }
  }

  /// Deletes a file, or a folder with everything in it.
  Future<void> delete(String path) async {
    switch (await FileSystemEntity.type(path, followLinks: false)) {
      case FileSystemEntityType.notFound:
        return;
      case FileSystemEntityType.directory:
        await Directory(path).delete(recursive: true);
      case FileSystemEntityType.link:
        await Link(path).delete();
      default:
        await File(path).delete();
    }
  }

  /// Whether [e] means "a rename can't cross volumes": Documents redirected
  /// to another drive or a network share. Windows ERROR_NOT_SAME_DEVICE
  /// (17), POSIX EXDEV (18).
  bool isCrossDevice(FileSystemException e) =>
      e.osError?.errorCode == (Platform.isWindows ? 17 : 18);
}

enum AppDataMoveStatus {
  /// Nothing in Documents: a fresh install, or moved on an earlier start.
  notInDocuments,

  /// Moved from Documents on this start.
  moved,

  /// Both folders hold the item. The data folder's is used; the one in
  /// Documents is left untouched for the user to sort out. Happens after
  /// running an older build again once the data had moved.
  inBothFolders,

  /// Could not be moved this time (see [AppDataItemOutcome.error]); the
  /// app uses it in Documents for this launch and tries again next start.
  keptInDocuments,
}

class AppDataItemOutcome {
  const AppDataItemOutcome(this.status, this.folder, {this.error});

  final AppDataMoveStatus status;

  /// The folder the app should open the item in for this launch.
  final String folder;

  /// Why the item stayed in Documents, or, for a moved item, why its
  /// original could not be removed from Documents afterwards.
  final Object? error;
}

class AppDataMigrationReport {
  const AppDataMigrationReport(this.outcomes);

  final Map<AppDataItem, AppDataItemOutcome> outcomes;

  String folderFor(AppDataItem item) => outcomes[item]!.folder;

  /// One line per item that needs attention, safe to send to Sentry: item
  /// names and OS error codes only, never paths (they hold the user name).
  List<String> get problems => [
    for (final MapEntry(key: item, value: outcome) in outcomes.entries)
      if (_describeProblem(outcome) case final problem?)
        '${item.name}: $problem',
  ];

  static String? _describeProblem(AppDataItemOutcome outcome) {
    final code = switch (outcome.error) {
      FileSystemException(:final osError?) =>
        ' (OS error ${osError.errorCode})',
      null => '',
      final other => ' (${other.runtimeType})',
    };
    return switch (outcome.status) {
      AppDataMoveStatus.notInDocuments => null,
      AppDataMoveStatus.moved when outcome.error == null => null,
      AppDataMoveStatus.moved =>
        'moved, but the original in Documents '
            'could not be removed$code',
      AppDataMoveStatus.inBothFolders =>
        'also in Documents; using the data folder and leaving Documents alone',
      AppDataMoveStatus.keptInDocuments => 'still in Documents$code',
    };
  }
}

/// Thrown when a failed move can't be undone, so neither folder holds a
/// complete database. Opening either one could lose data, so the app must
/// not start until someone has looked at the files.
class AppDataMigrationException implements Exception {
  AppDataMigrationException(this.message, this.cause);

  final String message;
  final Object cause;

  @override
  String toString() => 'AppDataMigrationException: $message ($cause)';
}

class AppDataMigration {
  AppDataMigration({
    required this.documentsFolder,
    required this.dataFolder,
    AppDataFileOps? fileOps,
    this.retryDelays = const [
      Duration(milliseconds: 100),
      Duration(milliseconds: 400),
    ],
  }) : _ops = fileOps ?? const AppDataFileOps();

  final String documentsFolder;
  final String dataFolder;

  /// Waits between rename attempts. Antivirus scanners and OneDrive hold
  /// files open for a moment after the app last closed them.
  final List<Duration> retryDelays;

  final AppDataFileOps _ops;

  Future<AppDataMigrationReport> run() async {
    if (p.equals(documentsFolder, dataFolder)) {
      return AppDataMigrationReport({
        for (final item in AppDataItem.values)
          item: AppDataItemOutcome(
            AppDataMoveStatus.notInDocuments,
            dataFolder,
          ),
      });
    }
    await Directory(dataFolder).create(recursive: true);
    return AppDataMigrationReport({
      // One at a time: each item stands alone, so a locked database
      // doesn't hold back the others.
      for (final item in AppDataItem.values) item: await _migrate(item),
    });
  }

  String _inDocuments(String name) => p.join(documentsFolder, name);
  String _inData(String name) => p.join(dataFolder, name);

  Future<AppDataItemOutcome> _migrate(AppDataItem item) async {
    if (!await _exists(_inDocuments(item.fileName))) {
      return AppDataItemOutcome(AppDataMoveStatus.notInDocuments, dataFolder);
    }
    if (await _exists(_inData(item.fileName))) {
      return AppDataItemOutcome(AppDataMoveStatus.inBothFolders, dataFolder);
    }

    try {
      await _moveByRenaming(item);
      return AppDataItemOutcome(AppDataMoveStatus.moved, dataFolder);
    } on FileSystemException catch (e) {
      if (!_ops.isCrossDevice(e)) {
        return AppDataItemOutcome(
          AppDataMoveStatus.keptInDocuments,
          documentsFolder,
          error: e,
        );
      }
    }

    try {
      final leftover = await _moveByCopying(item);
      return AppDataItemOutcome(
        AppDataMoveStatus.moved,
        dataFolder,
        error: leftover,
      );
    } on FileSystemException catch (e) {
      return AppDataItemOutcome(
        AppDataMoveStatus.keptInDocuments,
        documentsFolder,
        error: e,
      );
    }
  }

  /// The normal case: Documents and the data folder share a volume, and
  /// each rename is atomic.
  Future<void> _moveByRenaming(AppDataItem item) async {
    try {
      for (final name in item.companionNames) {
        // Absent when the database never had one, or when an interrupted
        // earlier run already moved it.
        if (!await _exists(_inDocuments(name))) continue;
        // Replaces any companion already in the data folder: while the
        // main file is still in Documents, the one in Documents is current.
        await _renameWithRetry(_inDocuments(name), _inData(name));
      }
      await _renameWithRetry(
        _inDocuments(item.fileName),
        _inData(item.fileName),
      );
    } on FileSystemException {
      await _undo(item);
      rethrow;
    }
  }

  /// Documents is on another volume (a second drive, a network share):
  /// copy into the data folder, then remove the originals. Returns the
  /// error if an original could not be removed; the move still stands.
  Future<Object?> _moveByCopying(AppDataItem item) async {
    final names = [
      for (final name in [...item.companionNames, item.fileName])
        if (await _exists(_inDocuments(name))) name,
    ];

    try {
      for (final name in names) {
        final staged = _inData('$name$_stagingSuffix');
        await _ops.delete(staged); // left by an interrupted earlier run
        await _ops.copy(_inDocuments(name), staged);
      }
      // Companions first, main file last (it is last in [names]).
      for (final name in names) {
        await _ops.rename(_inData('$name$_stagingSuffix'), _inData(name));
      }
    } on FileSystemException {
      await _undo(item);
      rethrow;
    }

    // The data folder now holds the complete item. Remove the originals,
    // main file first: if that fails, both folders hold a complete copy
    // and the next start uses the data folder's.
    try {
      for (final name in names.reversed) {
        await _ops.delete(_inDocuments(name));
      }
      return null;
    } on FileSystemException catch (e) {
      return e;
    }
  }

  /// Rolls back a failed move so that the item in Documents is complete
  /// and the data folder holds none of its companions. A companion left in
  /// the data folder would otherwise be paired with the main file in some
  /// later run, after SQLite has moved on without it.
  Future<void> _undo(AppDataItem item) async {
    for (final name in [...item.companionNames, item.fileName]) {
      try {
        await _ops.delete(_inData('$name$_stagingSuffix'));
      } on FileSystemException {
        // A half-made copy under a name nothing opens. Harmless.
      }
    }
    for (final name in item.companionNames) {
      if (!await _exists(_inData(name))) continue;
      try {
        if (await _exists(_inDocuments(name))) {
          // A copy, or stale: the one in Documents is current.
          await _ops.delete(_inData(name));
        } else {
          // Moved there by this or an interrupted earlier run.
          await _renameWithRetry(_inData(name), _inDocuments(name));
        }
      } on FileSystemException catch (e) {
        throw AppDataMigrationException(
          'Could not undo a partial move of ${item.name}: $name is in '
          '$dataFolder while ${item.fileName} is in $documentsFolder. '
          'Move it back by hand before starting the app again.',
          e,
        );
      }
    }
  }

  Future<void> _renameWithRetry(String from, String to) async {
    for (var attempt = 0; ; attempt++) {
      try {
        await _ops.rename(from, to);
        return;
      } on FileSystemException catch (e) {
        if (_ops.isCrossDevice(e) || attempt >= retryDelays.length) rethrow;
        await Future<void>.delayed(retryDelays[attempt]);
      }
    }
  }

  Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;
}
