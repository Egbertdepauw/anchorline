import 'dart:typed_data';

import 'package:libdivecomputer/libdivecomputer.dart';
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
      model: 999,
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
}
