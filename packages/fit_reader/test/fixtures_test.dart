import 'dart:io';
import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';
import 'package:subsurface_core/subsurface_core.dart';
import 'package:test/test.dart';

Uint8List _load(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

List<(int o2, int he, bool dil)> _gases(Dive d) => [
  for (final g in d.gasMixes) (g.oxygenPercent, g.heliumPercent, g.isDiluent),
];

void main() {
  const mk1a = 'garmin_mk1_ccr_2023-08-17.fit';
  const mk1b = 'garmin_mk1_ccr_2023-10-21.fit';
  const suunto = 'suunto_ocean_nitrox.fit';

  test('Mk1 dive 1: facts', () {
    final bytes = _load(mk1a);
    expect(classifyFit(bytes), FitFileKind.dive);
    final dives = mapFitFile(bytes);
    expect(dives, hasLength(1));
    final d = dives.single.dive;
    expect(d.dcVendor, 'Garmin');
    expect(d.dcProduct, 'Descent Mk1');
    expect(d.dcModelCode, 2859);
    expect(d.dcSerial, 1000000001);
    expect(d.startTime, DateTime.utc(2023, 8, 17, 8, 51, 59));
    expect(d.utcOffsetMinutes, 720);
    expect(d.dcDiveNumber, 11);
    expect(d.diveMode, DiveMode.cc);
    expect(d.gfLow, 50);
    expect(d.gfHigh, 60);
    expect(d.waterDensityKgM3, 1025);
    expect(d.maxDepthMeters, closeTo(51.765, 0.01));
    expect(d.duration.inMinutes, inInclusiveRange(97, 99));
    expect(d.sampleIntervalMs, 1000);
    expect(d.atmosphericPressureMbar, 1022);
    expect(_gases(d), [
      (18, 20, true),
      (18, 20, false),
      (50, 0, false),
      (50, 0, true),
    ]);
    final sp = dives.single.samples.setpointBar;
    expect(sp.first, closeTo(0.7, 1e-6));
    expect(sp.reduce((a, b) => a > b ? a : b), closeTo(1.3, 1e-6));
  });

  test('Mk1 dive 2: facts', () {
    final bytes = _load(mk1b);
    expect(classifyFit(bytes), FitFileKind.dive);
    final dives = mapFitFile(bytes);
    expect(dives, hasLength(1));
    final d = dives.single.dive;
    expect(d.dcVendor, 'Garmin');
    expect(d.dcProduct, 'Descent Mk1');
    expect(d.dcModelCode, 2859);
    expect(d.dcSerial, 1000000001);
    expect(d.startTime, DateTime.utc(2023, 10, 21, 12, 13, 38));
    expect(d.utcOffsetMinutes, 780);
    expect(d.dcDiveNumber, 538);
    expect(d.diveMode, DiveMode.cc);
    expect(d.gfLow, 50);
    expect(d.gfHigh, 70);
    expect(d.maxDepthMeters, closeTo(62.02, 0.01));
    expect(d.duration.inMinutes, inInclusiveRange(105, 107));
    expect(d.atmosphericPressureMbar, 1024);
    expect(_gases(d), [
      (17, 30, true),
      (17, 30, false),
      (52, 0, false),
      (52, 0, true),
    ]);
  });

  test('Suunto Ocean: vendor Suunto, product Ocean, serial 0, ocTec, '
      'one 32% mix, GF 40/85', () {
    final bytes = _load(suunto);
    expect(classifyFit(bytes), FitFileKind.dive);
    final dives = mapFitFile(bytes);
    expect(dives, hasLength(1));
    final d = dives.single.dive;
    expect(d.dcVendor, 'Suunto');
    expect(d.dcProduct, 'Ocean');
    expect(d.dcSerial, 0);
    expect(d.diveMode, DiveMode.ocTec);
    expect(_gases(d), [(32, 0, false)]);
    expect(d.gfLow, 40);
    expect(d.gfHigh, 85);
    expect(d.atmosphericPressureMbar, 1013);
  });

  test('the committed fixtures hold no position, profile or original serial',
      () {
    for (final name in [mk1a, mk1b, suunto]) {
      final file = decodeFit(_load(name));
      for (final m in file.messages) {
        if (m.global == 3) {
          expect(
            m.fields.values.every((f) => f.value == null),
            isTrue,
            reason: '$name: user profile',
          );
        }
        if (m.global == FitMesg.session) {
          for (final n in [3, 4, 29, 30, 31, 32, 38, 39]) {
            expect(m.fields[n]?.value, isNull, reason: '$name: session $n');
          }
        }
        if (m.global == FitMesg.record) {
          expect(m.fields[0]?.value, isNull, reason: '$name: record lat');
          expect(m.fields[1]?.value, isNull, reason: '$name: record lon');
        }
        if (m.global == FitMesg.fileId || m.global == FitMesg.deviceInfo) {
          final serial = m.intField(3);
          expect(serial == null || serial == 1000000001, isTrue,
              reason: '$name: serial');
        }
      }
    }
  });
}
