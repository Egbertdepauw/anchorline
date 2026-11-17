import 'package:libdivecomputer/libdivecomputer.dart';
import 'package:subsurface_core/subsurface_core.dart';
import 'package:test/test.dart';

import 'support/builders.dart';

ConvertedDive _map(LibdcParsedDive p, {LibdcEnvelope? e}) =>
    mapLibdcDive(p, e ?? testEnvelope(), diveId: 'abc');

void main() {
  group('samples', () {
    test('four cells give four cellPpo2Bar channels and ppO2 is their median '
        'when not voted', () {
      final c = _map(
        testDive(
          rows: [
            row(0, depth: 0, cells: {0: 0.98, 1: 1.0, 2: 1.02, 3: 1.1}),
            row(10000, depth: 3, cells: {0: 0.98, 1: 1.0, 2: 1.02, 3: 1.1}),
          ],
        ),
      );
      expect(c.samples.cellPpo2Bar, hasLength(4));
      expect(c.samples.cellPpo2Bar[3][0], closeTo(1.1, 1e-6));
      expect(c.samples.ppo2Bar[0], closeTo(1.01, 1e-6));
    });

    test('voted ppO2 wins over the cells', () {
      final c = _map(
        testDive(
          rows: [
            row(0, depth: 0, ppo2: 1.2, cells: {0: 0.9, 1: 0.9, 2: 0.9}),
          ],
        ),
      );
      expect(c.samples.ppo2Bar[0], closeTo(1.2, 1e-6));
    });

    test('no ppO2 at all is 0', () {
      final c = _map(testDive(rows: [row(0, depth: 1)]));
      expect(c.samples.ppo2Bar[0], 0);
      expect(c.samples.cellPpo2Bar, isEmpty);
    });

    test('Shearwater-only fields stay empty: mV zero-filled, no calibration, '
        'no stack times', () {
      final c = _map(
        testDive(
          rows: [
            row(0, depth: 0, cells: {0: 1.0, 1: 1.0}),
            row(10000, depth: 5),
          ],
        ),
      );
      final s = c.samples;
      expect(s.sampleCount, 2);
      for (final col in [s.cellMv0, s.cellMv1, s.cellMv2]) {
        expect(col, [0, 0]);
      }
      expect(s.statusFlags, [0, 0]);
      expect(c.dive.sensorCalibration, isEmpty);
      expect(c.dive.configuredStackSeconds, isNull);
      expect(c.dive.stackRemainingAtStartSeconds, isNull);
      expect(c.dive.stackRemainingAtEndSeconds, isNull);
      expect(c.dive.logVersion, 0);
      expect(c.dive.dcModel, ShearwaterModel.unknown);
    });

    test('tank pressure channels follow the tanks and carry forward', () {
      final c = _map(
        testDive(
          tanks: const [
            LibdcTank(
              gasMix: 0,
              volumeLiters: 12,
              workPressureBar: 232.4,
              beginPressureBar: 200,
              endPressureBar: 120,
              usage: LibdcUsage.diluent,
            ),
            LibdcTank(beginPressureBar: 190, endPressureBar: 150),
          ],
          rows: [
            row(0, depth: 0, pressures: {0: 200, 1: 190}),
            row(10000, depth: 5),
            row(20000, depth: 5, pressures: {0: 190}),
          ],
        ),
      );
      final t = c.samples.tankPressuresBar;
      expect(t, hasLength(2));
      expect(t[0], [200, 200, 190]);
      expect(t[1], [190, 190, 190]);
      expect(c.dive.tanks, hasLength(2));
      expect(c.dive.tanks[0].slot, 0);
      expect(c.dive.tanks[0].usage, TankUsage.diluent);
      expect(c.dive.tanks[0].pressureMaxBar, 232);
      expect(c.dive.tanks[0].pressureReserveBar, 0);
      expect(c.dive.tanks[0].beginPressureBar, 200);
      expect(c.dive.tanks[1].usage, TankUsage.none);
      expect(c.dive.tanks[1].name, '');
      expect(c.dive.tanks[1].serial, 0);
    });

    test('pressures without TANK fields make a tank per index seen', () {
      final c = _map(
        testDive(
          rows: [
            row(0, depth: 0, pressures: {2: 0, 0: 200}),
            row(10000, depth: 5, pressures: {2: 150, 0: 180}),
            row(20000, depth: 5, pressures: {2: 100}),
          ],
        ),
      );
      expect(c.dive.tanks, hasLength(2));
      expect(c.dive.tanks.map((t) => t.slot), [0, 1]);
      expect(c.dive.tanks[0].beginPressureBar, 200);
      expect(c.dive.tanks[0].endPressureBar, 180);
      expect(c.dive.tanks[1].beginPressureBar, 150);
      expect(c.dive.tanks[1].endPressureBar, 100);
      expect(c.dive.tanks[1].usage, TankUsage.none);
      expect(c.dive.tanks[1].pressureMaxBar, 0);
      expect(c.samples.tankPressuresBar, hasLength(2));
      expect(c.samples.tankPressuresBar[0], [200, 180, 180]);
      expect(c.samples.tankPressuresBar[1], [0, 150, 100]);
    });

    test('CNS stays a fraction and deco and TTS are in seconds', () {
      final c = _map(
        testDive(
          rows: [
            row(
              0,
              depth: 30,
              cns: 0.25,
              deco: const LibdcDeco(
                type: LibdcDecoType.decoStop,
                timeSeconds: 180,
                depthM: 9,
                ttsSeconds: 1200,
              ),
            ),
          ],
        ),
      );
      expect(c.samples.cns[0], closeTo(0.25, 1e-6));
      expect(c.samples.decoStopDepthMeters[0], 9);
      expect(c.samples.decoTimeSeconds[0], 180);
      expect(c.samples.ttsSeconds[0], 1200);
    });
  });

  group('time', () {
    test('no time zone leaves utcOffsetMinutes null; +02:00 gives 120', () {
      expect(_map(testDive()).dive.utcOffsetMinutes, isNull);
      expect(
        _map(testDive(timezoneSeconds: 7200)).dive.utcOffsetMinutes,
        120,
      );
      expect(
        _map(testDive(timezoneSeconds: -18000)).dive.utcOffsetMinutes,
        -300,
      );
    });

    test('wall clock is stored as if UTC whatever the zone', () {
      final c = _map(
        testDive(
          wallClock: DateTime.utc(2026, 6, 1, 9, 30),
          timezoneSeconds: 7200,
          diveTimeSeconds: 3600,
        ),
      );
      expect(c.dive.startTime, DateTime.utc(2026, 6, 1, 9, 30));
      expect(c.dive.endTime, DateTime.utc(2026, 6, 1, 10, 30));
      expect(c.dive.duration, const Duration(hours: 1));
    });

    test('duration falls back to the last row, depth to the deepest sample',
        () {
      final c = _map(
        testDive(
          rows: [
            row(0, depth: 0),
            row(60000, depth: 12.5),
            row(120000, depth: 0),
          ],
        ),
      );
      expect(c.dive.duration, const Duration(seconds: 120));
      expect(c.dive.maxDepthMeters, 12.5);
      expect(c.dive.sampleIntervalMs, 60000);
    });

    test('a dive without a wall clock is a dataFormat failure', () {
      expect(
        () => _map(testDive(noWallClock: true)),
        throwsA(
          isA<LibdcParseException>().having(
            (e) => e.status,
            'status',
            LibdcStatus.dataFormat,
          ),
        ),
      );
    });
  });

  group('identity', () {
    test('identity comes from the envelope', () {
      final c = _map(testDive());
      expect(c.dive.id, 'abc');
      expect(c.samples.diveId, 'abc');
      expect(c.dive.dcSerial, 1234567);
      expect(c.dive.dcDiveNumber, 0);
      expect(c.dive.dcVendor, 'Divesoft');
      expect(c.dive.dcProduct, 'Liberty');
      expect(c.dive.dcFamily, 0x130000);
      expect(c.dive.dcModelCode, 10);
    });

    test('no serial gives dcSerial 0, and the model code falls back to the '
        'descriptor', () {
      final c = _map(testDive(), e: testEnvelope(serial: null));
      expect(c.dive.dcSerial, 0);
      expect(c.dive.dcModelCode, 10);
      final withInfo = _map(testDive(), e: testEnvelope(model: 0x43));
      expect(withInfo.dive.dcModelCode, 0x43);
    });
  });

  group('header', () {
    test('dive modes map as the table says; none with a setpoint is cc, '
        'without is ocTec', () {
      DiveMode mode(LibdcDiveMode? m, {double? setpoint}) => _map(
        testDive(diveMode: m, rows: [row(0, depth: 1, setpoint: setpoint)]),
      ).dive.diveMode;
      expect(mode(LibdcDiveMode.ccr), DiveMode.cc);
      expect(mode(LibdcDiveMode.scr), DiveMode.sc);
      expect(mode(LibdcDiveMode.oc), DiveMode.ocTec);
      expect(mode(LibdcDiveMode.gauge), DiveMode.gauge);
      expect(mode(LibdcDiveMode.freedive), DiveMode.freedive);
      expect(mode(null, setpoint: 0.7), DiveMode.cc);
      expect(mode(null, setpoint: 0), DiveMode.ocTec);
      expect(mode(null), DiveMode.ocTec);
    });

    test('deco model, gradient factors, pressure and water density', () {
      Dive dive({
        LibdcDecoModel? model,
        double? atm,
        LibdcSalinity? sal,
      }) => _map(
        testDive(decoModel: model, atmosphericBar: atm, salinity: sal),
      ).dive;

      final gf = dive(
        model: const LibdcDecoModel(
          type: LibdcDecoModelType.buhlmann,
          gfLow: 30,
          gfHigh: 85,
        ),
      );
      expect(gf.decoModel, DecoModel.gf);
      expect(gf.gfLow, 30);
      expect(gf.gfHigh, 85);

      final noGf = dive(
        model: const LibdcDecoModel(type: LibdcDecoModelType.buhlmann),
      );
      expect((noGf.gfLow, noGf.gfHigh), (0, 0));

      expect(
        dive(
          model: const LibdcDecoModel(type: LibdcDecoModelType.vpm),
        ).decoModel,
        DecoModel.vpmb,
      );
      expect(
        dive(
          model: const LibdcDecoModel(type: LibdcDecoModelType.dciem),
        ).decoModel,
        DecoModel.dciem,
      );
      for (final m in [
        const LibdcDecoModel(type: LibdcDecoModelType.rgbm),
        const LibdcDecoModel(type: LibdcDecoModelType.none),
        null,
      ]) {
        final d = dive(model: m);
        expect(d.decoModel, DecoModel.gf);
        expect((d.gfLow, d.gfHigh), (0, 0));
      }

      expect(dive(atm: 1.0132).atmosphericPressureMbar, 1013);
      expect(dive(atm: 0.8).atmosphericPressureMbar, 800);
      expect(dive().atmosphericPressureMbar, 1013);

      expect(dive().waterDensityKgM3, 1020);
      expect(
        dive(
          sal: const LibdcSalinity(water: LibdcWater.fresh, density: 0),
        ).waterDensityKgM3,
        1000,
      );
      expect(
        dive(
          sal: const LibdcSalinity(water: LibdcWater.salt, density: 0),
        ).waterDensityKgM3,
        1030,
      );
      expect(
        dive(
          sal: const LibdcSalinity(water: LibdcWater.salt, density: 1024.6),
        ).waterDensityKgM3,
        1025,
      );
    });
  });

  group('gas', () {
    test('a dive with no gas mixes gets one air mix and index 0 everywhere',
        () {
      final c = _map(
        testDive(
          diveMode: LibdcDiveMode.gauge,
          rows: [row(0, depth: 0), row(10000, depth: 5, gas: 3)],
        ),
      );
      expect(c.dive.gasMixes, hasLength(1));
      expect(c.dive.gasMixes[0].oxygenPercent, 21);
      expect(c.dive.gasMixes[0].heliumPercent, 0);
      expect(c.dive.gasMixes[0].isDiluent, isFalse);
      expect(c.samples.gasMixIndex, [0, 0]);
      expect(c.events, isEmpty);
    });

    test('an OXYGEN-usage mix is left out and the gas indexes skip it', () {
      final c = _map(
        testDive(
          gasMixes: const [
            LibdcGasMix(oxygen: 0.21, helium: 0.35, usage: LibdcUsage.diluent),
            LibdcGasMix(oxygen: 1.0, helium: 0, usage: LibdcUsage.oxygen),
            LibdcGasMix(oxygen: 0.5, helium: 0, usage: LibdcUsage.none),
          ],
          rows: [
            row(0, depth: 0, gas: 0),
            row(10000, depth: 20, gas: 1), // oxygen: keeps the previous index
            row(20000, depth: 20, gas: 2),
          ],
        ),
      );
      expect(c.dive.gasMixes, hasLength(2));
      expect(c.dive.gasMixes[1].oxygenPercent, 50);
      expect(c.samples.gasMixIndex, [0, 0, 1]);
      expect(
        c.events.where((e) => e.type == DiveEventType.gasSwitch).map(
          (e) => (e.timeMs, e.value),
        ),
        [(20000, 1)],
      );
    });

    test('diluent and bailout mixes keep their order and isDiluent', () {
      final c = _map(
        testDive(
          gasMixes: const [
            LibdcGasMix(oxygen: 0.21, helium: 0.35, usage: LibdcUsage.diluent),
            LibdcGasMix(oxygen: 0.18, helium: 0.45, usage: LibdcUsage.none),
            LibdcGasMix(
              oxygen: 0.5,
              helium: 0,
              usage: LibdcUsage.sidemount,
            ),
          ],
        ),
      );
      expect(c.dive.gasMixes.map((m) => m.isDiluent), [true, false, false]);
      expect(c.dive.gasMixes.map((m) => (m.oxygenPercent, m.heliumPercent)), [
        (21, 35),
        (18, 45),
        (50, 0),
      ]);
    });
  });

  group('events', () {
    test('gas and setpoint changes become events at their row times', () {
      final c = _map(
        testDive(
          gasMixes: const [
            LibdcGasMix(oxygen: 0.21, helium: 0.35, usage: LibdcUsage.diluent),
            LibdcGasMix(oxygen: 0.5, helium: 0, usage: LibdcUsage.none),
          ],
          rows: [
            row(0, depth: 0, setpoint: 0.7, gas: 0),
            row(10000, depth: 10, setpoint: 0.72, gas: 0), // under 0.05
            row(20000, depth: 20, setpoint: 1.3, gas: 0),
            row(30000, depth: 20, gas: 1),
            row(40000, depth: 20, gas: 1),
          ],
        ),
      );
      final summary = c.events
          .map((e) => (e.timeMs, e.type, e.value))
          .toList();
      expect(summary, [
        (20000, DiveEventType.setpointChange, 130),
        (30000, DiveEventType.gasSwitch, 1),
      ]);
    });

    test('a dive that opens on a setpoint or a gas gets no event for it', () {
      final c = _map(
        testDive(
          gasMixes: const [
            LibdcGasMix(oxygen: 0.21, helium: 0, usage: LibdcUsage.diluent),
            LibdcGasMix(oxygen: 0.5, helium: 0, usage: LibdcUsage.none),
          ],
          rows: [
            row(0, depth: 0, setpoint: 1.3, gas: 1),
            row(10000, depth: 5, setpoint: 1.3, gas: 1),
          ],
        ),
      );
      expect(c.events, isEmpty);
    });

    test('a bookmark keeps rawType; an event value beyond int32 becomes null',
        () {
      final c = _map(
        testDive(
          rows: [
            row(0, depth: 0),
            row(
              10000,
              depth: 5,
              events: const [
                LibdcSampleEvent(type: evBookmark, flags: 0, value: 7),
                LibdcSampleEvent(
                  type: evViolation,
                  flags: 0,
                  value: 0xFFFFFFFF,
                ),
              ],
            ),
          ],
        ),
      );
      expect(c.events, hasLength(2));
      expect(c.events[0].type, DiveEventType.bookmark);
      expect(c.events[0].rawType, evBookmark);
      expect(c.events[0].value, 7);
      expect(c.events[0].timeMs, 10000);
      expect(c.events[1].type, DiveEventType.decoWarning);
      expect(c.events[1].rawType, evViolation);
      expect(c.events[1].value, isNull);
    });

    test('event types map as the table says', () {
      DiveEventType of(int raw) => _map(
        testDive(
          rows: [
            row(
              0,
              depth: 0,
              events: [LibdcSampleEvent(type: raw, flags: 0, value: 0)],
            ),
          ],
        ),
      ).events.single.type;
      expect(of(evBookmark), DiveEventType.bookmark);
      expect(of(evCeiling), DiveEventType.ceilingViolation);
      expect(of(evCeilingSafetystop), DiveEventType.ceilingViolation);
      expect(of(evAscent), DiveEventType.ascentWarning);
      expect(of(evDecostop), DiveEventType.decoWarning);
      expect(of(evDeepstop), DiveEventType.decoWarning);
      expect(of(evViolation), DiveEventType.decoWarning);
      expect(of(evSurface), DiveEventType.other);
      expect(of(11), DiveEventType.other); // deprecated GASCHANGE
    });
  });
}
