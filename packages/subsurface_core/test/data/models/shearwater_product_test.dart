import 'package:subsurface_core/shearwater/parser/hardware.dart';
import 'package:test/test.dart';

void main() {
  test('every model except unknown has a distinct product name', () {
    final names = <String>{};
    for (final m in ShearwaterModel.values) {
      if (m == ShearwaterModel.unknown) continue;
      final name = shearwaterProductName(m);
      expect(name, isNotNull, reason: '$m');
      expect(names.add(name!), isTrue, reason: 'duplicate name for $m');
    }
  });

  test('petrel3 is "Petrel 3" and unknown is null', () {
    expect(shearwaterProductName(ShearwaterModel.petrel3), 'Petrel 3');
    expect(shearwaterProductName(ShearwaterModel.unknown), isNull);
    expect(kShearwaterVendor, 'Shearwater');
  });
}
