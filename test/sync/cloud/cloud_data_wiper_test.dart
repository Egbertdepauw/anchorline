import 'package:ccrlogger/sync/cloud/cloud_data_wiper.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordingDeleter implements CloudOwnerDeleter {
  final List<({String table, String ownerId})> calls = [];

  @override
  Future<void> deleteAllOwnedBy(String table, String ownerId) async {
    calls.add((table: table, ownerId: ownerId));
  }
}

void main() {
  test('signed-in user → deletes once per sync table with their owner_id',
      () async {
    final deleter = _RecordingDeleter();
    final wiper = CloudDataWiper.forTesting(
      deleter: deleter,
      currentUserId: () => 'uid-42',
    );

    await wiper.wipeAllForCurrentUser();

    expect(deleter.calls, hasLength(cloudSyncTables.length));
    expect(
      deleter.calls.map((c) => c.table).toSet(),
      cloudSyncTables.toSet(),
    );
    expect(deleter.calls.every((c) => c.ownerId == 'uid-42'), isTrue);
  });

  test('signed-out (null userId) → no-op, zero deletes', () async {
    final deleter = _RecordingDeleter();
    final wiper = CloudDataWiper.forTesting(
      deleter: deleter,
      currentUserId: () => null,
    );

    await wiper.wipeAllForCurrentUser();

    expect(deleter.calls, isEmpty);
  });

  test('children-before-parents deletion order is preserved', () async {
    final deleter = _RecordingDeleter();
    final wiper = CloudDataWiper.forTesting(
      deleter: deleter,
      currentUserId: () => 'uid-42',
    );

    await wiper.wipeAllForCurrentUser();

    // dive_annotations / dive_cylinders / pressure_mappings reference rows
    // in cylinders + dive_computers; if Postgres ever gains explicit FKs
    // between these tables, the parent-before-child order would 23503.
    final order = deleter.calls.map((c) => c.table).toList();
    expect(
      order.indexOf('pressure_mappings'),
      lessThan(order.indexOf('cylinders')),
    );
    expect(
      order.indexOf('dive_cylinders'),
      lessThan(order.indexOf('cylinders')),
    );
    expect(
      order.indexOf('pressure_mappings'),
      lessThan(order.indexOf('dive_computers')),
    );
  });
}
