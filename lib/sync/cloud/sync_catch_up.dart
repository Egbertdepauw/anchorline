/// Tells whether the local PowerSync data has caught up with the server
/// since a given moment, and runs work once it has.
///
/// `SyncStatus.connected` alone isn't enough: after a sleep or resume it can
/// still show the old connection, and `lastSyncedAt` survives restarts. So
/// the data counts as caught up only when a sync completed at or after the
/// last [markStale] (or creation), while connected and not downloading.
/// Used to keep the attachment purge from acting on stale data (#201).
library;

import 'dart:async';

/// The parts of PowerSync's `SyncStatus` that [SyncCatchUp] reads.
typedef SyncState = ({
  bool connected,
  bool downloading,
  DateTime? lastSyncedAt,
});

class SyncCatchUp {
  SyncCatchUp({
    required SyncState Function() current,
    required Stream<Object?> changes,
    DateTime Function()? now,
  })  : _current = current,
        _now = now ?? DateTime.now {
    _needAfter = _now();
    _sub = changes.listen((_) => _runPending());
  }

  final SyncState Function() _current;
  final DateTime Function() _now;
  late final StreamSubscription<Object?> _sub;
  late DateTime _needAfter;
  void Function()? _pending;
  final _caughtUpWaiters = <Completer<bool>>[];

  /// The data may be stale from now on: a later sync must complete before
  /// [caughtUp] is true again. Call on resume and sign-in.
  void markStale() => _needAfter = _now();

  bool get caughtUp {
    final s = _current();
    final last = s.lastSyncedAt;
    if (!s.connected || s.downloading || last == null) return false;
    // lastSyncedAt has whole-second precision.
    final floor = DateTime.fromMillisecondsSinceEpoch(
      _needAfter.millisecondsSinceEpoch ~/ 1000 * 1000,
    );
    return !last.isBefore(floor);
  }

  /// Runs [action] now if [caughtUp], otherwise on the first status change
  /// after which it is. A newer call replaces a pending one.
  void runWhenCaughtUp(void Function() action) {
    if (caughtUp) {
      _pending = null;
      action();
    } else {
      _pending = action;
    }
  }

  /// Resolves to true as soon as [caughtUp] is, or false after [timeout].
  Future<bool> waitCaughtUp({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (caughtUp) return true;
    final c = Completer<bool>();
    _caughtUpWaiters.add(c);
    final timer = Timer(timeout, () {
      if (!c.isCompleted) c.complete(false);
    });
    final result = await c.future;
    timer.cancel();
    _caughtUpWaiters.remove(c);
    return result;
  }

  void _runPending() {
    if (!caughtUp) return;
    for (final c in List.of(_caughtUpWaiters)) {
      if (!c.isCompleted) c.complete(true);
    }
    final p = _pending;
    _pending = null;
    p?.call();
  }

  void dispose() {
    _sub.cancel();
    for (final c in _caughtUpWaiters) {
      if (!c.isCompleted) c.complete(false);
    }
  }
}
