import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/ui/util/dive_computer_labels.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/sync/subsurface_git/subsurface_model.dart';

Dive _dive({
  int serial = 0xB89641E4,
  int model = 3, // ShearwaterModel.petrel3 index
  String? vendor,
  String? product,
  int? family,
  int parserVersion = 1,
}) =>
    Dive(
      id: 'x',
      dcSerial: serial,
      dcDiveNumber: 0,
      startTime: 1700000000,
      endTime: 1700003600,
      durationSeconds: 3600,
      maxDepthMm: 30000,
      diveMode: 5,
      decoModel: 0,
      atmosphericPressureMbar: 1013,
      waterDensity: 1020,
      logVersion: 0,
      dcModel: model,
      dcVendor: vendor,
      dcProduct: product,
      dcFamily: family,
      sampleIntervalMs: 10000,
      gasMixesJson: '[]',
      rawBlob: Uint8List(0),
      parserVersion: parserVersion,
      importedAt: 0,
    );

void main() {
  test('Divesoft Liberty shows as "Divesoft Liberty" with a decimal serial',
      () {
    final d = _dive(
        serial: 1234567,
        model: ShearwaterModel.unknown.index,
        vendor: 'Divesoft',
        product: 'Liberty',
        family: 23 << 16);
    expect(diveComputerName(d), 'Divesoft Liberty');
    expect(diveComputerSerialText(d), '1234567');
  });

  test('a Shearwater dive shows exactly as before', () {
    final d = _dive();
    expect(diveComputerName(d), 'Shearwater Petrel 3');
    expect(diveComputerSerialText(d), 'b89641e4');
    expect(diveComputerBadgeName(d), 'petrel3');
    // A Shearwater dive that carries vendor and product (family null) too.
    final v = _dive(vendor: 'Shearwater', product: 'Petrel 3');
    expect(diveComputerName(v), 'Shearwater Petrel 3');
    expect(diveComputerSerialText(v), 'b89641e4');
  });

  test(
      'a "Perdix 2" copy (vendor Perdix, product 2) shows its serial as 8 hex '
      'digits and the Shearwater name', () {
    final d = _dive(
        model: ShearwaterModel.perdix2.index,
        vendor: 'Perdix',
        product: '2',
        parserVersion: kSubsurfaceImportedParserVersion);
    expect(diveComputerSerialText(d), 'b89641e4');
    expect(diveComputerName(d), 'Shearwater Perdix 2');
    expect(diveComputerBadgeName(d), 'perdix2');
  });

  test('a short Shearwater serial is padded to 8 digits as before', () {
    expect(diveComputerSerialText(_dive(serial: 0x1234)), '00001234');
  });

  test('a non-Shearwater Subsurface copy shows its decimal serial', () {
    final d = _dive(
        serial: 0x1234567,
        model: ShearwaterModel.unknown.index,
        vendor: 'Heinrichs Weikamp',
        product: 'OSTC 4',
        parserVersion: kSubsurfaceImportedParserVersion);
    expect(diveComputerName(d), 'Heinrichs Weikamp OSTC 4');
    expect(diveComputerSerialText(d), '1234567');
  });

  test('an unknown family still shows its stored vendor and product', () {
    final d = _dive(
        serial: 42,
        model: ShearwaterModel.unknown.index,
        vendor: 'Futureco',
        product: 'Z9',
        family: 99 << 16);
    expect(diveComputerName(d), 'Futureco Z9');
    expect(diveComputerBadgeName(d), 'Futureco Z9');
    expect(diveComputerSerialText(d), '42');
  });

  test('a Garmin FIT dive (family -1) shows vendor and product', () {
    final d = _dive(
        serial: 3456789012,
        model: ShearwaterModel.unknown.index,
        vendor: 'Garmin',
        product: 'Descent Mk3',
        family: -1);
    expect(diveComputerName(d), 'Garmin Descent Mk3');
    expect(diveComputerSerialText(d), '3456789012');
  });

  test('a libdivecomputer dive missing its product falls back to the vendor',
      () {
    final d = _dive(
        model: ShearwaterModel.unknown.index, vendor: 'Divesoft', family: 23 << 16);
    expect(diveComputerName(d), 'Divesoft');
  });
}
