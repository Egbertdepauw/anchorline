import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Lower-case hex of a fingerprint, the form every libdivecomputer dive id
/// and the stored `dc_fingerprint` use.
String fingerprintHex(Uint8List fingerprint) {
  final out = StringBuffer();
  for (final b in fingerprint) {
    out.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return out.toString();
}

/// `sha256('libdc:<vendor>:<decimal serial>:<fingerprint hex>')` cut to 32
/// hex characters, the same form as `generateDiveId`. The id is frozen at
/// first import; nothing recomputes it.
String libdcDiveId({
  required String vendor,
  required int serial,
  required Uint8List fingerprint,
}) {
  final input = 'libdc:$vendor:$serial:${fingerprintHex(fingerprint)}';
  return sha256.convert(utf8.encode(input)).toString().substring(0, 32);
}
