import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:libdivecomputer/src/bindings.g.dart';
import 'package:libdivecomputer/src/upstream.g.dart';
import 'package:test/test.dart';

LibdcDescriptor _one(String vendor, String product) => Libdc.descriptors()
    .singleWhere((d) => d.vendor == vendor && d.product == product);

void main() {
  test('version names the pinned revision', () {
    expect(Libdc.version, contains(kLibdcPinnedCommit.substring(0, 7)));
    expect(Libdc.pinnedCommit, kLibdcPinnedCommit);
  });

  test('descriptors include Divesoft Liberty, OSTC 4 and Ratio iX3M 2021 '
      'GPS Tech+', () {
    final liberty = _one('Divesoft', 'Liberty');
    expect(liberty.family, dc_family_t.DC_FAMILY_DIVESOFT_FREEDOM);
    expect(liberty.model, 10);
    expect(liberty.supportsBle, isTrue);

    final ostc4 = _one('Heinrichs Weikamp', 'OSTC 4');
    expect(ostc4.family, dc_family_t.DC_FAMILY_HW_OSTC3);
    expect(ostc4.model, 0x43);
    expect(ostc4.supportsBle, isTrue);

    final ix3m = _one('Ratio', 'iX3M 2021 GPS Tech+');
    expect(ix3m.family, dc_family_t.DC_FAMILY_DIVESYSTEM_IDIVE);
    expect(ix3m.model, 0x64);
    expect(ix3m.supportsBle, isTrue);
  });

  test('every Shearwater family descriptor is flagged as Shearwater', () {
    final shearwater = Libdc.descriptors().where(
      (d) =>
          d.family == dc_family_t.DC_FAMILY_SHEARWATER_PREDATOR ||
          d.family == dc_family_t.DC_FAMILY_SHEARWATER_PETREL,
    );
    expect(shearwater, isNotEmpty);
    expect(shearwater.every((d) => d.isShearwater), isTrue);
    for (final d in shearwater) {
      final matched = Libdc.matchBle(d.product)
          .any((m) => m.family == d.family && m.model == d.model);
      expect(matched, isFalse, reason: '$d');
    }
  });

  test('matchBle never offers a Shearwater', () {
    for (final name in ['Petrel', 'Perdix', 'Teric']) {
      expect(Libdc.matchBle(name), isEmpty, reason: name);
    }
  });

  test('matchBle("Liberty 1234") gives the Divesoft Freedom family, Liberty '
      'included', () {
    // Upstream's dc_filter_divesoft matches a name by the prefixes "Freedom"
    // and "Liberty" for both models of the family, so the filter alone cannot
    // tell the two apart; the model is resolved from the connected device.
    final matches = Libdc.matchBle('Liberty 1234');
    expect(
      matches.map((d) => d.product),
      unorderedEquals(['Freedom', 'Liberty']),
    );
    expect(matches.every((d) => d.vendor == 'Divesoft'), isTrue);
    expect(
      matches.every((d) => d.family == dc_family_t.DC_FAMILY_DIVESOFT_FREEDOM),
      isTrue,
    );
  });

  test(
    'matchBle("OSTC4-12345") gives only BLE models of DC_FAMILY_HW_OSTC3',
    () {
      final matches = Libdc.matchBle('OSTC4-12345');
      expect(matches, isNotEmpty);
      expect(
        matches.every((d) => d.family == dc_family_t.DC_FAMILY_HW_OSTC3),
        isTrue,
      );
      expect(matches.every((d) => d.supportsBle), isTrue);
      expect(matches.map((d) => d.product), contains('OSTC 4'));
    },
  );

  test('matchBle("RATIO-123") gives only DC_FAMILY_DIVESYSTEM_IDIVE models '
      'with BLE', () {
    final matches = Libdc.matchBle('RATIO-123');
    expect(matches, isNotEmpty);
    expect(
      matches.every((d) => d.family == dc_family_t.DC_FAMILY_DIVESYSTEM_IDIVE),
      isTrue,
    );
    expect(matches.every((d) => d.supportsBle), isTrue);
  });

  test('matchBle of an empty or blank name is empty', () {
    expect(Libdc.matchBle(''), isEmpty);
    expect(Libdc.matchBle('   '), isEmpty);
  });

  test('every family is present in the default build', () {
    expect(Libdc.familyPresent(dc_family_t.DC_FAMILY_DIVESOFT_FREEDOM), isTrue);
    expect(Libdc.familyPresent(dc_family_t.DC_FAMILY_HW_OSTC3), isTrue);
  });
}
