/// Writes a libdivecomputer download recording to a file and opens the share
/// sheet, so a tester can send it to us.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Files above this size are gzipped before sharing.
const int kShareGzipAboveBytes = 10 * 1024 * 1024;

/// The text that goes with the file. It says plainly what the file holds.
const String kDownloadShareText =
    "This file is a recording of your dive computer's download. It contains "
    'the dives on the computer, its serial number and any GPS positions it '
    'logged. Send it to recordings@anchorline.eu or attach it to an issue at '
    'github.com/Egbertdepauw/anchorline/issues so we can check your '
    'computer.';

/// Opens the share sheet for [file] with [text]. [origin] anchors the iPad
/// and macOS popover.
typedef ShareFileFn = Future<void> Function(
    XFile file, String text, Rect? origin);

Future<void> _defaultShare(XFile file, String text, Rect? origin) async {
  await Share.shareXFiles(
    [file],
    subject: 'Anchorline dive computer download',
    text: text,
    // share_plus on iOS rejects a null origin (#232).
    sharePositionOrigin: origin,
  );
}

/// Writes `anchorline-download-<yyyymmdd-HHmmss>.txt` to the temporary
/// directory and shares it. The file is the header ([extraHeader], one entry
/// per line) followed by [recordingText]. Above [gzipAboveBytes] the file is
/// gzipped to `.txt.gz` instead.
///
/// [now], [tempDir], [share] and [gzipAboveBytes] are test seams.
Future<void> shareDownload({
  required String recordingText,
  required List<String> extraHeader,
  Rect? origin,
  DateTime Function()? now,
  Future<Directory> Function()? tempDir,
  ShareFileFn? share,
  int gzipAboveBytes = kShareGzipAboveBytes,
}) async {
  final dir = await (tempDir ?? getTemporaryDirectory)();
  final stamp = _stamp((now ?? DateTime.now)());
  final name = 'anchorline-download-$stamp.txt';
  final text = StringBuffer('Anchorline dive computer download\n');
  for (final line in extraHeader) {
    text.writeln(line);
  }
  text
    ..writeln()
    ..write(recordingText);

  // Decide from the encoded size before writing, so only one file is made.
  final bytes = utf8.encode(text.toString());
  var shareName = name;
  var mimeType = 'text/plain';
  List<int> payload = bytes;
  if (bytes.length > gzipAboveBytes) {
    shareName = '$name.gz';
    payload = gzip.encode(bytes);
    mimeType = 'application/gzip';
  }
  final sharePath = p.join(dir.path, shareName);
  await File(sharePath).writeAsBytes(payload);
  await (share ?? _defaultShare)(
    XFile(sharePath, name: shareName, mimeType: mimeType),
    kDownloadShareText,
    origin,
  );
}

String _stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}'
      '-${two(t.hour)}${two(t.minute)}${two(t.second)}';
}
