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
///
/// A dive with an empty fingerprint would share its id with every other
/// such dive of the computer. For those, the lower-case hex of
/// `sha256(data)` (the dive's bytes) stands in for the fingerprint, in the
/// id only. [data] is needed exactly then.
String libdcDiveId({
  required String vendor,
  required int serial,
  required Uint8List fingerprint,
  Uint8List? data,
}) {
  final String key;
  if (fingerprint.isNotEmpty) {
    key = fingerprintHex(fingerprint);
  } else if (data != null) {
    key = sha256.convert(data).toString();
  } else {
    throw ArgumentError.value(
      data,
      'data',
      'needed for a dive without a fingerprint',
    );
  }
  final input = 'libdc:$vendor:$serial:$key';
  return sha256.convert(utf8.encode(input)).toString().substring(0, 32);
}
