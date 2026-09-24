/// Picker helper that wraps `image_picker` (camera + library) and
/// `file_picker` (arbitrary files) behind a single entry point. The
/// dive-attachments UI doesn't care which sub-picker the user ended up
/// in — it just wants `List<PickedAttachmentFile>` back.
///
/// Files larger than [maxFileSizeBytes] are filtered out and surfaced
/// to the user via a SnackBar; we'd rather drop a too-big file than
/// let it land in a `pending` row that the uploader will refuse later.
/// The 25 MB ceiling matches the Worker's accept-list (see
/// `attachments` Worker for the canonical constant).
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mime/mime.dart' as mime;
import 'package:path/path.dart' as p;

import '../../sync/attachments/attachment_uploader.dart';

/// 25 MB hard ceiling. Mirrors the Worker upload limit; see
/// `supabase/migrations/0004_dive_attachments.sql` rationale.
const int maxFileSizeBytes = 25 * 1024 * 1024;

/// Shows the picker chooser and returns whatever files the user
/// successfully picked. Returns `null` if the user dismissed the
/// chooser without picking anything; returns an empty list if every
/// pick was filtered out (e.g. all oversize). Callers should treat
/// null and `[]` the same in practice.
///
/// Oversize files are reported via a SnackBar on [context]'s nearest
/// [ScaffoldMessenger]; the result list contains only files that
/// passed the size check.
Future<List<PickedAttachmentFile>?> pickAttachments(BuildContext context) async {
  final source = await showModalBottomSheet<_PickSource>(
    context: context,
    builder: (ctx) => const _PickSourceSheet(),
  );
  if (source == null) return null;
  if (!context.mounted) return null;

  final messenger = ScaffoldMessenger.of(context);
  final picker = ImagePicker();
  final List<PickedAttachmentFile> picked = [];
  final List<String> oversize = [];

  switch (source) {
    case _PickSource.camera:
      final shot = await picker.pickImage(source: ImageSource.camera);
      if (shot == null) return null;
      _addIfFits(File(shot.path), picked, oversize, originalName: shot.name);
    case _PickSource.gallery:
      final shots = await picker.pickMultiImage();
      if (shots.isEmpty) return null;
      for (final s in shots) {
        _addIfFits(File(s.path), picked, oversize, originalName: s.name);
      }
    case _PickSource.file:
      final result = await FilePicker.pickFiles(allowMultiple: true);
      if (result == null) return null;
      for (final f in result.files) {
        final path = f.path;
        if (path == null) continue;
        _addIfFits(File(path), picked, oversize, originalName: f.name);
      }
  }

  if (oversize.isNotEmpty) {
    final names = oversize.length == 1
        ? oversize.single
        : '${oversize.length} files';
    messenger.showSnackBar(SnackBar(
      content: Text('Skipped $names — exceeds 25 MB limit'),
      duration: const Duration(seconds: 4),
    ));
  }

  return picked;
}

void _addIfFits(
  File file,
  List<PickedAttachmentFile> out,
  List<String> oversize, {
  required String originalName,
}) {
  int size;
  try {
    size = file.lengthSync();
  } catch (_) {
    // If we can't even stat it, treat it as "drop and warn".
    oversize.add(originalName);
    return;
  }
  if (size > maxFileSizeBytes) {
    oversize.add(originalName);
    return;
  }
  out.add(PickedAttachmentFile(
    file: file,
    originalFilename: originalName,
    mimeType: _mimeFor(file.path, originalName),
    sizeBytes: size,
  ));
}

/// Best-effort MIME lookup. `package:mime` peeks at a file's magic
/// bytes when given a path, otherwise falls back to the extension.
/// We keep both candidates and prefer whichever the package returns.
String _mimeFor(String path, String originalName) {
  // Prefer the magic-bytes sniff; fall back to extension-only on the
  // declared filename (which may differ from the path on some pickers).
  final byPath = mime.lookupMimeType(path);
  if (byPath != null) return byPath;
  final byExt = mime.lookupMimeType(p.basename(originalName));
  if (byExt != null) return byExt;
  return 'application/octet-stream';
}

enum _PickSource { camera, gallery, file }

/// `image_picker` only supports `ImageSource.camera` on iOS, Android,
/// and the Web — macOS, Linux, and Windows have no camera backend.
/// Hiding the option on those platforms is cleaner than letting the
/// tap silently no-op.
bool get _platformSupportsCamera {
  if (kIsWeb) return true;
  return defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.android;
}

class _PickSourceSheet extends StatelessWidget {
  const _PickSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_platformSupportsCamera)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take photo'),
              onTap: () => Navigator.of(context).pop(_PickSource.camera),
            ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Pick from library'),
            onTap: () => Navigator.of(context).pop(_PickSource.gallery),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file),
            title: const Text('Pick file'),
            onTap: () => Navigator.of(context).pop(_PickSource.file),
          ),
        ],
      ),
    );
  }
}
