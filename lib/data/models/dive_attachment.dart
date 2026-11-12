/// User-attached files and links on a dive (or, in a Phase 3 follow-up,
/// a certification). The cloud table is single-table with a `kind`
/// discriminator — see `supabase/migrations/0004_dive_attachments.sql`
/// for the rationale. The Dart side mirrors that with a sealed
/// hierarchy so callers don't have to repeat null-checks for "is this a
/// file or a link?" — pattern matching does it.
///
/// Sync metadata fields are present from day one (per CLAUDE.md
/// principle 6). [SyncStatus] is reused from `annotation.dart` rather
/// than redefined here; one canonical enum keeps PowerSync's
/// `sync_status` integer column unambiguous across DAOs.
library;

import 'package:drift/drift.dart' show Value;

import 'package:subsurface_core/data/models/annotation.dart' show SyncStatus;

export 'package:subsurface_core/data/models/annotation.dart' show SyncStatus;

/// What kind of entity this attachment hangs off of. The cloud schema's
/// `parent_kind` CHECK constraint enforces these values; the Dart enum
/// is documentation. v1 always uses [DiveAttachmentParentKind.dive].
enum DiveAttachmentParentKind {
  dive('dive'),
  certification('certification');

  final String wire;
  const DiveAttachmentParentKind(this.wire);

  static DiveAttachmentParentKind fromWire(String s) {
    for (final v in values) {
      if (v.wire == s) return v;
    }
    throw ArgumentError('Unknown parent_kind: $s');
  }
}

/// Lifecycle of a [FileAttachment]'s bytes in R2. Ints match the column:
/// 0 = pending (row exists, bytes haven't reached R2 yet),
/// 1 = uploaded (bytes are durable, checksum recorded),
/// 2 = failed (last upload attempt errored; retry sweep will pick it up),
/// 3 = purged (the R2 object was deleted after the row was soft-deleted;
/// such a row is always soft-deleted and must never be restored).
/// Link attachments don't use this; the column stays at 0 for them.
enum UploadState {
  pending(0),
  uploaded(1),
  failed(2),
  purged(3);

  final int wire;
  const UploadState(this.wire);

  static UploadState fromWire(int i) {
    for (final v in values) {
      if (v.wire == i) return v;
    }
    return UploadState.pending;
  }
}

/// Sealed base — common metadata shared by file and link attachments.
/// Subclasses carry the kind-specific columns. The seam between this
/// model and the wire row is in `DiveAttachmentsDao._rowToModel`.
sealed class DiveAttachment {
  final String id;
  final DiveAttachmentParentKind parentKind;
  final String parentId;
  final String? title;
  final String? description;
  final int displayOrder;

  // Sync metadata (see CLAUDE.md principle 6).
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int version;
  final SyncStatus syncStatus;

  const DiveAttachment({
    required this.id,
    required this.parentKind,
    required this.parentId,
    this.title,
    this.description,
    this.displayOrder = 0,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.version = 1,
    this.syncStatus = SyncStatus.pending,
  });
}

class FileAttachment extends DiveAttachment {
  /// R2 object key — see migration 0004 for the layout.
  final String storageKey;
  final String mimeType;
  final int? sizeBytes;
  final String? originalFilename;
  final String? checksumSha256;
  final UploadState uploadState;
  final int uploadAttempts;

  const FileAttachment({
    required super.id,
    required super.parentKind,
    required super.parentId,
    super.title,
    super.description,
    super.displayOrder,
    required this.storageKey,
    required this.mimeType,
    this.sizeBytes,
    this.originalFilename,
    this.checksumSha256,
    this.uploadState = UploadState.pending,
    this.uploadAttempts = 0,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    super.version,
    super.syncStatus,
  });

  FileAttachment copyWith({
    String? id,
    DiveAttachmentParentKind? parentKind,
    String? parentId,
    Value<String?>? title,
    Value<String?>? description,
    int? displayOrder,
    String? storageKey,
    String? mimeType,
    Value<int?>? sizeBytes,
    Value<String?>? originalFilename,
    Value<String?>? checksumSha256,
    UploadState? uploadState,
    int? uploadAttempts,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?>? deletedAt,
    int? version,
    SyncStatus? syncStatus,
  }) =>
      FileAttachment(
        id: id ?? this.id,
        parentKind: parentKind ?? this.parentKind,
        parentId: parentId ?? this.parentId,
        title: title == null ? this.title : title.value,
        description: description == null ? this.description : description.value,
        displayOrder: displayOrder ?? this.displayOrder,
        storageKey: storageKey ?? this.storageKey,
        mimeType: mimeType ?? this.mimeType,
        sizeBytes: sizeBytes == null ? this.sizeBytes : sizeBytes.value,
        originalFilename: originalFilename == null
            ? this.originalFilename
            : originalFilename.value,
        checksumSha256: checksumSha256 == null
            ? this.checksumSha256
            : checksumSha256.value,
        uploadState: uploadState ?? this.uploadState,
        uploadAttempts: uploadAttempts ?? this.uploadAttempts,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt == null ? this.deletedAt : deletedAt.value,
        version: version ?? this.version,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}

class LinkAttachment extends DiveAttachment {
  final String url;

  const LinkAttachment({
    required super.id,
    required super.parentKind,
    required super.parentId,
    super.title,
    super.description,
    super.displayOrder,
    required this.url,
    required super.createdAt,
    required super.updatedAt,
    super.deletedAt,
    super.version,
    super.syncStatus,
  });

  LinkAttachment copyWith({
    String? id,
    DiveAttachmentParentKind? parentKind,
    String? parentId,
    Value<String?>? title,
    Value<String?>? description,
    int? displayOrder,
    String? url,
    DateTime? createdAt,
    DateTime? updatedAt,
    Value<DateTime?>? deletedAt,
    int? version,
    SyncStatus? syncStatus,
  }) =>
      LinkAttachment(
        id: id ?? this.id,
        parentKind: parentKind ?? this.parentKind,
        parentId: parentId ?? this.parentId,
        title: title == null ? this.title : title.value,
        description: description == null ? this.description : description.value,
        displayOrder: displayOrder ?? this.displayOrder,
        url: url ?? this.url,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: deletedAt == null ? this.deletedAt : deletedAt.value,
        version: version ?? this.version,
        syncStatus: syncStatus ?? this.syncStatus,
      );
}
