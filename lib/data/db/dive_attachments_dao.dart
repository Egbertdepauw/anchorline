/// Data Access Object for dive (and, future, certification) attachments.
///
/// PowerSync-backed (Phase 3). The `dive_attachments` table is single-
/// table with a `kind` column discriminating files vs links — see
/// `supabase/migrations/0004_dive_attachments.sql`. Reads materialise
/// rows into the [DiveAttachment] sealed hierarchy via [_rowToModel].
///
/// `owner_id` is stamped from the current Supabase session at write
/// time; nulls are tolerated locally for offline-without-account edits
/// and get stamped retroactively at upload time once the user signs in
/// (matches [DiveAnnotationsDao]).
///
/// Write-once columns (kind, parent_kind, parent_id, storage_key) are
/// not exposed by [updateMetadata] on purpose — flipping them after
/// create would require coordinated R2 + Postgres surgery, and there's
/// no UI affordance that needs it.
library;

import 'package:drift/drift.dart' show Value;
import 'package:powersync/powersync.dart' hide SyncStatus;

import '../../sync/cloud/ccrlogger_backend_connector.dart' show SessionSource;
import '../models/dive_attachment.dart';

class DiveAttachmentsDao {
  final PowerSyncDatabase _db;
  final SessionSource _session;

  DiveAttachmentsDao(this._db, this._session);

  String? get _ownerId => _session.currentSession?.user.id;

  /// Fires whenever any row in `dive_attachments` is inserted, updated,
  /// or deleted — including PowerSync-driven changes coming from the
  /// cloud. Emits an initial event on subscription.
  Stream<void> watchChanges() =>
      _db.watch('SELECT 1 FROM dive_attachments LIMIT 1').map((_) {});

  // ── Reads ──────────────────────────────────────────────────────────────

  /// Lists live attachments for a dive, mixed kinds, ordered by
  /// display_order ASC then created_at DESC. Soft-deleted rows are
  /// excluded; use [get] to surface them for the UNDO path.
  Future<List<DiveAttachment>> listForDive(String diveId) async {
    final rows = await _db.getAll(
      "SELECT * FROM dive_attachments "
      "WHERE parent_kind = 'dive' AND parent_id = ? AND deleted_at IS NULL "
      "ORDER BY display_order ASC, created_at DESC",
      [diveId],
    );
    return rows.map(_rowToModel).toList();
  }

  /// Returns a single row, including soft-deleted ones — the UNDO path
  /// fetches a tombstoned row and calls [restore].
  Future<DiveAttachment?> get(String id) async {
    final row = await _db
        .getOptional('SELECT * FROM dive_attachments WHERE id = ?', [id]);
    return row == null ? null : _rowToModel(row);
  }

  /// File-only rows whose bytes haven't reached R2 yet (or last attempt
  /// failed). Used by the foreground retry sweep.
  Future<List<FileAttachment>> listPendingUploads() async {
    final rows = await _db.getAll(
      "SELECT * FROM dive_attachments "
      "WHERE kind = 'file' AND upload_state IN (?, ?) AND deleted_at IS NULL",
      [UploadState.pending.wire, UploadState.failed.wire],
    );
    return rows.map(_rowToModel).whereType<FileAttachment>().toList();
  }

  /// File rows soft-deleted before [deletedBefore] whose R2 object has not
  /// been purged yet. Feeds the purge sweep (`AttachmentPurger`).
  Future<List<FileAttachment>> listPurgeable(DateTime deletedBefore) async {
    final rows = await _db.getAll(
      "SELECT * FROM dive_attachments "
      "WHERE kind = 'file' AND deleted_at IS NOT NULL AND deleted_at < ? "
      "AND upload_state != ?",
      [deletedBefore.millisecondsSinceEpoch, UploadState.purged.wire],
    );
    return rows.map(_rowToModel).whereType<FileAttachment>().toList();
  }

  /// Storage keys for every file row attached to a dive (live and
  /// soft-deleted both — the future hard-delete sweep needs the
  /// tombstoned ones too). Link rows have null storage_key and are
  /// excluded by the WHERE.
  Future<List<String>> listStorageKeysForDive(String diveId) async {
    final rows = await _db.getAll(
      "SELECT storage_key FROM dive_attachments "
      "WHERE parent_kind = 'dive' AND parent_id = ? "
      "AND storage_key IS NOT NULL",
      [diveId],
    );
    return rows
        .map((r) => r['storage_key'] as String?)
        .whereType<String>()
        .toList();
  }

  /// Storage keys for every file row in the local PowerSync cache,
  /// regardless of which dive owns them. Used by the Reset-Everything
  /// path to delete the corresponding R2 objects before the cloud rows
  /// (and therefore the keys) are gone. Includes soft-deleted rows for
  /// the same reason — a tombstoned row's R2 object still costs storage.
  Future<List<String>> listAllStorageKeys() async {
    final rows = await _db.getAll(
      "SELECT storage_key FROM dive_attachments "
      "WHERE storage_key IS NOT NULL",
    );
    return rows
        .map((r) => r['storage_key'] as String?)
        .whereType<String>()
        .toList();
  }

  // ── Writes ─────────────────────────────────────────────────────────────

  /// Inserts a new file-kind row. The CHECK constraint on the cloud
  /// table requires storage_key + mime_type to be non-null and url to
  /// be null for files; the model enforces the first two and we set the
  /// third explicitly here so a link-shaped value can never land via
  /// this path.
  Future<void> insertFile(FileAttachment a) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.execute(
      'INSERT INTO dive_attachments '
      '(id, owner_id, parent_kind, parent_id, kind, title, description, '
      'display_order, storage_key, mime_type, size_bytes, original_filename, '
      'checksum_sha256, upload_state, upload_attempts, url, '
      'created_at, updated_at, deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        a.id,
        _ownerId,
        a.parentKind.wire,
        a.parentId,
        'file',
        a.title,
        a.description,
        a.displayOrder,
        a.storageKey,
        a.mimeType,
        a.sizeBytes,
        a.originalFilename,
        a.checksumSha256,
        a.uploadState.wire,
        a.uploadAttempts,
        null, // url is link-only
        a.createdAt.millisecondsSinceEpoch,
        now,
        a.deletedAt?.millisecondsSinceEpoch,
        a.version,
        a.syncStatus.index,
      ],
    );
  }

  /// Inserts a new link-kind row. Mirrors [insertFile]; file columns
  /// stay null per the cloud CHECK constraint.
  Future<void> insertLink(LinkAttachment a) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.execute(
      'INSERT INTO dive_attachments '
      '(id, owner_id, parent_kind, parent_id, kind, title, description, '
      'display_order, storage_key, mime_type, size_bytes, original_filename, '
      'checksum_sha256, upload_state, upload_attempts, url, '
      'created_at, updated_at, deleted_at, version, sync_status) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        a.id,
        _ownerId,
        a.parentKind.wire,
        a.parentId,
        'link',
        a.title,
        a.description,
        a.displayOrder,
        null, // storage_key is file-only
        null, // mime_type is file-only
        null, // size_bytes is file-only
        null, // original_filename is file-only
        null, // checksum_sha256 is file-only
        UploadState.pending.wire, // unused for links; column is NOT NULL
        0,
        a.url,
        a.createdAt.millisecondsSinceEpoch,
        now,
        a.deletedAt?.millisecondsSinceEpoch,
        a.version,
        a.syncStatus.index,
      ],
    );
  }

  /// Partial update of mutable user-facing metadata. Each parameter
  /// uses Drift's [Value] sentinel: omitted = leave alone, `Value(null)`
  /// = explicitly clear the column, `Value(x)` = set to x. We fetch the
  /// existing row first inside a write transaction so nothing else can
  /// race the version bump.
  ///
  /// Kind / parent / storage_key are write-once and not parameters.
  Future<void> updateMetadata(
    String id, {
    Value<String?>? title,
    Value<String?>? description,
    int? displayOrder,
    Value<String?>? url,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version, title, description, display_order, url, kind '
        'FROM dive_attachments WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      // Guard: link rows must keep a url; file rows must keep null.
      // If a caller passes the wrong shape we silently ignore the url
      // change rather than write a row that violates the cloud CHECK.
      final kind = existing['kind'] as String;
      final newTitle = title == null ? existing['title'] as String? : title.value;
      final newDescription = description == null
          ? existing['description'] as String?
          : description.value;
      final newDisplayOrder =
          displayOrder ?? (existing['display_order'] as int? ?? 0);
      final newUrl = (url == null || kind != 'link')
          ? existing['url'] as String?
          : url.value;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_attachments SET '
        'owner_id = ?, '
        'title = ?, '
        'description = ?, '
        'display_order = ?, '
        'url = ?, '
        'updated_at = ?, '
        'version = ? '
        'WHERE id = ?',
        [
          _ownerId,
          newTitle,
          newDescription,
          newDisplayOrder,
          newUrl,
          now,
          newVersion,
          id,
        ],
      );
    });
  }

  /// Records that R2 accepted the bytes. Stamps the checksum so future
  /// integrity checks have a reference value, flips upload_state to
  /// uploaded, and bumps version so the change rides PowerSync up.
  ///
  /// [storageKey] is also rewritten here: the notifier inserts a row
  /// with a `pending:<id>` sentinel because the Worker is the authority
  /// on the final R2 object key, and we don't know it until the Worker
  /// signs the upload. The uploader passes the Worker-returned key in.
  Future<void> markUploaded(
    String id, {
    required String checksumSha256,
    required String storageKey,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM dive_attachments WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_attachments SET '
        'owner_id = ?, '
        'upload_state = ?, '
        'checksum_sha256 = ?, '
        'storage_key = ?, '
        'updated_at = ?, '
        'version = ? '
        'WHERE id = ?',
        [
          _ownerId,
          UploadState.uploaded.wire,
          checksumSha256,
          storageKey,
          now,
          newVersion,
          id,
        ],
      );
    });
  }

  /// Records that the most recent R2 upload attempt errored. The retry
  /// sweep uses upload_attempts to back off / give up.
  Future<void> markUploadFailed(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version, upload_attempts FROM dive_attachments WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      final newAttempts = (existing['upload_attempts'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_attachments SET '
        'owner_id = ?, '
        'upload_state = ?, '
        'upload_attempts = ?, '
        'updated_at = ?, '
        'version = ? '
        'WHERE id = ?',
        [
          _ownerId,
          UploadState.failed.wire,
          newAttempts,
          now,
          newVersion,
          id,
        ],
      );
    });
  }

  /// Claims a soft-deleted file row for purging: sets `upload_state = 3`
  /// (bumping version, updated_at, owner_id like [markUploadFailed]) only if
  /// the row is still soft-deleted, still has [expectedKey], and is not
  /// already purged. Returns whether the claim succeeded. The purger claims
  /// BEFORE deleting the R2 object so a concurrent UNDO ([restore]) or a
  /// finishing upload ([markUploaded]) can't race the delete.
  Future<bool> markPurged(String id, {required String expectedKey}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM dive_attachments '
        'WHERE id = ? AND deleted_at IS NOT NULL AND storage_key = ? '
        'AND upload_state != ?',
        [id, expectedKey, UploadState.purged.wire],
      );
      if (existing == null) return false;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_attachments SET '
        'owner_id = ?, upload_state = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, UploadState.purged.wire, now, newVersion, id],
      );
      return true;
    });
  }

  /// Undoes a [markPurged] claim when the R2 delete failed, restoring the
  /// row's [previous] upload state so the next sweep retries it. Only
  /// touches a row that is still purged with [expectedKey].
  Future<void> revertPurge(
    String id, {
    required String expectedKey,
    required UploadState previous,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM dive_attachments '
        'WHERE id = ? AND upload_state = ? AND storage_key = ?',
        [id, UploadState.purged.wire, expectedKey],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_attachments SET '
        'owner_id = ?, upload_state = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, previous.wire, now, newVersion, id],
      );
    });
  }

  /// Soft-deletes a row. The R2 object stays put until the purge sweep
  /// (`AttachmentPurger`) deletes it, 24 h later, and marks the row
  /// purged via [markPurged].
  /// Mirrors [DiveDao.softDeleteDive]'s version-bump pattern.
  Future<void> softDelete(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version FROM dive_attachments WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_attachments SET '
        'owner_id = ?, deleted_at = ?, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, now, now, newVersion, id],
      );
    });
  }

  /// Clears the soft-delete flag — paired with the SnackBar UNDO action.
  /// A purged row (R2 object already gone) stays deleted: no-op.
  Future<void> restore(String id) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.writeTransaction((tx) async {
      final existing = await tx.getOptional(
        'SELECT version, upload_state FROM dive_attachments WHERE id = ?',
        [id],
      );
      if (existing == null) return;
      if (existing['upload_state'] == UploadState.purged.wire) return;
      final newVersion = (existing['version'] as int? ?? 0) + 1;
      await tx.execute(
        'UPDATE dive_attachments SET '
        'owner_id = ?, deleted_at = NULL, updated_at = ?, version = ? '
        'WHERE id = ?',
        [_ownerId, now, newVersion, id],
      );
    });
  }

  // ── Mapping helpers ─────────────────────────────────────────────────────

  DiveAttachment _rowToModel(Map<String, dynamic> row) {
    final kind = row['kind'] as String;
    final id = row['id'] as String;
    final parentKind =
        DiveAttachmentParentKind.fromWire(row['parent_kind'] as String);
    final parentId = row['parent_id'] as String;
    final title = row['title'] as String?;
    final description = row['description'] as String?;
    final displayOrder = row['display_order'] as int? ?? 0;
    final createdAt =
        DateTime.fromMillisecondsSinceEpoch(row['created_at'] as int);
    final updatedAt =
        DateTime.fromMillisecondsSinceEpoch(row['updated_at'] as int);
    final deletedAtMs = row['deleted_at'] as int?;
    final deletedAt = deletedAtMs == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(deletedAtMs);
    final version = row['version'] as int? ?? 1;
    final syncStatusIdx = row['sync_status'] as int? ?? 0;
    final syncStatus = SyncStatus.values[
        syncStatusIdx.clamp(0, SyncStatus.values.length - 1)];

    if (kind == 'file') {
      return FileAttachment(
        id: id,
        parentKind: parentKind,
        parentId: parentId,
        title: title,
        description: description,
        displayOrder: displayOrder,
        storageKey: row['storage_key'] as String,
        mimeType: row['mime_type'] as String,
        sizeBytes: row['size_bytes'] as int?,
        originalFilename: row['original_filename'] as String?,
        checksumSha256: row['checksum_sha256'] as String?,
        uploadState: UploadState.fromWire(row['upload_state'] as int? ?? 0),
        uploadAttempts: row['upload_attempts'] as int? ?? 0,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        version: version,
        syncStatus: syncStatus,
      );
    }
    return LinkAttachment(
      id: id,
      parentKind: parentKind,
      parentId: parentId,
      title: title,
      description: description,
      displayOrder: displayOrder,
      url: row['url'] as String,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      version: version,
      syncStatus: syncStatus,
    );
  }
}
