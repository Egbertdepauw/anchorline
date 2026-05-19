/// Write-only beta telemetry channel: records `user did X at time T`
/// events into the Supabase `usage_events` table so we can see which
/// features actually get used and prioritise tier-split / paid-tier
/// design from data instead of guesses.
///
/// Three guard rails:
///
/// 1. **kReleaseMode-only.** Debug builds (you, iterating) do not fire
///    telemetry — keeps dev sessions out of the analytics stream and
///    keeps the dashboard signal-to-noise high.
/// 2. **Signed-in users only.** No session → silently drop the event.
///    The RLS policy on the table is the server-side enforcement of
///    the same rule; this client check just avoids a guaranteed-fail
///    round-trip.
/// 3. **Never crashes the app.** A failed insert (network down, server
///    error, RLS reject) is debug-logged and swallowed. Telemetry is
///    a "nice to have" — it must never block a real user flow.
///
/// See [`supabase/migrations/0012_usage_events.sql`](../../../supabase/migrations/0012_usage_events.sql)
/// for the table + RLS.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UsageTracker {
  UsageTracker(this._supabase);

  final SupabaseClient _supabase;

  /// Record a single beta-usage event. Fire-and-forget — the call
  /// returns immediately and the underlying insert runs in the
  /// background. Failures are swallowed; see class docs for why.
  ///
  /// [eventName] should be `snake_case` and stable over time so dashboard
  /// queries don't break when we rename in code. Keep it short. Examples:
  ///   - `import_completed`
  ///   - `dive_opened`
  ///   - `subsurface_sync_triggered`
  ///   - `attachment_added`
  ///
  /// [properties] is free-form per-event metadata (counts, codes, flags).
  /// Avoid putting PII or user-typed strings here — this table is
  /// telemetry, not a backup. `{ 'count': 47 }` is great;
  /// `{ 'notes': "free-text dive notes" }` is not.
  void track(String eventName, [Map<String, Object?>? properties]) {
    if (!kReleaseMode) return;
    final session = _supabase.auth.currentSession;
    if (session == null) return;

    // Fire-and-forget. We deliberately don't await so the caller doesn't
    // pay any latency for telemetry; any error inside the async chain
    // is caught and dropped below.
    () async {
      try {
        await _supabase.from('usage_events').insert({
          'owner_id': session.user.id,
          'event_name': eventName,
          'properties': ?properties,
        });
      } catch (e) {
        debugPrint('UsageTracker drop $eventName: $e');
      }
    }();
  }
}
