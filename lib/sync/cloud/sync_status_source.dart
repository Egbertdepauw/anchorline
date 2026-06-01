/// Read-only view of [PowerSyncDatabase]'s sync status, narrow enough
/// to inject a fake in widget tests without dragging the whole
/// PowerSync database in.
///
/// We expose a project-owned [SyncStatusSnapshot] rather than PowerSync's
/// own [SyncStatus] because PowerSync marks its constructor `@internal`
/// — only PowerSync's package can instantiate it. Mapping at the boundary
/// keeps tests free to construct snapshots directly.
library;

import 'package:powersync/powersync.dart';

class SyncStatusSnapshot {
  final bool connected;
  final bool uploading;
  final bool downloading;
  final DateTime? lastSyncedAt;

  /// Last upload / download error PowerSync recorded, as a string (the
  /// underlying field is `Object?`). Surfaced so a stalled upload queue is
  /// diagnosable: when the upload pump is wedged on a rejected ("poison")
  /// CRUD op, PowerSync stores the failure here even though `uploading`
  /// reads false between retries. See issue #2.
  final String? uploadError;
  final String? downloadError;

  const SyncStatusSnapshot({
    this.connected = false,
    this.uploading = false,
    this.downloading = false,
    this.lastSyncedAt,
    this.uploadError,
    this.downloadError,
  });

  factory SyncStatusSnapshot.fromPowerSync(SyncStatus s) => SyncStatusSnapshot(
        connected: s.connected,
        uploading: s.uploading,
        downloading: s.downloading,
        lastSyncedAt: s.lastSyncedAt,
        uploadError: s.uploadError?.toString(),
        downloadError: s.downloadError?.toString(),
      );
}

abstract class SyncStatusSource {
  SyncStatusSnapshot get currentStatus;
  Stream<SyncStatusSnapshot> get statusStream;
}

class PowerSyncStatusSource implements SyncStatusSource {
  final PowerSyncDatabase _db;
  PowerSyncStatusSource(this._db);

  @override
  SyncStatusSnapshot get currentStatus =>
      SyncStatusSnapshot.fromPowerSync(_db.currentStatus);

  @override
  Stream<SyncStatusSnapshot> get statusStream =>
      _db.statusStream.map(SyncStatusSnapshot.fromPowerSync);
}
