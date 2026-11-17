import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:libdivecomputer/src/parse/descriptor_choice.dart';
import 'package:libdivecomputer/src/parse/wall_clock.dart';
import 'package:test/test.dart';

Uint8List _garbage(int n) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 37 + 11) & 0xff));

LibdcEnvelope _envelope({
  required String vendor,
  required String product,
  required int family,
  required int model,
  Uint8List? data,
}) => LibdcEnvelope(
  pinnedCommit: Libdc.pinnedCommit,
  vendor: vendor,
  product: product,
  family: family,
  descriptorModel: model,
  fingerprint: Uint8List.fromList([1, 2, 3, 4]),
  data: data ?? _garbage(300),
);

void main() {
  final liberty = Libdc.descriptors().singleWhere(
    (d) => d.vendor == 'Divesoft' && d.product == 'Liberty',
  );

  test('parseDive of garbage data throws LibdcParseException, never crashes',
      () {
    for (final size in [0, 1, 7, 300, 5000]) {
      final e = _envelope(
        vendor: liberty.vendor,
        product: liberty.product,
        family: liberty.family,
        model: liberty.model,
        data: _garbage(size),
      );
      expect(() => parseDive(e), throwsA(isA<LibdcParseException>()));
    }
  });

  test('parseDive finds the descriptor by name even when the family number '
      'differs', () {
    final wrongFamily = _envelope(
      vendor: liberty.vendor,
      product: liberty.product,
      family: 0x7fff0000,
      model: liberty.model,
    );
    // Found by vendor and product, then the garbage fails to parse. If the
    // lookup had failed, the status would be `unsupported` from our own
    // "no descriptor" path, with a different cause.
    expect(
      () => parseDive(wrongFamily),
      throwsA(
        isA<LibdcParseException>().having(
          (e) => e.status,
          'status',
          LibdcStatus.dataFormat,
        ),
      ),
    );
  });

  test('parseDive falls back to family and model when the name is unknown',
      () {
    final byFamily = _envelope(
      vendor: 'Renamed',
      product: 'Thing',
      family: liberty.family,
      model: liberty.model,
    );
    expect(
      () => parseDive(byFamily),
      throwsA(
        isA<LibdcParseException>().having(
          (e) => e.status,
          'status',
          LibdcStatus.dataFormat,
        ),
      ),
    );
  });

  test('parseDive with no matching descriptor is unsupported', () {
    final nothing = _envelope(
      vendor: 'Nobody',
      product: 'Nothing',
      family: 0x7fff0000,
      model: 999,
    );
    expect(
      () => parseDive(nothing),
      throwsA(
        isA<LibdcParseException>().having(
          (e) => e.status,
          'status',
          LibdcStatus.unsupported,
        ),
      ),
    );
  });

  test('LibdcStatus.fromCode maps known codes and falls back to io', () {
    expect(LibdcStatus.fromCode(-9), LibdcStatus.dataFormat);
    expect(LibdcStatus.fromCode(0), LibdcStatus.success);
    expect(LibdcStatus.fromCode(-1234), LibdcStatus.io);
  });

  test('an i200C dive resolves to its own model, not the first i200C', () {
    final table = [
      for (final d in Libdc.descriptors())
        (d.vendor, d.product, d.family, d.model),
    ];
    final i200c = Libdc.descriptors()
        .where((d) => d.vendor == 'Aqualung' && d.product == 'i200C')
        .toList();
    expect(i200c.map((d) => d.model), containsAll([0x4649, 0x4749]));
    for (final model in [0x4649, 0x4749]) {
      final index = chooseDescriptorIndex(
        table,
        vendor: 'Aqualung',
        product: 'i200C',
        family: 0x7fff0000, // wrong family: the name and model decide
        model: model,
      );
      expect(table[index!].$4, model);
      expect(table[index].$2, 'i200C');
    }
  });

  test('chooseDescriptorIndex: exact beats name-only, then family+model', () {
    const table = [
      ('A', 'x', 1, 10),
      ('A', 'x', 1, 11),
      ('B', 'y', 2, 20),
    ];
    int? pick(String v, String p, int f, int m) => chooseDescriptorIndex(
      table,
      vendor: v,
      product: p,
      family: f,
      model: m,
    );
    expect(pick('A', 'x', 1, 11), 1);
    expect(pick('A', 'x', 9, 11), 1);
    expect(pick('Renamed', 'z', 2, 20), 2);
    // Name matches but the model does not: family+model decides.
    expect(pick('A', 'x', 2, 20), 2);
    expect(pick('A', 'x', 1, 99), isNull);
    expect(pick('Q', 'q', 9, 9), isNull);
  });

  test('an impossible wall clock is a dataFormat failure', () {
    expect(
      libdcWallClock(2026, 6, 1, 9, 30, 0),
      DateTime.utc(2026, 6, 1, 9, 30),
    );
    for (final a in [
      [2026, 0, 1, 9, 30, 0],
      [2026, 13, 1, 9, 30, 0],
      [2026, 6, 0, 9, 30, 0],
      [2026, 6, 1, 24, 0, 0],
      [2026, 6, 1, 9, 60, 0],
      [2026, 6, 1, 9, 30, 61],
    ]) {
      expect(
        () => libdcWallClock(a[0], a[1], a[2], a[3], a[4], a[5]),
        throwsA(isA<LibdcParseException>()),
      );
    }
  });
}
