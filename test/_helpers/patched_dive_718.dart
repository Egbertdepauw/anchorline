import 'dart:io';
import 'dart:typed_data';

import 'package:subsurface_core/shearwater/parser/constants.dart';

/// dive_718 with two of its sample records turned into tag-log (bookmark)
/// events, since none of the fixtures has one. The first (sample 9) has bearing
/// 270 and value 7, the second (sample 19) no bearing (0xFFFFFFFF) and value 8.
Uint8List patchedDive718() {
  final data = Uint8List.fromList(
      File('test/fixtures/dives/dive_718.bin').readAsBytesSync());
  final view = ByteData.sublistView(data);
  final sampleOffsets = [
    for (var o = 0; o + 32 <= data.length; o += 32)
      if (data[o] == logRecordDiveSample) o
  ];
  final withBearing = sampleOffsets[9];
  final noBearing = sampleOffsets[19];
  for (final o in [withBearing, noBearing]) {
    data[o] = logRecordInfoEvent;
    data[o + 1] = infoEventTagLog;
  }
  view.setUint32(withBearing + 8, 270);
  view.setUint32(withBearing + 12, 7);
  view.setUint32(noBearing + 8, 0xFFFFFFFF);
  view.setUint32(noBearing + 12, 8);
  return data;
}
