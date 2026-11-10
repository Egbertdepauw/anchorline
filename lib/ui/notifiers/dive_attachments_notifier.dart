/// Per-dive view-model for the attachments list (files + links).
///
/// Owns no state of its own beyond the current dive id and the last
/// fetched list — the canonical store is PowerSync via
/// [DiveAttachmentsDao]. Mirrors [DiveAnnotationsNotifier]'s shape:
/// `load(diveId)` populates, mutators commit through the DAO and then
/// `reload()` to re-pull, listeners get notified once per externally-
/// visible state change.
///
/// File uploads are kicked off here but executed by an injected
/// [AttachmentUploader] (Phase E). The notifier inserts the DAO row
/// in `pending` immediately, awaits the uploader, then reloads — the
/// row's terminal state (`uploaded` or `failed`) was flipped by the
/// uploader via the DAO before the future resolved.
///
/// Worker refusals (issue #196) get their own state instead of the
/// generic [DiveAttachmentsNotifier.error]: a quota refusal sets
/// [DiveAttachmentsNotifier.storageFull] (the widgets show the storage-
/// full dialog for it) and an uploads-disabled one sets
/// [DiveAttachmentsNotifier.uploadsPaused].
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';

import '../../data/db/dive_attachments_dao.dart';
import '../../data/models/dive_attachment.dart';
import '../../sync/attachments/attachment_purger.dart';
import '../../sync/attachments/attachment_signer.dart';
import '../../sync/attachments/attachment_uploader.dart';
import '../../sync/attachments/attachment_uploader_impl.dart'
    show UploadFailedException;

/// Tiny seam over UUID generation so tests can pin row ids. Production
/// uses [UuidV4IdGenerator]; tests inject a deterministic counter.
abstract class IdGenerator {
  String next();
}

/// RFC-4122 v4 UUID, hand-rolled on top of [math.Random.secure] to
/// avoid pulling `package:uuid` in for fifteen lines of code. Not
/// crypto-grade randomness, but it doesn't have to be — collisions
/// across our row space are statistically impossible.
class UuidV4IdGenerator implements IdGenerator {
  const UuidV4IdGenerator();

  @override
  String next() {
    final r = math.Random.secure();
    final bytes = List<int>.generate(16, (_) => r.nextInt(256));
    // Set version (4) and variant (10xx) per RFC 4122 §4.4.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
    final b = StringBuffer();
    for (var i = 0; i < 16; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) b.write('-');
      b.write(hex(i));
    }
    return b.toString();
  }
}

/// A quota refusal waiting for the storage-full dialog. A new instance
/// per refusal, so a widget can tell a fresh refusal from a rebuild.
class StorageFullState {
  final AttachmentUsage usage;

  /// Size of the file the Worker refused.
  final int fileSizeBytes;

  /// Whether "Free space now" has anything to purge.
  final bool canFreeSpace;

  /// Files of the same multi-file add that came after the refused one
  /// and weren't added. "Free space now" adds them after the refused
  /// file; "OK" drops them.
  final int remainingFiles;

  const StorageFullState({
    required this.usage,
    required this.fileSizeBytes,
    required this.canFreeSpace,
    this.remainingFiles = 0,
  });
}

class DiveAttachmentsNotifier extends ChangeNotifier {
  final DiveAttachmentsDao _dao;
  final AttachmentUploader _uploader;
  final IdGenerator _idGenerator;

  /// Frees space for "Free space now". Without one, the dialog never
  /// offers it.
  final AttachmentPurger? _purger;

  DiveAttachmentsNotifier(
    this._dao,
    this._uploader, {
    IdGenerator? idGenerator,
    AttachmentPurger? purger,
  })  : _idGenerator = idGenerator ?? const UuidV4IdGenerator(),
        _purger = purger;

  String? _diveId;
  List<DiveAttachment> _attachments = const [];
  bool _loading = false;
  String? _error;
  bool _disposed = false;
  StreamSubscription<void>? _watchSub;

  StorageFullState? _storageFull;
  bool _uploadsPaused = false;

  /// What "Free space now" retries: the refused pick (an add) or the
  /// refused row id (a manual retry). Exactly one is set while
  /// [_storageFull] is.
  PickedAttachmentFile? _refusedPick;
  String? _refusedRowId;

  /// The picks of a multi-file add after [_refusedPick], not added yet.
  List<PickedAttachmentFile> _refusedRemaining = const [];

  /// Failed rows whose last failure was a quota refusal. Session only.
  final Set<String> _storageFullIds = {};

  // ── Read accessors ────────────────────────────────────────────────────

  List<DiveAttachment> get attachments => List.unmodifiable(_attachments);
  bool get loading => _loading;
  String? get error => _error;
  bool get loaded => _diveId != null && !_loading;
  String? get diveId => _diveId;

  /// Set by a quota refusal until [dismissStorageFull] or
  /// [freeSpaceAndRetry].
  StorageFullState? get storageFull => _storageFull;

  /// Set when the Worker has uploads switched off, until
  /// [dismissUploadsPaused] or the next upload or retry that the Worker
  /// doesn't refuse that way.
  bool get uploadsPaused => _uploadsPaused;

  /// Whether [id] is a failed row the Worker refused for quota.
  bool isStorageFull(String id) => _storageFullIds.contains(id);

  // ── Lifecycle ─────────────────────────────────────────────────────────

  Future<void> load(String diveId) async {
    _diveId = diveId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _attachments = await _dao.listForDive(diveId);
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
    // Subscribe to local table changes so PowerSync syncs from another
    // device land in the UI without a manual reload. Skip the initial
    // emit (current state) since the explicit listForDive above already
    // covered it. Cancel any prior subscription first — load() may be
    // called more than once if the same notifier is reused for a
    // different dive (it isn't today, but be defensive).
    //
    // The catch is for tests where the database connection pool gets
    // closed (tearDown) while a watch event is still in flight: the
    // reload would throw "connection pool is closed" otherwise. A
    // closed-DB live-update is meaningless anyway — swallow it.
    await _watchSub?.cancel();
    _watchSub = _dao.watchChanges().skip(1).listen(
      (_) async {
        if (_disposed || _diveId != diveId) return;
        try {
          await reload();
        } catch (_) {
          // Best-effort: live-update failures don't block the user.
        }
      },
      // Stream-level errors (e.g. test teardown closing the DB while a
      // watch event is in flight) shouldn't propagate as uncaught.
      onError: (Object _) {},
    );
  }

  /// Re-runs the listForDive query for the current [_diveId]. Used
  /// after every mutator and by widgets reacting to
  /// [DiveAttachmentsDao.watchChanges].
  Future<void> reload() async {
    final diveId = _diveId;
    if (_disposed || diveId == null) return;
    try {
      _attachments = await _dao.listForDive(diveId);
      _error = null;
    } catch (e) {
      _error = e.toString();
    }
    notifyListeners();
  }

  // ── Mutators ──────────────────────────────────────────────────────────

  Future<void> addLink({
    required String url,
    String? title,
    String? description,
  }) async {
    final diveId = _requireDiveId('addLink');
    final now = DateTime.now();
    final link = LinkAttachment(
      id: _idGenerator.next(),
      parentKind: DiveAttachmentParentKind.dive,
      parentId: diveId,
      title: title,
      description: description,
      displayOrder: _nextDisplayOrder(),
      url: url,
      createdAt: now,
      updatedAt: now,
      version: 1,
    );
    await _dao.insertLink(link);
    await reload();
  }

  /// Inserts a `pending` file row immediately so the UI can show it,
  /// then drives the upload through the injected [AttachmentUploader].
  /// The uploader is responsible for flipping the row to `uploaded` or
  /// `failed` via the DAO; this method awaits that work and reloads
  /// once when it's done so the UI sees the terminal state in one
  /// notify rather than two.
  Future<void> addFile(PickedAttachmentFile picked) async {
    await _addFile(picked);
  }

  /// Adds [picks] one after another. Sequential: a parallel burst would
  /// race the display_order computation. A quota refusal stops the
  /// batch; the refused pick and the ones after it are kept with
  /// [storageFull], so "Free space now" can add them all.
  Future<void> addFiles(List<PickedAttachmentFile> picks) async {
    for (var i = 0; i < picks.length; i++) {
      final refused =
          await _addFile(picks[i], remaining: picks.sublist(i + 1));
      if (refused) break;
    }
  }

  /// Returns whether the Worker refused [picked] for quota and
  /// [storageFull] now holds it (and [remaining]).
  Future<bool> _addFile(
    PickedAttachmentFile picked, {
    List<PickedAttachmentFile> remaining = const [],
  }) async {
    final diveId = _requireDiveId('addFile');
    final id = _idGenerator.next();
    final now = DateTime.now();
    final row = FileAttachment(
      id: id,
      parentKind: DiveAttachmentParentKind.dive,
      parentId: diveId,
      title: null,
      description: null,
      displayOrder: _nextDisplayOrder(),
      // Sentinel — the DAO's CHECK constraint forbids null. The
      // uploader rewrites this to the canonical R2 key via
      // DAO.markUploaded once the Worker confirms.
      storageKey: 'pending:$id',
      mimeType: picked.mimeType,
      sizeBytes: picked.sizeBytes,
      originalFilename: picked.originalFilename,
      uploadState: UploadState.pending,
      uploadAttempts: 0,
      createdAt: now,
      updatedAt: now,
      version: 1,
    );
    await _dao.insertFile(row);
    // Surface the pending row to the UI before we go off and upload.
    await reload();

    Object? uploadError;
    try {
      await _uploader.upload(
        attachmentId: id,
        diveId: diveId,
        localFile: picked.file,
        mimeType: picked.mimeType,
      );
    } catch (e) {
      uploadError = e;
    }
    final cause = _causeOf(uploadError);
    var refused = false;
    if (cause is AttachmentQuotaExceededException) {
      if (_disposed) {
        // Nobody is left to show the dialog. Keep the row `failed` so
        // the diver sees "Upload failed" next time instead of the file
        // silently vanishing.
        return false;
      }
      // The file isn't added: drop the row and its cached bytes so
      // nothing is stuck in `failed` or retried later.
      await _dao.softDelete(id);
      await _uploader.discard(id);
      await _setStorageFull(cause.usage, picked.sizeBytes,
          pick: picked, remaining: remaining);
      refused = true;
    } else {
      _uploadsPaused = cause is AttachmentUploadsDisabledException;
    }
    // The uploader has already flipped the row state via the DAO; we
    // just re-pull so the UI sees `uploaded` or `failed`.
    await reload();
    if (uploadError != null && _isGenericFailure(cause)) {
      _error = uploadError.toString();
      notifyListeners();
    }
    return refused;
  }

  Future<void> updateMetadata(
    String id, {
    String? title,
    String? description,
    String? url,
  }) async {
    await _dao.updateMetadata(
      id,
      title: title == null ? null : Value(title),
      description: description == null ? null : Value(description),
      url: url == null ? null : Value(url),
    );
    await reload();
  }

  /// Reorders [_attachments] by moving the row at [oldIndex] to
  /// [newIndex] and rewriting every row's `display_order` to its new
  /// position. The DAO doesn't expose batch updates yet — N round-
  /// trips is fine for the v1 attachments-per-dive count, which is
  /// dominated by single-digit cases.
  Future<void> reorder(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _attachments.length) return;
    if (newIndex < 0 || newIndex > _attachments.length) return;
    if (oldIndex == newIndex) return;

    final reordered = List<DiveAttachment>.of(_attachments);
    final moved = reordered.removeAt(oldIndex);
    // ReorderableListView.onReorderItem already adjusts newIndex for the
    // removed row, so it is the final post-removal insert position — no
    // pre-removal shift needed. Clamp defensively against stray callers.
    reordered.insert(newIndex.clamp(0, reordered.length), moved);

    for (var i = 0; i < reordered.length; i++) {
      final row = reordered[i];
      if (row.displayOrder == i) continue;
      await _dao.updateMetadata(row.id, displayOrder: i);
    }
    await reload();
  }

  Future<void> softDelete(String id) async {
    _storageFullIds.remove(id);
    await _dao.softDelete(id);
    await reload();
  }

  Future<void> restore(String id) async {
    await _dao.restore(id);
    await reload();
  }

  /// Re-kicks the uploader for an existing file row. The uploader
  /// reads the local file from its own pending-uploads cache — the
  /// notifier never sees the bytes on retry.
  Future<void> retryUpload(String id) async {
    final row = await _dao.get(id);
    if (row is! FileAttachment) return;
    Object? err;
    try {
      await _uploader.retry(row);
    } catch (e) {
      err = e;
    }
    final cause = _causeOf(err);
    if (cause is AttachmentQuotaExceededException) {
      // Unlike an add, the row stays `failed` so the user can retry it.
      _storageFullIds.add(id);
      await _setStorageFull(cause.usage, row.sizeBytes ?? 0, rowId: id);
    } else {
      // Only a quota refusal keeps the label; any other outcome,
      // including another kind of failure, replaces it.
      _storageFullIds.remove(id);
      _uploadsPaused = cause is AttachmentUploadsDisabledException;
    }
    await reload();
    if (err != null && _isGenericFailure(cause)) {
      _error = err.toString();
      notifyListeners();
    }
  }

  /// "Free space now": purges every soft-deleted attachment, then
  /// retries the refused add or row once. For a refused multi-file add
  /// the files after it are added too, in order, until one is refused
  /// again. Another refusal sets [storageFull] again; it never retries
  /// further by itself.
  Future<void> freeSpaceAndRetry() async {
    final pick = _refusedPick;
    final remaining = _refusedRemaining;
    final rowId = _refusedRowId;
    _clearStorageFull();
    notifyListeners();
    final purger = _purger;
    if (purger != null) {
      try {
        await purger.purgeDeleted(minAge: Duration.zero);
      } catch (e) {
        // Retry anyway: whatever the purge did free still counts.
        debugPrint('Attachment purge for free space failed: $e');
      }
    }
    if (pick != null) {
      await addFiles([pick, ...remaining]);
    } else if (rowId != null) {
      await retryUpload(rowId);
    }
  }

  /// Closes the storage-full dialog without retrying. The files of a
  /// multi-file add that weren't added are dropped.
  void dismissStorageFull() {
    if (_storageFull == null) return;
    _clearStorageFull();
    notifyListeners();
  }

  /// Hides the uploads-paused message.
  void dismissUploadsPaused() {
    if (!_uploadsPaused) return;
    _uploadsPaused = false;
    notifyListeners();
  }

  // ── Helpers ───────────────────────────────────────────────────────────

  /// The uploader wraps every failure in [UploadFailedException]; the
  /// refusals we handle specially are its cause.
  Object? _causeOf(Object? error) =>
      error is UploadFailedException ? error.cause : error;

  /// Quota and uploads-disabled refusals have their own state; every
  /// other failure shows the generic [error].
  bool _isGenericFailure(Object? cause) =>
      cause is! AttachmentQuotaExceededException &&
      cause is! AttachmentUploadsDisabledException;

  Future<void> _setStorageFull(
    AttachmentUsage usage,
    int fileSizeBytes, {
    PickedAttachmentFile? pick,
    List<PickedAttachmentFile> remaining = const [],
    String? rowId,
  }) async {
    final purger = _purger;
    var canFreeSpace = false;
    if (purger != null) {
      try {
        canFreeSpace = await purger.hasPurgeable();
      } catch (_) {
        // Can't tell: leave the button out rather than offer a no-op.
      }
    }
    _storageFull = StorageFullState(
      usage: usage,
      fileSizeBytes: fileSizeBytes,
      canFreeSpace: canFreeSpace,
      remainingFiles: remaining.length,
    );
    _refusedPick = pick;
    _refusedRemaining = remaining;
    _refusedRowId = rowId;
  }

  void _clearStorageFull() {
    _storageFull = null;
    _refusedPick = null;
    _refusedRemaining = const [];
    _refusedRowId = null;
  }

  String _requireDiveId(String op) {
    final id = _diveId;
    if (id == null) {
      throw StateError('DiveAttachmentsNotifier.$op called before load()');
    }
    return id;
  }

  int _nextDisplayOrder() {
    if (_attachments.isEmpty) return 0;
    return _attachments
            .map((a) => a.displayOrder)
            .fold<int>(0, (a, b) => a > b ? a : b) +
        1;
  }

  /// An upload can finish after the screen is gone; its notify then
  /// has nobody to tell.
  @override
  void notifyListeners() {
    if (_disposed) return;
    super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _watchSub?.cancel();
    super.dispose();
  }
}
