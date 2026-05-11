/// Polls Supabase's `public.sync_health_check()` RPC to surface
/// replication-slot WAL retention in the UI before it crosses the
/// Postgres-level `max_slot_wal_keep_size = 1GB` cap that would
/// invalidate the slot and force a full PowerSync re-bootstrap.
///
/// Layers of defence (most-aggressive last):
///
///   1. App banner at `warn` (≥256 MB retained) — user-actionable
///      "keep the app open / sign in on the device that's holding
///      the queue".
///   2. App banner at `critical` (≥768 MB retained) — telling the
///      user a slot reset is imminent.
///   3. Postgres-side: at 1 GB the slot is invalidated; pg_cron's
///      `reap_stale_replication_slots()` then drops it within 15 min
///      and PowerSync re-bootstraps clients on next reconnect.
///
/// This service is the eyes for layer 1+2. It calls the RPC every
/// [pollInterval] (default 5 min) while at least one slot is being
/// observed, and exposes a [ChangeNotifier]-driven snapshot to the
/// banner widget.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// One row from the RPC (1:1 with a row of `pg_replication_slots`).
@immutable
class SyncHealthSlot {
  final String slotName;
  final bool active;
  final String walStatus;
  final int retainedMb;

  const SyncHealthSlot({
    required this.slotName,
    required this.active,
    required this.walStatus,
    required this.retainedMb,
  });

  factory SyncHealthSlot.fromJson(Map<String, dynamic> j) => SyncHealthSlot(
        slotName: j['slot_name'] as String,
        active: j['active'] as bool? ?? false,
        walStatus: j['wal_status'] as String? ?? 'unknown',
        retainedMb: (j['retained_mb'] as num?)?.toInt() ?? 0,
      );
}

/// Severity escalation. Maps onto the banner colour / message.
enum SyncHealthSeverity { ok, warn, critical }

@immutable
class SyncHealthSnapshot {
  /// Worst slot in the set (highest [SyncHealthSeverity]); null when
  /// the service hasn't polled yet or no slots exist.
  final SyncHealthSlot? worst;

  /// All slots seen on the last poll; useful for diagnostics.
  final List<SyncHealthSlot> slots;

  final SyncHealthSeverity severity;
  final DateTime polledAt;

  /// True when the most-recent poll failed. The banner stays hidden in
  /// this case — a transient API blip shouldn't escalate to "your
  /// database is dying" — but a developer reading logs sees the cause.
  final bool degraded;

  const SyncHealthSnapshot({
    required this.worst,
    required this.slots,
    required this.severity,
    required this.polledAt,
    this.degraded = false,
  });

  /// Convenience flag — banner shows when severity is anything other
  /// than `ok` AND we have fresh data.
  bool get shouldShowBanner => severity != SyncHealthSeverity.ok && !degraded;
}

/// Pure threshold function — extracted so widget tests can exercise it
/// without spinning up Supabase. Mirrors the docstring at the top.
SyncHealthSeverity classifySeverity(SyncHealthSlot slot) {
  // Postgres has already invalidated the slot — PowerSync's next
  // reconnect will trigger a full re-bootstrap. Surface critical.
  if (slot.walStatus == 'lost') return SyncHealthSeverity.critical;
  if (slot.retainedMb >= 768) return SyncHealthSeverity.critical;
  if (slot.retainedMb >= 256) return SyncHealthSeverity.warn;
  return SyncHealthSeverity.ok;
}

/// Thin seam over the Supabase RPC so tests can fake the wire format.
abstract class SyncHealthClient {
  Future<List<SyncHealthSlot>> fetch();
}

class SupabaseSyncHealthClient implements SyncHealthClient {
  final SupabaseClient _client;
  SupabaseSyncHealthClient(this._client);

  @override
  Future<List<SyncHealthSlot>> fetch() async {
    final raw = await _client.rpc<List<dynamic>>('sync_health_check');
    return raw
        .cast<Map<String, dynamic>>()
        .map(SyncHealthSlot.fromJson)
        .toList(growable: false);
  }
}

/// Polls the RPC on a fixed cadence; signals listeners on every poll.
class SyncHealthService extends ChangeNotifier {
  final SyncHealthClient _client;
  final Duration pollInterval;

  SyncHealthSnapshot? _snapshot;
  Timer? _timer;

  SyncHealthService(
    this._client, {
    this.pollInterval = const Duration(minutes: 5),
  });

  SyncHealthSnapshot? get snapshot => _snapshot;

  /// Start polling. Calls the RPC immediately, then on the cadence.
  /// Idempotent — calling twice does nothing on the second call.
  void start() {
    if (_timer != null) return;
    unawaited(_pollOnce());
    _timer = Timer.periodic(pollInterval, (_) => _pollOnce());
  }

  /// Stop polling. The last [snapshot] is preserved.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Force a one-off poll outside the cadence — useful from a "retry"
  /// button or right after sign-in.
  Future<void> refresh() => _pollOnce();

  Future<void> _pollOnce() async {
    try {
      final slots = await _client.fetch();
      SyncHealthSlot? worst;
      var worstSeverity = SyncHealthSeverity.ok;
      for (final s in slots) {
        final sev = classifySeverity(s);
        if (sev.index > worstSeverity.index) {
          worstSeverity = sev;
          worst = s;
        }
      }
      _snapshot = SyncHealthSnapshot(
        worst: worst,
        slots: slots,
        severity: worstSeverity,
        polledAt: DateTime.now(),
      );
    } catch (e, st) {
      debugPrint('SyncHealthService poll failed: $e\n$st');
      _snapshot = SyncHealthSnapshot(
        worst: _snapshot?.worst,
        slots: _snapshot?.slots ?? const [],
        severity: SyncHealthSeverity.ok,
        polledAt: DateTime.now(),
        degraded: true,
      );
    }
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
