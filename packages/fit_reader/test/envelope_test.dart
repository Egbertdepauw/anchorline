import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';
import 'package:test/test.dart';

void main() {
  final fit = Uint8List.fromList([1, 2, 3, 4, 5]);

  test('envelope round trip', () {
    final e = FitEnvelope(
      source: FitSource.connectExport,
      fileName: 'dive é 1.fit',
      fit: fit,
    );
    final bytes = e.encode();
    expect(bytes.sublist(0, 4), [0x41, 0x4C, 0x46, 0x54]);
    expect(bytes[4], 1);
    expect(bytes[5], 1);
    final back = FitEnvelope.decode(bytes);
    expect(back.source, FitSource.connectExport);
    expect(back.fileName, 'dive é 1.fit');
    expect(back.fit, fit);
  });

  test('every source survives a round trip', () {
    for (final s in FitSource.values) {
      final b = FitEnvelope(source: s, fileName: '', fit: fit).encode();
      expect(FitEnvelope.decode(b).source, s);
    }
  });

  test('bad magic, version 2 and truncation throw FormatException', () {
    final good = FitEnvelope(
      source: FitSource.file,
      fileName: 'a.fit',
      fit: fit,
    ).encode();

    final badMagic = Uint8List.fromList(good)..[0] = 0x58;
    expect(() => FitEnvelope.decode(badMagic), throwsFormatException);

    final v2 = Uint8List.fromList(good)..[4] = 2;
    expect(() => FitEnvelope.decode(v2), throwsFormatException);

    expect(
      () => FitEnvelope.decode(Uint8List.sublistView(good, 0, good.length - 1)),
      throwsFormatException,
    );
    expect(
      () => FitEnvelope.decode(Uint8List.sublistView(good, 0, 9)),
      throwsFormatException,
    );
    expect(() => FitEnvelope.decode(Uint8List(3)), throwsFormatException);
  });
}
