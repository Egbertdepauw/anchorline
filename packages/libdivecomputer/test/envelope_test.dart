import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:test/test.dart';

LibdcEnvelope _env({
  int? model,
  int? firmware,
  int? serial,
  int? devtime,
  int? systime,
}) => LibdcEnvelope(
  pinnedCommit: '0194f09',
  vendor: 'Divesoft',
  product: 'Liberty',
  family: 0x130000,
  descriptorModel: 10,
  devinfoModel: model,
  devinfoFirmware: firmware,
  devinfoSerial: serial,
  devtime: devtime,
  systime: systime,
  fingerprint: Uint8List.fromList([0xde, 0xad, 0xbe, 0xef]),
  data: Uint8List.fromList([1, 2, 3]),
);

void _expectSame(LibdcEnvelope a, LibdcEnvelope b) {
  expect(a.pinnedCommit, b.pinnedCommit);
  expect(a.vendor, b.vendor);
  expect(a.product, b.product);
  expect(a.family, b.family);
  expect(a.descriptorModel, b.descriptorModel);
  expect(a.devinfoModel, b.devinfoModel);
  expect(a.devinfoFirmware, b.devinfoFirmware);
  expect(a.devinfoSerial, b.devinfoSerial);
  expect(a.devtime, b.devtime);
  expect(a.systime, b.systime);
  expect(a.fingerprint, b.fingerprint);
  expect(a.data, b.data);
}

void main() {
  test('round-trips every field, with and without device info and clock', () {
    for (final e in [
      _env(),
      _env(model: 0x43, firmware: 0x01020304, serial: 0xFFFFFFFF),
      _env(devtime: 123456, systime: 1780000000),
      _env(
        model: 1,
        firmware: 2,
        serial: 3,
        devtime: 0xFFFFFFFF,
        systime: -5,
      ),
    ]) {
      _expectSame(LibdcEnvelope.decode(e.encode()), e);
    }
  });

  test('absent values stay null when decoding', () {
    final d = LibdcEnvelope.decode(_env().encode());
    expect(d.devinfoSerial, isNull);
    expect(d.devtime, isNull);
  });

  test('golden bytes for one envelope', () {
    final bytes = _env(
      model: 0x43,
      firmware: 0x0102,
      serial: 1234567,
      devtime: 0x10,
      systime: 0x0102030405,
    ).encode();
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(
      hex,
      '414c4443' // ALDC
      '01' // version
      '073031393466303' '9' // 7 "0194f09"
      '08446976657' '36f6674' // 8 "Divesoft"
      '074c696265727479' // 7 "Liberty"
      '00130000' // family
      '0000000a' // descriptor model
      '03' // flags
      '00000043' // devinfo model
      '00000102' // firmware
      '0012d687' // serial
      '00000010' // devtime
      '0000000102030405' // systime
      '0004deadbeef' // fingerprint
      '00000003010203', // data
    );
  });

  test('a bad magic, version 2 or truncated input throws FormatException', () {
    final good = _env().encode();
    final badMagic = Uint8List.fromList(good)..[0] = 0x42;
    expect(() => LibdcEnvelope.decode(badMagic), throwsFormatException);
    final v2 = Uint8List.fromList(good)..[4] = 2;
    expect(() => LibdcEnvelope.decode(v2), throwsFormatException);
    expect(
      () => LibdcEnvelope.decode(good.sublist(0, good.length - 1)),
      throwsFormatException,
    );
    expect(
      () => LibdcEnvelope.decode(Uint8List.fromList([0x41, 0x4c])),
      throwsFormatException,
    );
    expect(() => LibdcEnvelope.decode(Uint8List(0)), throwsFormatException);
  });
}
