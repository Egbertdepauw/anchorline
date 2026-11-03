import 'package:subsurface_core/shearwater/parser/dive_converter.dart';
import 'package:ccrlogger/shearwater/parser/dive_parser.dart';
import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:flutter_test/flutter_test.dart';

import 'dive_parser_test.dart' show loadFixture;

void main() {
  late ConvertedDive converted;

  setUpAll(() {
    final data = loadFixture('dive_718.bin');
    final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
    final parsed = parser.parse(data);
    converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: 718,
      dcModel: ShearwaterModel.petrel3,
    );
  });

  group('Cell mV raw values (JJ-CCR DiveCAN, calMask=0)', () {
    test('sample 0 has the expected raw mV bytes', () {
      final s = converted.samples;
      expect(s.cellMv0[0], equals(32.0));
      expect(s.cellMv1[0], equals(37.0));
      expect(s.cellMv2[0], equals(36.0));
    });

    test('cell0 max across all samples lands in healthy-cell range', () {
      final cell0 = converted.samples.cellMv0;
      var maxMv = 0.0;
      for (var i = 0; i < cell0.length; i++) {
        if (cell0[i] > maxMv) maxMv = cell0[i];
      }
      expect(maxMv, greaterThan(60));
      expect(maxMv, lessThan(80));
    });

    test('every sample has cellMv0 > 0 (full coverage on this CCR dive)', () {
      final cell0 = converted.samples.cellMv0;
      expect(cell0.length, equals(699));
      for (var i = 0; i < cell0.length; i++) {
        expect(cell0[i], greaterThan(0),
            reason: 'cellMv0 zero at sample $i');
      }
    });

    test('calibration factors are preserved on Dive header', () {
      final cal = converted.dive.sensorCalibration;
      expect(cal.length, equals(3));
      for (final c in cal) {
        expect(c, greaterThan(0.0));
        expect(c, lessThan(1.0));
      }
    });
  });
}
