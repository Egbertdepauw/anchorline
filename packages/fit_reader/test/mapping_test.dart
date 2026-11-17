import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fit_reader/fit_reader.dart';
import 'package:subsurface_core/subsurface_core.dart';
import 'package:test/test.dart';

import 'support/fit_writer.dart';

const _enumT = 0x00, _s8 = 0x01, _u8 = 0x02, _u16 = 0x84, _u32 = 0x86;
const _str = 0x07, _f32 = 0x88, _u32z = 0x8C;

FitMessageSpec _m(int g, Map<int, (int, Object)> f) => FitMessageSpec(g, f);

FitMessageSpec _fileId({
  int manufacturer = 1,
  int? product = 2859,
  int? serial = 1000000001,
  int timeCreated = 1061159483,
  bool withTimeCreated = true,
  String? productName,
}) => _m(0, {
  0: (_enumT, 4),
  1: (_u16, manufacturer),
  if (product != null) 2: (_u16, product),
  if (serial != null) 3: (_u32z, serial),
  if (withTimeCreated) 4: (_u32, timeCreated),
  if (productName != null) 8: (_str, productName),
});

FitMessageSpec _sport(int sub) => _m(12, {0: (_enumT, 53), 1: (_enumT, sub)});

FitMessageSpec _session(int start, int endTs, {int sub = 63}) => _m(18, {
  253: (_u32, endTs),
  2: (_u32, start),
  5: (_enumT, 53),
  6: (_enumT, sub),
  7: (_u32, (endTs - start) * 1000),
});

// The test writer keeps one definition per message, so every record carries
// the same fields.
FitMessageSpec _record(
  int ts,
  int depthMm, {
  int temp = 20,
  int stopDepthMm = 0,
  int stopTime = 0,
  int ndl = 0,
  int cns = 0,
}) => _m(20, {
  253: (_u32, ts),
  92: (_u32, depthMm),
  13: (_s8, temp),
  93: (_u32, stopDepthMm),
  94: (_u32, stopTime),
  96: (_u32, ndl),
  97: (_u8, cns),
});

FitMessageSpec _alert(int ts, int code) =>
    _m(21, {253: (_u32, ts), 0: (_enumT, 56), 1: (_enumT, 3), 3: (_u32, code)});

FitMessageSpec _gasSwitch(int ts, int gasIndex) => _m(21, {
  253: (_u32, ts),
  0: (_enumT, 57),
  1: (_enumT, 3),
  3: (_u32, gasIndex),
});

FitMessageSpec _gas(int index, int o2, int he, {int status = 1, int type = 0}) =>
    _m(259, {
      254: (_u16, index),
      0: (_u8, he),
      1: (_u8, o2),
      2: (_enumT, status),
      3: (_enumT, type),
    });

FitMessageSpec _settings({
  int gfLow = 50,
  int gfHigh = 60,
  double? density = 1025,
  int? waterType,
  int? lowSp,
  int? highSp,
}) => _m(258, {
  1: (_enumT, 0),
  2: (_u8, gfLow),
  3: (_u8, gfHigh),
  if (waterType != null) 4: (_enumT, waterType),
  if (density != null) 5: (_f32, density),
  if (lowSp != null) 23: (_u8, lowSp),
  if (highSp != null) 26: (_u8, highSp),
});

FitMessageSpec _sensor(int id, {String name = '        '}) => _m(147, {
  0: (_u32z, id),
  2: (_str, name),
  3: (_enumT, 1),
  52: (_enumT, 28),
  74: (_enumT, 2),
});

FitMessageSpec _tank(int ts, int sensor, int centiBar) => _m(319, {
  253: (_u32, ts),
  0: (_u32z, sensor),
  1: (_u16, centiBar),
});

FitMessageSpec _summary(int ts, {int? diveNumber, int maxDepth = 30000}) =>
    _m(268, {
      253: (_u32, ts),
      0: (_u16, 18),
      3: (_u32, maxDepth),
      if (diveNumber != null) 10: (_u32, diveNumber),
    });

const _start = 1061159483;

/// A short CCR dive of 12 s at 1 s records.
Uint8List _ccrFile({List<FitMessageSpec> extraEvents = const []}) => buildFit([
  _fileId(),
  _sport(63),
  _gas(0, 18, 45, type: 1),
  _gas(1, 21, 35),
  _gas(2, 50, 0),
  _settings(lowSp: 70, highSp: 130),
  for (var i = 0; i <= 12; i++)
    _record(_start + i, i * 1000, temp: 20 - i ~/ 4, cns: i),
  ...extraEvents,
  _session(_start, _start + 12),
  _summary(_start + 12, diveNumber: 11),
]);

ConvertedDive _one(Uint8List b) {
  final r = mapFitFile(b);
  expect(r, hasLength(1));
  return r.single;
}

void main() {
  test('without time_created, ids and fingerprints follow the session start',
      () {
    Uint8List file(int start) => buildFit([
      _fileId(withTimeCreated: false),
      _sport(63),
      _record(start, 0),
      _record(start + 5, 1000),
      _session(start, start + 5),
    ]);
    final a = _one(file(_start)).dive;
    final b = _one(file(_start + 86400)).dive;
    expect(a.id, isNot(b.id));
    expect(
      a.id,
      sha256
          .convert(utf8.encode('fit:1:1000000001:start$_start'))
          .toString()
          .substring(0, 32),
    );
    expect(
      a.id,
      fitDiveId(manufacturer: 1, serial: 1000000001, sessionStart: _start),
    );
    expect(
      fitFingerprintHex(serial: 1000000001, sessionStart: _start),
      isNot(fitFingerprintHex(serial: 1000000001, sessionStart: _start + 1)),
    );
    expect(
      fitFingerprintHex(serial: 1, sessionStart: 2, session: 1),
      '000000010000000201',
    );
    // A file with a time_created ignores the session start.
    expect(
      fitDiveId(
        manufacturer: 1,
        serial: 1000000001,
        timeCreated: 1061159483,
        sessionStart: 5,
      ),
      fitDiveId(manufacturer: 1, serial: 1000000001, timeCreated: 1061159483),
    );
    expect(
      () => fitDiveId(manufacturer: 1, serial: 1),
      throwsArgumentError,
    );
  });

  test('a session starting days before its records is refused', () {
    final bad = buildFit([
      _fileId(),
      _sport(63),
      _record(_start, 0),
      _record(_start + 5, 1000),
      _session(_start - 3 * 86400, _start + 5),
    ]);
    expect(
      () => mapFitFile(bad),
      throwsA(
        isA<FitFormatException>().having(
          (e) => e.message,
          'message',
          'implausible dive length',
        ),
      ),
    );
    expect(mapFitFile(_ccrFile()), hasLength(1));
  });

  test('a grid larger than 10 samples per record plus 3600 is refused', () {
    // 30 000 s from the start with two records is under 48 h but over the cap.
    final bad = buildFit([
      _fileId(),
      _sport(63),
      _record(_start + 30000, 0),
      _record(_start + 30001, 1000),
      _session(_start, _start + 30001),
    ]);
    expect(() => mapFitFile(bad), throwsA(isA<FitFormatException>()));
  });

  test('fitDiveId matches its formula', () {
    final want = sha256
        .convert(utf8.encode('fit:1:1000000001:1061159483'))
        .toString()
        .substring(0, 32);
    expect(want, '492ce7c10e6586790d49bb164517095a');
    expect(
      fitDiveId(manufacturer: 1, serial: 1000000001, timeCreated: 1061159483),
      want,
    );
    final s1 = sha256
        .convert(utf8.encode('fit:1:1000000001:1061159483:1'))
        .toString()
        .substring(0, 32);
    expect(
      fitDiveId(
        manufacturer: 1,
        serial: 1000000001,
        timeCreated: 1061159483,
        session: 1,
      ),
      s1,
    );
  });

  test('fitFingerprintHex(serial: 1, timeCreated: 2) == "0000000100000002"; '
      'session 1 appends "01"', () {
    expect(fitFingerprintHex(serial: 1, timeCreated: 2), '0000000100000002');
    expect(
      fitFingerprintHex(serial: 1, timeCreated: 2, session: 1),
      '000000010000000201',
    );
    expect(
      fitFingerprintHex(serial: 0xFFFFFFFF, timeCreated: 2, session: 12),
      'ffffffff000000020c',
    );
  });

  test('a CCR dive maps to cc with a diluent, bailout mixes and a '
      '0.7 → 1.3 setpoint trace', () {
    final c = _one(_ccrFile(extraEvents: [_alert(_start + 5, 25)]));
    final d = c.dive;
    expect(d.diveMode, DiveMode.cc);
    expect(d.decoModel, DecoModel.gf);
    expect((d.gfLow, d.gfHigh), (50, 60));
    expect(d.waterDensityKgM3, 1025);
    expect(d.atmosphericPressureMbar, 1013);
    expect(d.gasMixes, hasLength(3));
    expect(
      d.gasMixes.map((g) => (g.oxygenPercent, g.heliumPercent, g.isDiluent)),
      [(18, 45, true), (21, 35, false), (50, 0, false)],
    );
    final sp = c.samples.setpointBar;
    expect(sp[0], closeTo(0.7, 1e-6));
    expect(sp[4], closeTo(0.7, 1e-6));
    expect(sp[5], closeTo(1.3, 1e-6));
    expect(sp[12], closeTo(1.3, 1e-6));
    expect(d.dcDiveNumber, 11);
    expect(d.logVersion, 0);
    expect(d.sensorCalibration, isEmpty);
    expect(d.configuredStackSeconds, isNull);
    expect(d.stackRemainingAtStartSeconds, isNull);
    expect(d.stackRemainingAtEndSeconds, isNull);
  });

  test('empty channels follow the Shearwater OC convention', () {
    final c = _one(_ccrFile());
    final s = c.samples;
    expect(s.sampleCount, 13);
    expect(s.ppo2Bar, everyElement(0));
    expect(s.ppo2Bar, hasLength(13));
    expect(s.cellMv0, hasLength(13));
    expect(s.cellMv1, hasLength(13));
    expect(s.cellMv2, hasLength(13));
    expect(s.statusFlags, hasLength(13));
    expect(s.statusFlags, everyElement(0));
    expect(s.cellPpo2Bar, isEmpty);
    expect(s.tankPressuresBar, isEmpty);
  });

  test('metres, degrees, CNS fraction, deco time: next stop else NDL', () {
    final b = buildFit([
      _fileId(),
      _sport(63),
      _gas(0, 21, 0),
      _record(_start, 0, temp: 25, ndl: 999, cns: 0),
      _record(_start + 1, 12345, temp: 24, ndl: 600, cns: 4),
      _record(
        _start + 2,
        30000,
        temp: 18,
        stopDepthMm: 6000,
        stopTime: 120,
        ndl: 0,
        cns: 50,
      ),
      _record(_start + 3, 30000, stopDepthMm: 0, ndl: 5, cns: 51),
      _session(_start, _start + 3),
    ]);
    final s = _one(b).samples;
    expect(s.depthMeters[1], closeTo(12.345, 1e-4));
    expect(s.temperatureCelsius[1], 24);
    expect(s.cns[2], closeTo(0.5, 1e-6));
    expect(s.decoStopDepthMeters[2], closeTo(6.0, 1e-6));
    expect(s.decoTimeSeconds[2], 120);
    expect(s.decoStopDepthMeters[3], 0);
    expect(s.decoTimeSeconds[3], 5);
    expect(s.decoTimeSeconds[1], 600);
    expect(_one(b).dive.maxDepthMeters, closeTo(30.0, 1e-6));
  });

  test('setpoint switch alerts move the setpoint and add setpointChange '
      'events', () {
    final c = _one(
      _ccrFile(
        extraEvents: [
          _alert(_start + 3, 25),
          _alert(_start + 8, 26),
          _alert(_start + 10, 27),
        ],
      ),
    );
    final sp = c.samples.setpointBar;
    expect(sp[2], closeTo(0.7, 1e-6));
    expect(sp[3], closeTo(1.3, 1e-6));
    expect(sp[8], closeTo(0.7, 1e-6));
    expect(sp[10], closeTo(1.3, 1e-6));
    final ev = c.events.where((e) => e.type == DiveEventType.setpointChange);
    expect(ev.map((e) => (e.timeMs, e.rawType)), [
      (3000, 25),
      (8000, 26),
      (10000, 27),
    ]);
  });

  test('other alerts become events with their code as rawType', () {
    final c = _one(
      _ccrFile(
        extraEvents: [
          _alert(_start + 2, 9),
          _alert(_start + 4, 17),
          _alert(_start + 6, 0),
          _alert(_start + 7, 4),
        ],
      ),
    );
    final byRaw = {for (final e in c.events) e.rawType: e};
    expect(byRaw[9]!.type, DiveEventType.ceilingViolation);
    expect(byRaw[9]!.timeMs, 2000);
    expect(byRaw[17]!.type, DiveEventType.ascentWarning);
    expect(byRaw[0]!.type, DiveEventType.decoWarning);
    expect(byRaw[4]!.type, DiveEventType.other);
  });

  test('gas switch events set the gas mix index and add gasSwitch events', () {
    final c = _one(
      _ccrFile(extraEvents: [_gasSwitch(_start + 4, 2), _gasSwitch(_start + 9, 1)]),
    );
    final g = c.samples.gasMixIndex;
    expect(g[0], 0);
    expect(g[3], 0);
    expect(g[4], 2);
    expect(g[8], 2);
    expect(g[9], 1);
    expect(g[12], 1);
    final ev = c.events.where((e) => e.type == DiveEventType.gasSwitch);
    expect(ev.map((e) => (e.timeMs, e.value)), [(4000, 2), (9000, 1)]);
  });

  test('two tank transmitters give two tanks and two pressure channels', () {
    final b = buildFit([
      _fileId(),
      _sport(54),
      _gas(0, 21, 0),
      _sensor(111, name: 'Back gas'),
      _sensor(222, name: '        '), // same width: one definition
      _record(_start, 0),
      _tank(_start, 111, 20000),
      _tank(_start, 222, 19000),
      _record(_start + 1, 1000),
      _record(_start + 2, 2000),
      _tank(_start + 2, 111, 19500),
      _record(_start + 3, 3000),
      _session(_start, _start + 3, sub: 54),
    ]);
    final c = _one(b);
    expect(c.dive.diveMode, DiveMode.ocTec);
    expect(c.dive.tanks, hasLength(2));
    expect(c.dive.tanks[0].slot, 0);
    expect(c.dive.tanks[0].serial, 111);
    expect(c.dive.tanks[0].name, 'Back gas');
    expect(c.dive.tanks[1].slot, 1);
    expect(c.dive.tanks[1].serial, 222);
    expect(c.dive.tanks[1].name, 'T2');
    expect(c.dive.tanks[0].usage, TankUsage.none);
    expect(c.dive.tanks[0].beginPressureBar, closeTo(200, 1e-6));
    expect(c.dive.tanks[0].endPressureBar, closeTo(195, 1e-6));
    final p = c.samples.tankPressuresBar;
    expect(p, hasLength(2));
    expect(p[0], hasLength(4));
    expect(p[0][0], closeTo(200, 1e-4));
    expect(p[0][1], closeTo(200, 1e-4));
    expect(p[0][2], closeTo(195, 1e-4));
    expect(p[0][3], closeTo(195, 1e-4));
    expect(p[1][3], closeTo(190, 1e-4));
  });

  test('irregular records resample to the most common gap, carrying values '
      'forward', () {
    final b = buildFit([
      _fileId(),
      _sport(53),
      _gas(0, 32, 0),
      _record(_start + 0, 1000),
      _record(_start + 2, 2000),
      _record(_start + 4, 3000),
      _record(_start + 6, 4000),
      _record(_start + 9, 5000),
      _session(_start, _start + 9, sub: 53),
    ]);
    final c = _one(b);
    expect(c.dive.sampleIntervalMs, 2000);
    expect(c.samples.sampleIntervalMs, 2000);
    expect(c.samples.sampleCount, 6);
    expect(
      [for (final v in c.samples.depthMeters) v.round()],
      [1, 2, 3, 4, 4, 5],
    );
    expect(c.dive.duration, const Duration(seconds: 10));
    expect(c.dive.endTime.difference(c.dive.startTime), c.dive.duration);
    expect(c.dive.maxDepthMeters, closeTo(5, 1e-6));
  });

  test('start time is wall clock: session start + offset, stored as UTC; '
      'offset in utcOffsetMinutes', () {
    final b = buildFit([
      _fileId(),
      _sport(63),
      _gas(0, 21, 0),
      _record(_start, 0),
      _record(_start + 1, 100),
      _m(34, {253: (_u32, _start + 1), 5: (_u32, _start + 1 + 780 * 60)}),
      _session(_start, _start + 1),
    ]);
    final d = _one(b).dive;
    final unixUtc = _start + 631065600;
    expect(
      d.startTime,
      DateTime.fromMillisecondsSinceEpoch(
        (unixUtc + 780 * 60) * 1000,
        isUtc: true,
      ),
    );
    expect(d.startTime.isUtc, isTrue);
    expect(d.utcOffsetMinutes, 780);
  });

  test('no offset in the file keeps the UTC time and a null offset', () {
    final d = _one(_ccrFile()).dive;
    expect(
      d.startTime,
      DateTime.fromMillisecondsSinceEpoch(
        (_start + 631065600) * 1000,
        isUtc: true,
      ),
    );
    expect(d.utcOffsetMinutes, isNull);
  });

  test('no dive number gives 0, and two short dives one minute apart get '
      'different ids and fingerprints', () {
    final b = buildFit([
      _fileId(),
      _sport(63),
      _gas(0, 21, 0),
      _record(_start, 0),
      _record(_start + 5, 500),
      _session(_start, _start + 5),
      _record(_start + 60, 0),
      _record(_start + 65, 500),
      _session(_start + 60, _start + 65),
    ]);
    final r = mapFitFile(b);
    expect(r, hasLength(2));
    expect(r[0].dive.dcDiveNumber, 0);
    expect(r[1].dive.dcDiveNumber, 0);
    expect(r[0].dive.id, isNot(r[1].dive.id));
    expect(
      r[0].dive.id,
      fitDiveId(manufacturer: 1, serial: 1000000001, timeCreated: 1061159483),
    );
    expect(
      r[1].dive.id,
      fitDiveId(
        manufacturer: 1,
        serial: 1000000001,
        timeCreated: 1061159483,
        session: 1,
      ),
    );
    expect(r[1].samples.diveId, r[1].dive.id);
    expect(
      fitFingerprintHex(serial: 1000000001, timeCreated: 1061159483),
      isNot(
        fitFingerprintHex(
          serial: 1000000001,
          timeCreated: 1061159483,
          session: 1,
        ),
      ),
    );
  });

  test('the fixtures keep their dive ids; these literals must never change',
      () {
    // Ids are frozen at first import. If one of these fails, the code is
    // wrong: bumping kFitParserVersion is never the fix for an id change.
    String idOf(String name) => mapFitFile(
      File('test/fixtures/$name').readAsBytesSync(),
    ).single.dive.id;
    expect(idOf('garmin_mk1_ccr_2023-08-17.fit'), '492ce7c10e6586790d49bb164517095a');
    expect(idOf('garmin_mk1_ccr_2023-10-21.fit'), 'be28c41bb2acadc7d193435cd8ce2e8d');
    expect(idOf('suunto_ocean_nitrox.fit'), '6b5b5e41a4da9ee6c5c7b43450b46df5');
  });

  test('brand fields: Garmin, Descent Mk1, family -1, model code 2859, '
      'dcModel unknown', () {
    final d = _one(_ccrFile()).dive;
    expect(d.dcVendor, 'Garmin');
    expect(d.dcProduct, 'Descent Mk1');
    expect(d.dcFamily, kFitDcFamily);
    expect(d.dcFamily, -1);
    expect(d.dcModelCode, 2859);
    expect(d.dcModel, ShearwaterModel.unknown);
    expect(d.dcSerial, 1000000001);
  });

  test('Suunto Ocean product name maps to vendor Suunto, product Ocean', () {
    final b = buildFit([
      _fileId(
        manufacturer: 23,
        product: null,
        serial: null,
        productName: 'Suunto Ocean',
      ),
      _sport(53),
      _gas(0, 32, 0),
      _record(_start, 0),
      _record(_start + 1, 100),
      _session(_start, _start + 1, sub: 53),
    ]);
    final d = _one(b).dive;
    expect(d.dcVendor, 'Suunto');
    expect(d.dcProduct, 'Ocean');
    expect(d.dcSerial, 0);
    expect(d.diveMode, DiveMode.ocTec);
    expect(fitVendorName(23), 'Suunto');
    expect(fitVendorName(99), 'FIT manufacturer 99');
    expect(
      fitProductName(
        manufacturer: 23,
        productName: 'Suunto Ocean',
      ),
      'Ocean',
    );
  });

  test('an unknown Garmin product id gives "Garmin product 9999"', () {
    expect(fitProductName(manufacturer: 1, product: 9999), 'Garmin product 9999');
    expect(fitProductName(manufacturer: 99, product: 7), 'product 7');
    expect(fitProductName(manufacturer: 1, product: 4588), 'Descent G2');
    expect(fitProductName(manufacturer: 1, product: 3702), 'Descent Mk2/Mk2i');
    expect(fitProductName(manufacturer: 1, product: 4776), 'fēnix 8');
    final b = buildFit([
      _fileId(product: 9999),
      _sport(63),
      _record(_start, 0),
      _record(_start + 1, 100),
      _session(_start, _start + 1),
    ]);
    expect(_one(b).dive.dcProduct, 'Garmin product 9999');
  });

  test('a disabled gas is left out; a backup-only gas is kept', () {
    final b = buildFit([
      _fileId(),
      _sport(53),
      _gas(0, 21, 0),
      _gas(1, 50, 0, status: 0),
      _gas(2, 100, 0, status: 2),
      _record(_start, 0),
      _record(_start + 1, 100),
      _gasSwitch(_start + 1, 2),
      _session(_start, _start + 1, sub: 53),
    ]);
    final c = _one(b);
    expect(c.dive.gasMixes.map((g) => g.oxygenPercent), [21, 100]);
    expect(c.samples.gasMixIndex[1], 1, reason: 'gas message 2 is mix 1');
  });

  test('gauge and no sub-sport modes', () {
    for (final (sub, mode) in [
      (55, DiveMode.gauge),
      (53, DiveMode.ocTec),
      (54, DiveMode.ocTec),
    ]) {
      final b = buildFit([
        _fileId(),
        _sport(sub),
        _record(_start, 0),
        _record(_start + 1, 100),
        _session(_start, _start + 1, sub: sub),
      ]);
      expect(_one(b).dive.diveMode, mode);
    }
  });

  test('water density falls back on the water type', () {
    for (final (type, want) in [(0, 1000), (1, 1025)]) {
      final b = buildFit([
        _fileId(),
        _sport(53),
        _settings(density: null, waterType: type),
        _record(_start, 0),
        _record(_start + 1, 100),
        _session(_start, _start + 1, sub: 53),
      ]);
      expect(_one(b).dive.waterDensityKgM3, want);
    }
  });

  test('samples before the first temperature, CNS or tank reading take it', () {
    // 0x7F and 0xFF are the invalid markers of sint8 and uint8, which read
    // as absent: the first temperature and CNS arrive at t=10 s.
    final b = buildFit([
      _fileId(),
      _sport(53),
      _gas(0, 21, 0),
      _sensor(111, name: 'Back gas'),
      for (var i = 0; i < 10; i++)
        _record(_start + i, i * 1000, temp: 0x7F, cns: 0xFF),
      _record(_start + 10, 10000, temp: 17, cns: 9),
      _record(_start + 11, 11000, temp: 16, cns: 10),
      _tank(_start + 10, 111, 15000),
      _tank(_start + 11, 111, 14900),
      _session(_start, _start + 11, sub: 53),
    ]);
    final s = _one(b).samples;
    for (var i = 0; i <= 10; i++) {
      expect(s.temperatureCelsius[i], 17, reason: 'sample $i');
      expect(s.cns[i], closeTo(0.09, 1e-6), reason: 'sample $i');
      expect(s.tankPressuresBar[0][i], closeTo(150, 1e-4), reason: 'sample $i');
    }
    expect(s.temperatureCelsius[11], 16);
    expect(s.tankPressuresBar[0][11], closeTo(149, 1e-4));
    expect(s.depthMeters[0], 0);
    expect(s.depthMeters[5], 5);
  });

  test('surface pressure is the earliest shallowest record within 0.5 m '
      'that has an ambient pressure, else 1013', () {
    FitMessageSpec rec(int i, int mm, int pa) => _m(20, {
      253: (_u32, _start + i),
      92: (_u32, mm),
      91: (_u32, pa),
    });
    final b = buildFit([
      _fileId(),
      _sport(53),
      rec(0, 2000, 150000), // too deep to count
      rec(1, 400, 105000),
      rec(2, 0, 101960),
      rec(3, 0, 100000), // later, same depth
      _session(_start, _start + 3, sub: 53),
    ]);
    expect(_one(b).dive.atmosphericPressureMbar, 1020);
    expect(_one(_ccrFile()).dive.atmosphericPressureMbar, 1013);
  });

  test('events keep file order within a second, and the trace follows it', () {
    // 45 setpoint alerts; every group of 5 shares a timestamp and alternates
    // low/high, so an unstable sort would scramble them.
    final evs = <FitMessageSpec>[];
    for (var i = 0; i < 45; i++) {
      evs.add(_alert(_start + 1 + i ~/ 5, i.isEven ? 25 : 24));
    }
    final c = _one(buildFit([
      _fileId(),
      _sport(63),
      _gas(0, 21, 0),
      _settings(lowSp: 70, highSp: 130),
      for (var i = 0; i <= 12; i++) _record(_start + i, i * 1000),
      ...evs,
      _session(_start, _start + 12),
    ]));
    expect(c.events.map((e) => e.rawType).toList(), [
      for (var i = 0; i < 45; i++) i.isEven ? 25 : 24,
    ]);
    // Group at t=9 s is i = 40..44: high, low, high, low, high -> ends high.
    expect(c.samples.setpointBar[9], closeTo(1.3, 1e-6));
    // Group at t=8 s is i = 35..39: low, high, low, high, low -> ends low.
    expect(c.samples.setpointBar[8], closeTo(0.7, 1e-6));
  });

  test('an alert code above 65535 is dropped', () {
    final c = _one(_ccrFile(extraEvents: [
      _alert(_start + 2, 70000),
      _alert(_start + 3, 9),
    ]));
    expect(c.events.map((e) => e.rawType), [9]);
  });

  test('a session without records still maps, with no samples', () {
    final b = buildFit([_fileId(), _sport(63), _session(_start, _start + 30)]);
    final c = _one(b);
    expect(c.samples.sampleCount, 0);
    expect(c.dive.duration, const Duration(seconds: 30));
    expect(c.dive.maxDepthMeters, 0);
  });
}
