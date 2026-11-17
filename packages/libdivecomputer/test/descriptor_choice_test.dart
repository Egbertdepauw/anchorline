// The identity descriptor over libdivecomputer's real descriptor table, and
// what it does to a parse.
import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:libdivecomputer/src/parse/descriptor_choice.dart';
import 'package:test/test.dart';

import 'support/petrel3_replay.dart';

void main() {
  final all = Libdc.descriptors();
  final table = [for (final d in all) (d.vendor, d.product, d.family, d.model)];

  int indexOf(String vendor, String product) =>
      all.indexWhere((d) => d.vendor == vendor && d.product == product);

  (String, String) identity(String vendor, String product, int? devinfoModel) {
    final i = identityDescriptorIndex(
      table,
      opened: indexOf(vendor, product),
      devinfoModel: devinfoModel,
    );
    return (table[i].$1, table[i].$2);
  }

  test('an OSTC 4 opened as "OSTC 2" is an OSTC 4', () {
    // matchBle's first candidate for "OSTC4-12345" is the OSTC 2 (model 0).
    expect(all[indexOf('Heinrichs Weikamp', 'OSTC 2')].model, 0);
    expect(identity('Heinrichs Weikamp', 'OSTC 2', 0x43), (
      'Heinrichs Weikamp',
      'OSTC 4',
    ));
    expect(identity('Heinrichs Weikamp', 'OSTC 2', 0x44), (
      'Heinrichs Weikamp',
      'OSTC 5',
    ));
  });

  test('an i300C opened as the first Oceanic candidate is an i300C', () {
    final i300c = all[indexOf('Aqualung', 'i300C')];
    final proPlusX = all[indexOf('Oceanic', 'Pro Plus X')];
    expect(proPlusX.family, i300c.family);
    expect(identity('Oceanic', 'Pro Plus X', i300c.model), (
      'Aqualung',
      'i300C',
    ));
  });

  test('siblings with one model are the same dive, whichever was opened', () {
    // Deep Six, Crest, Genesis and Scorpena sell one computer.
    final excursion = all[indexOf('Deep Six', 'Excursion')];
    final siblings = all
        .where(
          (d) => d.family == excursion.family && d.model == excursion.model,
        )
        .toList();
    expect(siblings.map((d) => d.vendor).toSet().length, greaterThan(1));
    for (final s in siblings) {
      expect(identity(s.vendor, s.product, excursion.model), (
        siblings.first.vendor,
        siblings.first.product,
      ));
    }
  });

  test('no device info, or a model no descriptor has: the one opened', () {
    expect(identity('Heinrichs Weikamp', 'OSTC 2', null), (
      'Heinrichs Weikamp',
      'OSTC 2',
    ));
    // hwOS 3 computers report a hardware byte no descriptor carries.
    expect(identity('Heinrichs Weikamp', 'OSTC 3', 0x0a), (
      'Heinrichs Weikamp',
      'OSTC 3',
    ));
    // Another family's model is not this family's.
    final petrel3 = all[indexOf('Shearwater', 'Petrel 3')];
    expect(identity('Heinrichs Weikamp', 'OSTC 2', petrel3.model), (
      'Heinrichs Weikamp',
      'OSTC 2',
    ));
  });

  group('a Petrel 3 dive whose envelope says it was opened as a Petrel 2', () {
    late final LibdcEnvelope real;
    late final LibdcParsedDive realParse;
    setUpAll(() async {
      real = (await replayPetrel3Dives()).first.envelope;
      realParse = parseDive(real);
    });

    LibdcEnvelope asPetrel2({required bool devinfo}) {
      final petrel2 = all[indexOf('Shearwater', 'Petrel 2')];
      return LibdcEnvelope(
        pinnedCommit: real.pinnedCommit,
        vendor: petrel2.vendor,
        product: petrel2.product,
        family: petrel2.family,
        descriptorModel: petrel2.model,
        devinfoModel: devinfo ? real.devinfoModel : null,
        devinfoFirmware: devinfo ? real.devinfoFirmware : null,
        devinfoSerial: devinfo ? real.devinfoSerial : null,
        fingerprint: real.fingerprint,
        data: Uint8List.fromList(real.data),
      );
    }

    test('is parsed and named as the Petrel 3 the computer reported', () {
      final e = asPetrel2(devinfo: true);
      final p = parseDive(e);
      expect(p.identityVendor, 'Shearwater');
      expect(p.identityProduct, 'Petrel 3');
      expect(p.rows.length, realParse.rows.length);
      expect(p.wallClock, realParse.wallClock);
      final mapped = mapLibdcDive(p, e, diveId: 'x');
      expect(mapped.dive.dcVendor, 'Shearwater');
      expect(mapped.dive.dcProduct, 'Petrel 3');
      expect(realParse.identityProduct, 'Petrel 3');
    });

    test('without device info it stays the Petrel 2 that was opened', () {
      final p = parseDive(asPetrel2(devinfo: false));
      expect(p.identityProduct, 'Petrel 2');
    });
  });
}
