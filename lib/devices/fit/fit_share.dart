/// Writes one imported FIT dive to a file and opens the share sheet, so a
/// tester can send it to us.
library;

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:fit_reader/fit_reader.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../libdc/download_share.dart' show ShareFileFn;

/// The text that goes with the file. It says plainly what the file holds.
const String kFitShareText =
    "This file is one of your dives, as your watch recorded it. It contains "
    "the dive, the watch's serial number, and any GPS positions and heart "
    'rate it logged. Send it to recordings@anchorline.eu or attach it to an '
    'issue at github.com/Egbertdepauw/anchorline/issues so we can check your '
    'model.';

Future<void> _defaultShare(XFile file, String text, Rect? origin) async {
  await Share.shareXFiles(
    [file],
    subject: 'Anchorline dive',
    text: text,
    // share_plus on iOS rejects a null origin (#232).
    sharePositionOrigin: origin,
  );
}

String _slug(String s) {
  final t = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return t.isEmpty ? 'dive' : t;
}

/// Writes the FIT bytes of dive [diveId] to
/// `<temp>/<vendor>-<product>-<yyyymmdd-HHmm>.fit` and shares the file.
/// [loadRawBlob] returns the stored raw blob (the `ALFT` envelope) of a dive;
/// the file holds the FIT bytes out of it, exactly as the watch wrote them.
///
/// Linux has no share sheet (share_plus throws there), so the file is saved to
/// the user's Downloads folder instead (the temporary directory when there is
/// none) and its path is returned for the screen to show, as
/// `shareDownload` does. Elsewhere the return value is null and the share
/// sheet opens, anchored at [origin] (iOS needs one, #232).
///
/// Throws [StateError] when the dive has no raw blob on this device.
///
/// [now], [tempDir], [downloadsDir], [isLinux] and [share] are test seams.
Future<String?> shareFitDive({
  required String diveId,
  required String vendor,
  String? product,
  required Future<Uint8List?> Function(String diveId) loadRawBlob,
  Rect? origin,
  DateTime Function()? now,
  Future<Directory> Function()? tempDir,
  Future<Directory?> Function()? downloadsDir,
  bool? isLinux,
  ShareFileFn? share,
}) async {
  final blob = await loadRawBlob(diveId);
  if (blob == null) {
    throw StateError('no raw blob for this dive on this device');
  }
  final fit = FitEnvelope.decode(blob).fit;

  final linux = isLinux ?? (!kIsWeb && Platform.isLinux);
  Directory? dir;
  if (linux) {
    try {
      dir = await (downloadsDir ?? getDownloadsDirectory)();
    } catch (_) {
      dir = null;
    }
  }
  dir ??= await (tempDir ?? getTemporaryDirectory)();
  final t = (now ?? DateTime.now)();
  String two(int v) => v.toString().padLeft(2, '0');
  final stamp = '${t.year.toString().padLeft(4, '0')}${two(t.month)}'
      '${two(t.day)}-${two(t.hour)}${two(t.minute)}';
  final name = [
    _slug(vendor),
    if (product != null && product.isNotEmpty) _slug(product),
    stamp,
  ].join('-');
  final path = p.join(dir.path, '$name.fit');
  await File(path).writeAsBytes(fit);
  if (linux) return path;
  await (share ?? _defaultShare)(
    XFile(path, name: '$name.fit', mimeType: 'application/octet-stream'),
    kFitShareText,
    origin,
  );
  return null;
}
