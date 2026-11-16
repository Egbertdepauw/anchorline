import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:subsurface_core/sync/subsurface_git/subsurface_model.dart';
import 'package:test/test.dart';

void main() {
  test('"Shearwater Petrel 3" splits to Shearwater / Petrel 3', () {
    final s = splitSubsurfaceModel('Shearwater Petrel 3');
    expect(s!.vendor, 'Shearwater');
    expect(s.product, 'Petrel 3');
  });

  test('"Heinrichs Weikamp OSTC 4" splits to Heinrichs Weikamp / OSTC 4', () {
    final s = splitSubsurfaceModel('Heinrichs Weikamp OSTC 4');
    expect(s!.vendor, 'Heinrichs Weikamp');
    expect(s.product, 'OSTC 4');
  });

  test('"manually added dive" and a model without a space give null', () {
    expect(splitSubsurfaceModel('manually added dive'), isNull);
    expect(splitSubsurfaceModel('Petrel'), isNull);
    expect(splitSubsurfaceModel(''), isNull);
  });

  test('Shearwater serial "B89641E4" parses as hex', () {
    expect(parseSubsurfaceSerial('Shearwater', 'B89641E4'), 0xB89641E4);
    expect(parseSubsurfaceSerial(null, 'b89641e4'), 0xB89641E4);
  });

  test('Divesoft serial "1234567" parses as decimal', () {
    expect(parseSubsurfaceSerial('Divesoft', '1234567'), 1234567);
  });

  test('a non-Shearwater serial that is not decimal falls back to hex, '
      'then 0', () {
    expect(parseSubsurfaceSerial('Divesoft', 'ab12'), 0xab12);
    expect(parseSubsurfaceSerial('Divesoft', 'zz!'), 0);
  });

  test('shearwaterModelFromProduct inverts the product names', () {
    expect(shearwaterModelFromProduct('Petrel 3'), ShearwaterModel.petrel3);
    expect(shearwaterModelFromProduct('Peregrine TX'),
        ShearwaterModel.peregrineTx);
    expect(shearwaterModelFromProduct('Nope'), ShearwaterModel.unknown);
    expect(shearwaterModelFromProduct(null), ShearwaterModel.unknown);
  });

  test('subsurfaceSerialForms: Shearwater and null vendor give one form', () {
    expect(subsurfaceSerialForms('Shearwater', 0xB89641E4), {0xB89641E4});
    expect(subsurfaceSerialForms(null, 1234567), {1234567});
  });

  test('subsurfaceSerialForms: Divesoft 1234567 adds the old hex reading',
      () {
    expect(subsurfaceSerialForms('Divesoft', 1234567), {1234567, 0x1234567});
  });
}
