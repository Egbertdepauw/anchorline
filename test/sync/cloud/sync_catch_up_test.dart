import 'dart:async';

import 'package:ccrlogger/sync/cloud/sync_catch_up.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late SyncState status;
  late StreamController<SyncState> changes;
  late SyncCatchUp gate;

  void emit(SyncState s) {
    status = s;
    changes.add(s);
  }

  SyncState synced(DateTime at, {bool downloading = false}) =>
      (connected: true, downloading: downloading, lastSyncedAt: at);

  setUp(() {
    now = DateTime(2026, 11, 11, 12);
    // Synced before the app (re)started: stale until a newer sync.
    status = synced(now.subtract(const Duration(hours: 3)));
    changes = StreamController<SyncState>.broadcast(sync: true);
    gate = SyncCatchUp(
      current: () => status,
      changes: changes.stream,
      now: () => now,
    );
  });

  tearDown(() async {
    gate.dispose();
    await changes.close();
  });

  test('a sync from before creation does not count', () {
    expect(gate.caughtUp, isFalse);
  });

  test('a sync completed after creation counts', () {
    emit(synced(now.add(const Duration(seconds: 2))));
    expect(gate.caughtUp, isTrue);
  });

  test('a sync in the same second counts (whole-second precision)', () {
    final at = now.add(const Duration(milliseconds: 400));
    now = at;
    gate.markStale();
    emit(synced(DateTime.fromMillisecondsSinceEpoch(
        at.millisecondsSinceEpoch ~/ 1000 * 1000)));
    expect(gate.caughtUp, isTrue);
  });

  test('disconnected or downloading does not count', () {
    final later = now.add(const Duration(seconds: 2));
    emit((connected: false, downloading: false, lastSyncedAt: later));
    expect(gate.caughtUp, isFalse);
    emit(synced(later, downloading: true));
    expect(gate.caughtUp, isFalse);
  });

  test('markStale (resume) needs a newer sync, even while "connected"', () {
    emit(synced(now.add(const Duration(seconds: 2))));
    expect(gate.caughtUp, isTrue);

    // Resume after a sleep: the status still shows the old connection.
    now = now.add(const Duration(hours: 1));
    gate.markStale();
    expect(gate.caughtUp, isFalse);

    emit(synced(now.add(const Duration(seconds: 1))));
    expect(gate.caughtUp, isTrue);
  });

  test('runWhenCaughtUp defers until a fresh sync, then runs once', () {
    var runs = 0;
    gate.runWhenCaughtUp(() => runs++);
    expect(runs, 0);

    emit(synced(now.add(const Duration(seconds: 1)), downloading: true));
    expect(runs, 0);
    emit(synced(now.add(const Duration(seconds: 2))));
    expect(runs, 1);
    emit(synced(now.add(const Duration(seconds: 3))));
    expect(runs, 1);
  });

  test('runWhenCaughtUp runs at once when caught up', () {
    emit(synced(now.add(const Duration(seconds: 1))));
    var runs = 0;
    gate.runWhenCaughtUp(() => runs++);
    expect(runs, 1);
  });

  test('waitCaughtUp resolves true on a fresh sync', () async {
    final wait = gate.waitCaughtUp();
    emit(synced(now.add(const Duration(seconds: 1))));
    expect(await wait, isTrue);
  });

  test('waitCaughtUp resolves false after the timeout', () async {
    expect(
      await gate.waitCaughtUp(timeout: const Duration(milliseconds: 20)),
      isFalse,
    );
  });
}
