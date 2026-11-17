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

  test('a dive without a fingerprint takes its id from its bytes', () {
    final a = Uint8List.fromList([1, 2, 3]);
    final b = Uint8List.fromList([1, 2, 4]);
    String id(Uint8List data) => libdcDiveId(
      vendor: 'Ratio',
      serial: 77,
      fingerprint: Uint8List(0),
      data: data,
    );
    final expected = sha256
        .convert(utf8.encode('libdc:Ratio:77:${sha256.convert(a)}'))
        .toString()
        .substring(0, 32);
    expect(id(a), expected);
    expect(id(a), isNot(id(b)), reason: 'two such dives, two ids');
    // With a fingerprint the bytes play no part.
    final fingerprint = Uint8List.fromList([9, 9]);
    expect(
      libdcDiveId(vendor: 'Ratio', serial: 77, fingerprint: fingerprint, data: a),
      libdcDiveId(vendor: 'Ratio', serial: 77, fingerprint: fingerprint),
    );
    expect(
      () => libdcDiveId(vendor: 'Ratio', serial: 77, fingerprint: Uint8List(0)),
      throwsArgumentError,
    );
  });

  test('fingerprintHex is lower case and zero padded', () {
    expect(
      fingerprintHex(Uint8List.fromList([0x00, 0x0a, 0xFF])),
      '000aff',
    );
    expect(fingerprintHex(Uint8List(0)), '');
  });
}
