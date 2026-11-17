import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:test/test.dart';

void main() {
  test('libdcDiveId hashes "libdc:<vendor>:<decimal serial>:<lower hex>" '
      'and keeps 32 hex', () {
    final id = libdcDiveId(
      vendor: 'Divesoft',
      serial: 1234567,
      fingerprint: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
    );
    final expected = sha256
        .convert(utf8.encode('libdc:Divesoft:1234567:deadbeef'))
        .toString()
        .substring(0, 32);
    expect(id, expected);
    expect(id, hasLength(32));
    expect(id, matches(RegExp(r'^[0-9a-f]{32}$')));
  });

  test('fingerprintHex is lower case and zero padded', () {
    expect(
      fingerprintHex(Uint8List.fromList([0x00, 0x0a, 0xFF])),
      '000aff',
    );
    expect(fingerprintHex(Uint8List(0)), '');
  });
}
