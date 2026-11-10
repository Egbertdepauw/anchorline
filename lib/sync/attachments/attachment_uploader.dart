/// Abstract seam between the dive-attachments notifier and the Phase E
/// HTTP/R2 uploader. Defining this interface in Phase C lets the
/// notifier and its tests build against a fake while the real
/// implementation (which pairs an `AttachmentSigner` with an http
/// client and owns the on-disk pending-uploads cache) ships
/// separately as `attachment_uploader_impl.dart`.
///
/// Contract:
/// * The DAO row has already been inserted by the notifier, with
///   `upload_state = pending` and a `pending:<id>` sentinel
///   `storage_key`. The implementation is responsible for flipping
///   the row's terminal state via the DAO:
///     - on success: `DAO.markUploaded(id, checksumSha256, storageKey)`
///       where `storageKey` is the canonical key the Worker returned;
///     - on failure: `DAO.markUploadFailed(id)`.
/// * On failure the implementation rethrows so the notifier can
///   surface the error to the UI; the DAO row stays in `failed`.
/// * The implementation owns its own local file cache for retries —
///   the notifier never needs to know where bytes live on disk.
library;

import 'dart:io';

import '../../data/models/dive_attachment.dart';

abstract class AttachmentUploader {
  /// Uploads [localFile] for the previously-inserted [attachmentId]
  /// row attached to [diveId]. The notifier has already inserted a
  /// `pending` row; the impl drives it to a terminal state via the
  /// DAO. [onProgress] is optional and reports a fractional 0..1
  /// progress value.
  Future<void> upload({
    required String attachmentId,
    required String diveId,
    required File localFile,
    required String mimeType,
    void Function(double progress)? onProgress,
  });

  /// Re-runs the upload for a row that's currently in `failed` (or
  /// stale `pending`). The implementation looks the local file up in
  /// its own pending-uploads cache — Phase C's notifier has no
  /// visibility into that cache. Phase E's impl is the only place
  /// that can satisfy this; there is no sensible fallback here so
  /// the default is left abstract.
  Future<void> retry(FileAttachment row);

  /// Forgets the cached local file for [attachmentId], so nothing
  /// retries it. Used when the add is abandoned (the Worker refused it
  /// for quota and the notifier soft-deleted the row).
  Future<void> discard(String attachmentId);
}

/// What the file picker hands the notifier when the user attaches a
/// file. Wrapping it in a small struct keeps `addFile` from sprouting
/// half a dozen positional args, and gives Phase E a single shape to
/// hand off to the uploader's local cache.
class PickedAttachmentFile {
  final File file;
  final String originalFilename;
  final String mimeType;
  final int sizeBytes;

  const PickedAttachmentFile({
    required this.file,
    required this.originalFilename,
    required this.mimeType,
    required this.sizeBytes,
  });
}
