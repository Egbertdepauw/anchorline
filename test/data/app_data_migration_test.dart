import 'dart:io';

import 'package:ccrlogger/data/app_data_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The OS error code for "can't rename across volumes" on the test host.
final int _crossDeviceCode = Platform.isWindows ? 17 : 18;

/// Windows ERROR_SHARING_VIOLATION: the file is open in another process.
/// Any code other than the cross-device one behaves the same.
const int _sharingViolationCode = 32;

/// Real file operations, except where a test makes one fail.
class _FaultyOps extends AppDataFileOps {
  _FaultyOps({this.failRename, this.failCopy, this.failDelete});

  /// Returns the error to throw for this rename, or null to let it run.
  final OSError? Function(String from, String to)? failRename;
  final OSError? Function(String from)? failCopy;
  final OSError? Function(String path)? failDelete;

  final renames = <String>[];

  @override
  Future<void> rename(String from, String to) {
    renames.add(p.basename(from));
    final error = failRename?.call(from, to);
    if (error != null) {
      throw FileSystemException('Cannot rename', from, error);
    }
    return super.rename(from, to);
  }

  @override
  Future<void> copy(String from, String to) {
    final error = failCopy?.call(from);
    if (error != null) throw FileSystemException('Cannot copy', from, error);
    return super.copy(from, to);
  }

  @override
  Future<void> delete(String path) {
    final error = failDelete?.call(path);
    if (error != null) throw FileSystemException('Cannot delete', path, error);
    return super.delete(path);
  }
}

void main() {
  late Directory tmp;
  late String documents;
  late String data;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ccrlog_migration_');
    documents = p.join(tmp.path, 'Documents');
    data = p.join(tmp.path, 'AppData', 'Anchorline');
    Directory(documents).createSync();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void write(String folder, String name, String content) {
    final file = File(p.join(folder, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  String? read(String folder, String name) {
    final file = File(p.join(folder, name));
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  bool exists(String folder, String name) =>
      FileSystemEntity.typeSync(p.join(folder, name)) !=
      FileSystemEntityType.notFound;

  /// Everything a long-time desktop user has in Documents today.
  void writeFullDocuments() {
    write(documents, 'ccrlogger.sqlite', 'drift');
    write(documents, 'ccrlogger.sqlite-journal', 'drift journal');
    write(documents, 'powersync.db', 'powersync');
    write(documents, 'powersync.db-wal', 'powersync wal');
    write(documents, 'powersync.db-shm', 'powersync shm');
    write(documents, p.join('subsurface_clone', '.git', 'HEAD'), 'ref');
    write(documents, p.join('subsurface_clone', 'dives', 'dive.xml'), 'xml');
    write(documents, 'ble-debug.log', 'log');
    write(documents, 'ble-debug.log.prev', 'old log');
  }

  AppDataMigration migration({AppDataFileOps? ops}) => AppDataMigration(
    documentsFolder: documents,
    dataFolder: data,
    fileOps: ops,
    retryDelays: const [Duration.zero, Duration.zero],
  );

  test('a fresh install has nothing to move and gets a data folder', () async {
    final report = await migration().run();

    expect(Directory(data).existsSync(), isTrue);
    for (final item in AppDataItem.values) {
      expect(report.outcomes[item]!.status, AppDataMoveStatus.notInDocuments);
      expect(report.folderFor(item), data);
    }
    expect(report.problems, isEmpty);
  });

  test('moves every item together with its companion files', () async {
    writeFullDocuments();

    final report = await migration().run();

    for (final item in AppDataItem.values) {
      expect(report.outcomes[item]!.status, AppDataMoveStatus.moved);
      expect(report.folderFor(item), data);
    }
    expect(read(data, 'ccrlogger.sqlite'), 'drift');
    expect(read(data, 'ccrlogger.sqlite-journal'), 'drift journal');
    expect(read(data, 'powersync.db'), 'powersync');
    expect(read(data, 'powersync.db-wal'), 'powersync wal');
    expect(read(data, 'powersync.db-shm'), 'powersync shm');
    expect(read(data, p.join('subsurface_clone', '.git', 'HEAD')), 'ref');
    expect(read(data, p.join('subsurface_clone', 'dives', 'dive.xml')), 'xml');
    expect(read(data, 'ble-debug.log'), 'log');
    expect(read(data, 'ble-debug.log.prev'), 'old log');
    expect(Directory(documents).listSync(), isEmpty);
    expect(report.problems, isEmpty);
  });

  test('moves companion files before the main file', () async {
    writeFullDocuments();
    final ops = _FaultyOps();

    await migration(ops: ops).run();

    expect(
      ops.renames.indexOf('powersync.db-wal'),
      lessThan(ops.renames.indexOf('powersync.db')),
    );
    expect(
      ops.renames.indexOf('powersync.db-shm'),
      lessThan(ops.renames.indexOf('powersync.db')),
    );
  });

  test('leaves unrelated files and stray companions in Documents', () async {
    write(documents, 'dive-notes.txt', 'mine');
    write(documents, 'powersync.db-wal', 'no database next to me');

    final report = await migration().run();

    expect(
      report.outcomes[AppDataItem.powerSyncDatabase]!.status,
      AppDataMoveStatus.notInDocuments,
    );
    expect(read(documents, 'dive-notes.txt'), 'mine');
    expect(read(documents, 'powersync.db-wal'), 'no database next to me');
    expect(exists(data, 'powersync.db-wal'), isFalse);
  });

  test('a second run finds nothing left to move', () async {
    writeFullDocuments();
    await migration().run();

    final report = await migration().run();

    for (final item in AppDataItem.values) {
      expect(report.outcomes[item]!.status, AppDataMoveStatus.notInDocuments);
    }
    expect(read(data, 'powersync.db'), 'powersync');
  });

  test('when both folders hold a database, uses the data folder and leaves '
      'Documents untouched', () async {
    write(documents, 'powersync.db', 'documents copy');
    write(documents, 'powersync.db-wal', 'documents wal');
    write(data, 'powersync.db', 'data folder copy');

    final report = await migration().run();

    final outcome = report.outcomes[AppDataItem.powerSyncDatabase]!;
    expect(outcome.status, AppDataMoveStatus.inBothFolders);
    expect(report.folderFor(AppDataItem.powerSyncDatabase), data);
    expect(read(documents, 'powersync.db'), 'documents copy');
    expect(read(documents, 'powersync.db-wal'), 'documents wal');
    expect(read(data, 'powersync.db'), 'data folder copy');
    expect(exists(data, 'powersync.db-wal'), isFalse);
    expect(report.problems, hasLength(1));
  });

  test(
    'a locked database stays in Documents with all its companions',
    () async {
      writeFullDocuments();
      final ops = _FaultyOps(
        failRename: (from, to) => p.basename(from) == 'powersync.db'
            ? const OSError('sharing violation', _sharingViolationCode)
            : null,
      );

      final report = await migration(ops: ops).run();

      final outcome = report.outcomes[AppDataItem.powerSyncDatabase]!;
      expect(outcome.status, AppDataMoveStatus.keptInDocuments);
      expect(outcome.error, isA<FileSystemException>());
      expect(report.folderFor(AppDataItem.powerSyncDatabase), documents);
      expect(read(documents, 'powersync.db'), 'powersync');
      expect(read(documents, 'powersync.db-wal'), 'powersync wal');
      expect(read(documents, 'powersync.db-shm'), 'powersync shm');
      expect(exists(data, 'powersync.db'), isFalse);
      expect(exists(data, 'powersync.db-wal'), isFalse);
      expect(exists(data, 'powersync.db-shm'), isFalse);
      // Retried before giving up: one attempt plus one per retry delay.
      expect(ops.renames.where((n) => n == 'powersync.db'), hasLength(3));
      // The other items don't depend on it and still move.
      expect(report.folderFor(AppDataItem.driftDatabase), data);
      expect(read(data, 'ccrlogger.sqlite'), 'drift');
      expect(report.problems, hasLength(1));
    },
  );

  test('a briefly locked file moves on a retry', () async {
    write(documents, 'ccrlogger.sqlite', 'drift');
    var failuresLeft = 2;
    final ops = _FaultyOps(
      failRename: (from, to) =>
          p.basename(from) == 'ccrlogger.sqlite' && failuresLeft-- > 0
          ? const OSError('sharing violation', _sharingViolationCode)
          : null,
    );

    final report = await migration(ops: ops).run();

    expect(
      report.outcomes[AppDataItem.driftDatabase]!.status,
      AppDataMoveStatus.moved,
    );
    expect(read(data, 'ccrlogger.sqlite'), 'drift');
  });

  test('resumes a database that was interrupted part-way', () async {
    // An earlier run moved the WAL file, then the process died.
    write(data, 'powersync.db-wal', 'powersync wal');
    write(documents, 'powersync.db', 'powersync');
    write(documents, 'powersync.db-shm', 'powersync shm');

    final report = await migration().run();

    expect(
      report.outcomes[AppDataItem.powerSyncDatabase]!.status,
      AppDataMoveStatus.moved,
    );
    expect(read(data, 'powersync.db'), 'powersync');
    expect(read(data, 'powersync.db-wal'), 'powersync wal');
    expect(read(data, 'powersync.db-shm'), 'powersync shm');
    expect(exists(documents, 'powersync.db'), isFalse);
  });

  test('a failed resume puts companions from the earlier run back', () async {
    write(data, 'powersync.db-wal', 'powersync wal');
    write(documents, 'powersync.db', 'powersync');
    write(documents, 'powersync.db-shm', 'powersync shm');
    final ops = _FaultyOps(
      failRename: (from, to) => from == p.join(documents, 'powersync.db')
          ? const OSError('sharing violation', _sharingViolationCode)
          : null,
    );

    final report = await migration(ops: ops).run();

    expect(report.folderFor(AppDataItem.powerSyncDatabase), documents);
    expect(read(documents, 'powersync.db'), 'powersync');
    expect(read(documents, 'powersync.db-wal'), 'powersync wal');
    expect(read(documents, 'powersync.db-shm'), 'powersync shm');
    expect(exists(data, 'powersync.db-wal'), isFalse);
    expect(exists(data, 'powersync.db-shm'), isFalse);
  });

  test(
    'a companion in both folders is replaced by the one in Documents',
    () async {
      write(data, 'powersync.db-wal', 'stale');
      write(documents, 'powersync.db', 'powersync');
      write(documents, 'powersync.db-wal', 'current');

      await migration().run();

      expect(read(data, 'powersync.db'), 'powersync');
      expect(read(data, 'powersync.db-wal'), 'current');
    },
  );

  test('a failed move removes stale companions from the data folder', () async {
    // If the stale WAL stayed behind, a later run would pair it with the
    // database in Documents after SQLite has checkpointed its own WAL.
    write(data, 'powersync.db-wal', 'stale');
    write(documents, 'powersync.db', 'powersync');
    write(documents, 'powersync.db-wal', 'current');
    final ops = _FaultyOps(
      failRename: (from, to) => p.basename(from) == 'powersync.db'
          ? const OSError('sharing violation', _sharingViolationCode)
          : null,
    );

    await migration(ops: ops).run();

    expect(read(documents, 'powersync.db'), 'powersync');
    expect(read(documents, 'powersync.db-wal'), 'current');
    expect(exists(data, 'powersync.db-wal'), isFalse);
  });

  test('refuses to continue when companions cannot be put back', () async {
    write(documents, 'powersync.db', 'powersync');
    write(documents, 'powersync.db-wal', 'powersync wal');
    final ops = _FaultyOps(
      failRename: (from, to) {
        final name = p.basename(from);
        final movingBack = p.isWithin(data, from);
        if (name == 'powersync.db' || movingBack) {
          return const OSError('access denied', 5);
        }
        return null;
      },
    );

    await expectLater(
      migration(ops: ops).run(),
      throwsA(isA<AppDataMigrationException>()),
    );
  });

  group('across volumes', () {
    _FaultyOps crossDevice({
      OSError? Function(String from)? failCopy,
      OSError? Function(String path)? failDelete,
    }) => _FaultyOps(
      failRename: (from, to) => p.isWithin(documents, from)
          ? OSError('cross-device link', _crossDeviceCode)
          : null,
      failCopy: failCopy,
      failDelete: failDelete,
    );

    test('puts the copied main file in place after its companions', () async {
      writeFullDocuments();
      final ops = crossDevice();

      await migration(ops: ops).run();

      final placed = ops.renames.where((n) => n.endsWith('.migrating'));
      expect(
        placed.toList().indexOf('powersync.db-wal.migrating'),
        lessThan(placed.toList().indexOf('powersync.db.migrating')),
      );
      expect(
        placed.toList().indexOf('ccrlogger.sqlite-journal.migrating'),
        lessThan(placed.toList().indexOf('ccrlogger.sqlite.migrating')),
      );
    });

    test(
      'copies everything, then removes the originals from Documents',
      () async {
        writeFullDocuments();

        final report = await migration(ops: crossDevice()).run();

        for (final item in AppDataItem.values) {
          expect(report.outcomes[item]!.status, AppDataMoveStatus.moved);
          expect(report.folderFor(item), data);
        }
        expect(read(data, 'powersync.db'), 'powersync');
        expect(read(data, 'powersync.db-wal'), 'powersync wal');
        expect(read(data, 'ccrlogger.sqlite-journal'), 'drift journal');
        expect(
          read(data, p.join('subsurface_clone', 'dives', 'dive.xml')),
          'xml',
        );
        expect(Directory(documents).listSync(), isEmpty);
        expect(
          Directory(data).listSync().map((e) => p.basename(e.path)),
          isNot(contains(endsWith('.migrating'))),
        );
        expect(report.problems, isEmpty);
      },
    );

    test(
      'a failed copy leaves Documents as it was and the data folder clean',
      () async {
        writeFullDocuments();
        final ops = crossDevice(
          failCopy: (from) => p.basename(from) == 'powersync.db'
              ? const OSError('disk full', 112)
              : null,
        );

        final report = await migration(ops: ops).run();

        expect(
          report.outcomes[AppDataItem.powerSyncDatabase]!.status,
          AppDataMoveStatus.keptInDocuments,
        );
        expect(report.folderFor(AppDataItem.powerSyncDatabase), documents);
        expect(read(documents, 'powersync.db'), 'powersync');
        expect(read(documents, 'powersync.db-wal'), 'powersync wal');
        expect(read(documents, 'powersync.db-shm'), 'powersync shm');
        final leftInData = Directory(data)
            .listSync()
            .map((e) => p.basename(e.path))
            .where((name) => name.startsWith('powersync.db'));
        expect(leftInData, isEmpty);
      },
    );

    test('an original that cannot be removed is reported, but the move '
        'stands', () async {
      write(documents, 'ccrlogger.sqlite', 'drift');
      final ops = crossDevice(
        failDelete: (path) => p.isWithin(documents, path)
            ? const OSError('access denied', 5)
            : null,
      );

      final report = await migration(ops: ops).run();

      final outcome = report.outcomes[AppDataItem.driftDatabase]!;
      expect(outcome.status, AppDataMoveStatus.moved);
      expect(outcome.error, isNotNull);
      expect(report.folderFor(AppDataItem.driftDatabase), data);
      expect(read(data, 'ccrlogger.sqlite'), 'drift');
      expect(report.problems, hasLength(1));
    });
  });

  test('problems name items and error codes but never paths', () async {
    write(documents, 'powersync.db', 'powersync');
    final ops = _FaultyOps(
      failRename: (from, to) =>
          const OSError('sharing violation', _sharingViolationCode),
    );

    final report = await migration(ops: ops).run();

    expect(report.problems, hasLength(1));
    expect(report.problems.single, contains('powerSyncDatabase'));
    expect(report.problems.single, contains('$_sharingViolationCode'));
    expect(report.problems.single, isNot(contains(tmp.path)));
  });

  test('does nothing when Documents is the data folder', () async {
    write(documents, 'ccrlogger.sqlite', 'drift');

    final report = await AppDataMigration(
      documentsFolder: documents,
      dataFolder: documents,
    ).run();

    expect(report.folderFor(AppDataItem.driftDatabase), documents);
    expect(read(documents, 'ccrlogger.sqlite'), 'drift');
  });
}
