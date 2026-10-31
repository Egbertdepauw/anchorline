/// Deletes every cloud row owned by the currently-authenticated user.
///
/// Used by the Settings → Danger zone "Reset everything" path. RLS on
/// the Postgres side already scopes deletes to the caller, but we also
/// pass an explicit `owner_id` filter to keep the SQL self-evident in
/// the Supabase logs.
///
/// The local PowerSync cache is wiped separately by the caller — this
/// helper only touches the cloud. Best-called BEFORE
/// `PowerSyncDatabase.disconnectAndClear()` so logical-replication
/// deletes can propagate cleanly to other devices.
library;

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Sync-eligible tables in deletion order. Children before parents to
/// avoid FK-violation surprises if Postgres ever gains explicit FKs
/// between these (currently only `auth.users` is referenced).
const cloudSyncTables = <String>[
  // Children that reference dives by id. Some have enforced FKs
  // (dive_bailout_carry → dives), some don't, but the ordering reflects
  // intent and saves us from future foot-guns when more FKs land.
  // When you add a new table that references `dives.id`, append it
  // HERE — above the dives delete — or the cloud wipe will fail with
  // a Postgrest 23503 foreign-key-violation.
  'dive_attachments',
  'dive_annotations',
  'pressure_mappings',
  'dive_cylinders',
  'dive_bailout_carry',
  // Sample data + dive rows. dive_samples FK-cascades from dives via
  // its `id` column, but we delete it explicitly first so we don't
  // depend on RLS-allowed cascades — keeps the Supabase log readable.
  // Without these two lines, the cloud wipe would leave the user's
  // dive rows in Postgres; PowerSync would re-sync them on next
  // reconnect and "Reset Everything" wouldn't actually wipe dives.
  'dive_samples',
  'dives',
  // Gas analyses soft-reference cylinders (no FK); listed before them
  // anyway so a future FK can't break the wipe.
  'gas_analyses',
  // Equipment / device parents.
  'cylinders',
  'oxygen_cells',
  'scrubber_sessions',
  'dive_computers',
];

/// Thin abstraction over the Supabase delete-by-owner operation, so
/// tests can record the calls without faking the whole query-builder.
abstract class CloudOwnerDeleter {
  Future<void> deleteAllOwnedBy(String table, String ownerId);
}

class SupabaseCloudOwnerDeleter implements CloudOwnerDeleter {
  final SupabaseClient _client;
  SupabaseCloudOwnerDeleter(this._client);

  @override
  Future<void> deleteAllOwnedBy(String table, String ownerId) =>
      _client.from(table).delete().eq('owner_id', ownerId);
}

class CloudDataWiper {
  final CloudOwnerDeleter _deleter;
  final String? Function() _currentUserId;

  CloudDataWiper(SupabaseClient client)
      : _deleter = SupabaseCloudOwnerDeleter(client),
        _currentUserId = (() => client.auth.currentUser?.id);

  /// Test seam: inject a fake deleter + userId provider directly.
  @visibleForTesting
  CloudDataWiper.forTesting({
    required CloudOwnerDeleter deleter,
    required String? Function() currentUserId,
  })  : _deleter = deleter,
        _currentUserId = currentUserId;

  /// Deletes every row this user owns across [cloudSyncTables].
  /// No-op if the user is signed out. Errors propagate.
  Future<void> wipeAllForCurrentUser() async {
    final userId = _currentUserId();
    if (userId == null) return;
    for (final table in cloudSyncTables) {
      await _deleter.deleteAllOwnedBy(table, userId);
    }
  }
}
