import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:test/test.dart';

void main() {
  group('modelFromNumber', () {
    test('maps libdivecomputer model numbers', () {
      const expected = {
        2: ShearwaterModel.predator,
        4: ShearwaterModel.nerd,
        5: ShearwaterModel.perdix,
        6: ShearwaterModel.perdixAi,
        7: ShearwaterModel.nerd2,
        8: ShearwaterModel.teric,
        9: ShearwaterModel.peregrine,
        10: ShearwaterModel.petrel3,
        11: ShearwaterModel.perdix2,
        12: ShearwaterModel.tern,
        13: ShearwaterModel.peregrineTx,
      };
      for (final MapEntry(key: number, value: model) in expected.entries) {
        expect(modelFromNumber(number, hardwareId: 0), model,
            reason: 'model number $number');
      }
    });

    test('number 3 is a Petrel or Petrel 2, by hardware ID', () {
      expect(modelFromNumber(3, hardwareId: 0x0404), ShearwaterModel.petrel);
      expect(modelFromNumber(3, hardwareId: 0x0909), ShearwaterModel.petrel);
      expect(modelFromNumber(3, hardwareId: 0x0505), ShearwaterModel.petrel2);
      // A hardware ID the table doesn't know.
      expect(modelFromNumber(3, hardwareId: 0x1234), ShearwaterModel.petrel2);
    });

    test('ignores the hardware ID for other numbers', () {
      // 0xB407 is a Petrel 3 in the hardware ID table.
      expect(modelFromNumber(11, hardwareId: 0xB407), ShearwaterModel.perdix2);
    });

    test('unsupported and unknown numbers give unknown', () {
      expect(modelFromNumber(14, hardwareId: 0), ShearwaterModel.unknown);
      expect(modelFromNumber(0, hardwareId: 0), ShearwaterModel.unknown);
      expect(modelFromNumber(255, hardwareId: 0xB407), ShearwaterModel.unknown);
    });
  });
}
