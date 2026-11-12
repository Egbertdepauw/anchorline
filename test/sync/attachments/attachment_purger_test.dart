import 'dart:async';

import 'package:ccrlogger/data/db/dive_attachments_dao.dart';
import 'package:ccrlogger/data/models/dive_attachment.dart';
import 'package:ccrlogger/sync/attachments/attachment_purger.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../_helpers/powersync_test_helper.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime.utc(2026, 11, 10, 12);
  late PowerSyncDatabase db;
  late DiveAttachmentsDao dao;
  late List<String> deleted;
  late Future<void> Function(String) deleteFn;

  Future<void> addDeleted(String id, String key, Duration ago) async {
    final t = now.subtract(ago);
    await dao.insertFile(FileAttachment(
      id: id,
      parentKind: DiveAttachmentParentKind.dive,
      parentId: 'd1',
      storageKey: key,
      mimeType: 'application/pdf',
      createdAt: t,
      updatedAt: t,
    ));
    await db.execute(
      'UPDATE dive_attachments SET deleted_at = ? WHERE id = ?',
      [t.millisecondsSinceEpoch, id],
    );
  }

  Future<UploadState> stateOf(String id) async =>
      ((await dao.get(id))! as FileAttachment).uploadState;

  AttachmentPurger purger() =>
      AttachmentPurger(dao: dao, deleteObject: deleteFn, now: () => now);

  setUp(() async {
    db = await openPowerSyncForTest();
    final session = FakeSessionSource()..setUserId('owner-1');
    dao = DiveAttachmentsDao(db, session);
    deleted = [];
    deleteFn = (k) async => deleted.add(k);
  });

  test('deletes the object and marks the row purged', () async {
    await addDeleted('a1', 'attachments/u/d/a1.pdf', const Duration(hours: 25));

    expect(await purger().purgeDeleted(), 1);
    expect(deleted, ['attachments/u/d/a1.pdf']);
    expect(await stateOf('a1'), UploadState.purged);
  });

  test('rows younger than minAge are left alone', () async {
    await addDeleted('a1', 'k1', const Duration(hours: 23));

    expect(await purger().purgeDeleted(), 0);
    expect(deleted, isEmpty);
    expect(await stateOf('a1'), UploadState.pending);
  });

  test('pending: key is marked purged without a delete call', () async {
    await addDeleted('a1', 'pending:a1', const Duration(hours: 30));

    expect(await purger().purgeDeleted(), 1);
    expect(deleted, isEmpty);
    expect(await stateOf('a1'), UploadState.purged);
  });

  test('a failing delete leaves that row unpurged; others still purge',
      () async {
    await addDeleted('bad', 'k-bad', const Duration(hours: 30));
    await addDeleted('good', 'k-good', const Duration(hours: 30));
    deleteFn = (k) async {
      if (k == 'k-bad') throw Exception('boom');
      deleted.add(k);
    };

    expect(await purger().purgeDeleted(), 1);
    expect(deleted, ['k-good']);
    expect(await stateOf('bad'), UploadState.pending);
    expect(await stateOf('good'), UploadState.purged);
  });

  test('overlapping calls share one run', () async {
    await addDeleted('a1', 'k1', const Duration(hours: 30));
    await addDeleted('a2', 'k2', const Duration(hours: 30));
    final gate = Completer<void>();
    deleteFn = (k) async {
      await gate.future;
      deleted.add(k);
    };
    final p = purger();

    final first = p.purgeDeleted();
    final second = p.purgeDeleted();
    gate.complete();

    expect(await first, 2);
    expect(await second, 2);
    expect(deleted..sort(), ['k1', 'k2']);
  });

  test('minAge zero includes a row deleted a second ago', () async {
    await addDeleted('a1', 'k1', const Duration(seconds: 1));

    expect(await purger().purgeDeleted(minAge: Duration.zero), 1);
    expect(deleted, ['k1']);
  });

  test('UNDO during the run keeps the row live and issues no delete',
      () async {
    await addDeleted('a1', 'k1', const Duration(hours: 30));
    await addDeleted('a2', 'k2', const Duration(hours: 30));
    // Whichever row is processed first, its delete restores the other one.
    deleteFn = (k) async {
      deleted.add(k);
      await dao.restore(k == 'k1' ? 'a2' : 'a1');
    };

    expect(await purger().purgeDeleted(), 1);
    expect(deleted, hasLength(1));
    final survivor = deleted.single == 'k1' ? 'a2' : 'a1';
    final got = (await dao.get(survivor))! as FileAttachment;
    expect(got.deletedAt, isNull);
    expect(got.uploadState, isNot(UploadState.purged));
  });

  test('a key rewritten between list and claim is not claimed', () async {
    await addDeleted('a1', 'pending:a1', const Duration(hours: 30));
    deleteFn = (k) async => deleted.add(k);
    final p = AttachmentPurger(
      dao: dao,
      now: () => now,
      deleteObject: deleteFn,
    );
    // Simulate the upload finishing right after the row was listed.
    final run = p.purgeDeleted();
    await dao.markUploaded('a1', checksumSha256: 'x', storageKey: 'real/a1');
    await run;

    expect(deleted, isNot(contains('pending:a1')));
    final got = (await dao.get('a1'))! as FileAttachment;
    expect(got.uploadState, isNot(equals(UploadState.pending)));
  });

  test('a failing delete reverts the claim and the row is listed again',
      () async {
    await addDeleted('a1', 'k1', const Duration(hours: 30));
    deleteFn = (k) async => throw Exception('boom');

    expect(await purger().purgeDeleted(), 0);
    expect(await stateOf('a1'), UploadState.pending);
    expect(
        (await dao.listPurgeable(now)).map((a) => a.id), ['a1']);
  });

  test('a zero-age call during a 24h run chains and purges the fresh row',
      () async {
    await addDeleted('old', 'k-old', const Duration(hours: 30));
    await addDeleted('fresh', 'k-fresh', const Duration(seconds: 1));
    final gate = Completer<void>();
    deleteFn = (k) async {
      await gate.future;
      deleted.add(k);
    };
    final p = purger();

    final slow = p.purgeDeleted();
    final now0 = p.purgeDeleted(minAge: Duration.zero);
    gate.complete();

    expect(await slow, 1);
    expect(await now0, 1);
    expect(deleted..sort(), ['k-fresh', 'k-old']);
    expect(await stateOf('fresh'), UploadState.purged);
  });

  test('hasPurgeable ignores pending: keys', () async {
    await addDeleted('a1', 'pending:a1', const Duration(hours: 30));
    expect(await purger().hasPurgeable(), isFalse);
  });

  test('hasPurgeable ignores the grace period', () async {
    final p = purger();
    expect(await p.hasPurgeable(), isFalse);
    await addDeleted('a1', 'k1', const Duration(seconds: 1));
    expect(await p.hasPurgeable(), isTrue);
    await p.purgeDeleted(minAge: Duration.zero);
    expect(await p.hasPurgeable(), isFalse);
  });

  group('attachments of deleted dives (#198)', () {
    Future<void> liveFileUnderDive(
        String id, String key, Duration diveDeletedAgo) async {
      final t = now.subtract(diveDeletedAgo);
      await db.execute('INSERT INTO dives (id, deleted_at) VALUES (?, ?)',
          ['dive-$id', t.millisecondsSinceEpoch]);
      await dao.insertFile(FileAttachment(
        id: id,
        parentKind: DiveAttachmentParentKind.dive,
        parentId: 'dive-$id',
        storageKey: key,
        mimeType: 'image/jpeg',
        uploadState: UploadState.uploaded,
        createdAt: t,
        updatedAt: t,
      ));
    }

    test('purges a live attachment of a dive deleted over 24 h ago',
        () async {
      await liveFileUnderDive('a1', 'k1', const Duration(days: 3));

      expect(await purger().purgeDeleted(), 1);
      expect(deleted, ['k1']);
      expect(await stateOf('a1'), UploadState.purged);
    });

    test('a recently deleted dive gets the grace period', () async {
      await liveFileUnderDive('a1', 'k1', const Duration(hours: 1));

      expect(await purger().purgeDeleted(), 0);
      expect(deleted, isEmpty);
      // Nothing is written ahead of the purge (#201): the row stays live.
      expect((await dao.get('a1'))!.deletedAt, isNull);
    });

    test('hasPurgeable counts them', () async {
      await liveFileUnderDive('a1', 'k1', const Duration(hours: 1));
      expect(await purger().hasPurgeable(), isTrue);
    });

    test('a dive deleted under 10 minutes ago is left alone', () async {
      // An older build's UNDO doesn't restore attachments, so even a
      // zero-age purge waits until the dive is past its UNDO window.
      await liveFileUnderDive('a1', 'k1', const Duration(minutes: 1));

      expect(await purger().hasPurgeable(), isFalse);
      expect(await purger().purgeDeleted(minAge: Duration.zero), 0);
      expect(deleted, isEmpty);
      expect((await dao.get('a1'))!.deletedAt, isNull);
    });

    test('a dive restored before the sweep keeps its attachment (#201)',
        () async {
      await liveFileUnderDive('a1', 'k1', const Duration(days: 3));
      // The restore made on another device syncs down before the sweep.
      await db.execute(
          'UPDATE dives SET deleted_at = NULL WHERE id = ?', ['dive-a1']);

      expect(await purger().purgeDeleted(minAge: Duration.zero), 0);
      expect(deleted, isEmpty);
      final got = (await dao.get('a1'))! as FileAttachment;
      expect(got.deletedAt, isNull);
      expect(got.uploadState, UploadState.uploaded);
    });

    test('a zero-age purge spares attachments deleted with a recent dive',
        () async {
      // A newer build's dive delete stamps the dive's deleted_at on them.
      await liveFileUnderDive('a1', 'k1', const Duration(minutes: 1));
      final diveDeletedAt = (await db.get(
              'SELECT deleted_at FROM dives WHERE id = ?', ['dive-a1']))[
          'deleted_at'] as int;
      await db.execute(
        'UPDATE dive_attachments SET deleted_at = ? WHERE id = ?',
        [diveDeletedAt, 'a1'],
      );

      expect(await purger().purgeDeleted(minAge: Duration.zero), 0);
      expect(deleted, isEmpty);
      expect(await purger().hasPurgeable(), isFalse);
    });

    test('a failing delete reverts to the state seen by the claim',
        () async {
      // Live at listing; before the claim, an old soft-delete made on
      // another device syncs down. If the R2 delete then fails, the revert
      // must keep that delete, not restore the listing's live row.
      await liveFileUnderDive('a1', 'k1', const Duration(days: 3));
      final otherDeviceDeletedAt = now.subtract(const Duration(days: 2));
      var checks = 0;
      final p = AttachmentPurger(
        dao: dao,
        deleteObject: (k) async => throw Exception('boom'),
        // The second check runs after the listing, just before the claim.
        syncCaughtUp: () async {
          if (++checks == 2) {
            await db.execute(
              'UPDATE dive_attachments SET deleted_at = ?, upload_state = ? '
              'WHERE id = ?',
              [
                otherDeviceDeletedAt.millisecondsSinceEpoch,
                UploadState.failed.wire,
                'a1',
              ],
            );
          }
          return true;
        },
        now: () => now,
      );

      expect(await p.purgeDeleted(), 0);
      final got = (await dao.get('a1'))! as FileAttachment;
      expect(got.deletedAt?.millisecondsSinceEpoch,
          otherDeviceDeletedAt.millisecondsSinceEpoch);
      expect(got.uploadState, UploadState.failed);
    });

    test('a failing delete puts the attachment back live', () async {
      await liveFileUnderDive('a1', 'k1', const Duration(days: 3));
      deleteFn = (k) async => throw Exception('boom');

      expect(await purger().purgeDeleted(), 0);
      final got = (await dao.get('a1'))! as FileAttachment;
      expect(got.deletedAt, isNull);
      expect(got.uploadState, UploadState.uploaded);
    });
  });

  test('nothing is purged while the local data is not fresh (#201)',
      () async {
    await addDeleted('a1', 'k1', const Duration(hours: 30));
    var fresh = false;
    final p = AttachmentPurger(
      dao: dao,
      deleteObject: deleteFn,
      syncCaughtUp: () async => fresh,
      now: () => now,
    );

    await expectLater(
        p.purgeDeleted(), throwsA(isA<SyncNotCaughtUpException>()));
    expect(deleted, isEmpty);
    expect(await stateOf('a1'), UploadState.pending);

    fresh = true;
    expect(await p.purgeDeleted(), 1);
    expect(deleted, ['k1']);
  });

  test('a run stops when the data goes stale mid-run (#201)', () async {
    await addDeleted('a1', 'k1', const Duration(hours: 30));
    await addDeleted('a2', 'k2', const Duration(hours: 30));
    // Fresh for the run's start and the first claim, stale after that.
    var checks = 0;
    final p = AttachmentPurger(
      dao: dao,
      deleteObject: deleteFn,
      syncCaughtUp: () async => ++checks <= 2,
      now: () => now,
    );

    expect(await p.purgeDeleted(), 1);
    expect(deleted, hasLength(1));
  });
}
