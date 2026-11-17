import 'dart:typed_data';

import 'package:fit_reader/fit_reader.dart';
import 'package:test/test.dart';

import 'support/fit_writer.dart';

const _enumT = 0x00, _u8 = 0x02, _u16 = 0x84, _u32 = 0x86;
const _str = 0x07, _u32z = 0x8C;

FitMessageSpec _m(int g, Map<int, (int, Object)> f) => FitMessageSpec(g, f);

FitMessageSpec _fileId({int type = 4, int? serial = 1234}) => _m(0, {
  0: (_enumT, type),
  1: (_u16, 1),
  2: (_u16, 2859),
  if (serial != null) 3: (_u32z, serial),
  4: (_u32, 1000),
});

FitMessageSpec _sport(int sport, [int? sub]) =>
    _m(12, {0: (_enumT, sport), if (sub != null) 1: (_enumT, sub)});

FitMessageSpec _session(int start, int endTs, {int sport = 53, int? sub}) =>
    _m(18, {
      253: (_u32, endTs),
      2: (_u32, start),
      5: (_enumT, sport),
      6: (_enumT, sub ?? 0),
      7: (_u32, (endTs - start) * 1000),
    });

FitMessageSpec _record(int ts, int depthMm) =>
    _m(20, {253: (_u32, ts), 92: (_u32, depthMm)});

FitMessageSpec _summary(int ts, int ref, {int? diveNumber, int? maxDepth}) =>
    _m(268, {
      253: (_u32, ts),
      0: (_u16, ref),
      3: (_u32, maxDepth ?? 0),
      10: (_u32, diveNumber ?? 0),
    });

void main() {
  group('classifyFit', () {
    test('a CCR dive file classifies as dive', () {
      final b = buildFit([_fileId(), _sport(53, 63), _session(100, 200)]);
      expect(classifyFit(b), FitFileKind.dive);
    });

    test('a diving file with no sub-sport classifies as dive', () {
      expect(classifyFit(buildFit([_fileId(), _sport(53)])), FitFileKind.dive);
    });

    test('without a sport message the first session decides', () {
      expect(
        classifyFit(buildFit([_fileId(), _session(100, 200, sub: 54)])),
        FitFileKind.dive,
      );
      expect(
        classifyFit(buildFit([_fileId(), _session(100, 200, sport: 1)])),
        FitFileKind.otherActivity,
      );
    });

    test('apnea and apnea-hunt files classify as apnea', () {
      for (final sub in [56, 57]) {
        expect(
          classifyFit(buildFit([_fileId(), _sport(53, sub)])),
          FitFileKind.apnea,
        );
      }
    });

    test('a running activity classifies as otherActivity, and decoding '
        'stopped at its sport message', () {
      // The CRC is wrong and the tail is garbage: only an early stop can
      // classify this without throwing, where decodeFit would throw.
      final b = buildFit([
        _fileId(),
        _sport(1, 0),
        _record(100, 5),
      ], badCrc: true);
      expect(() => decodeFit(b), throwsA(isA<FitFormatException>()));
      expect(classifyFit(b), FitFileKind.otherActivity);
    });

    test('a settings file (file id type 2) is notActivity', () {
      expect(
        classifyFit(buildFit([_fileId(type: 2), _sport(53, 63)])),
        FitFileKind.notActivity,
      );
    });

    test('an unreadable file throws FitFormatException', () {
      expect(
        () => classifyFit(Uint8List.fromList([1, 2, 3])),
        throwsA(isA<FitFormatException>()),
      );
    });
  });

  group('readFitDives', () {
    test('one session with its records, events, gases and summary', () {
      final b = buildFit([
        _fileId(),
        _m(23, {253: (_u32, 100), 0: (_u8, 1), 3: (_u32z, 0), 5: (_u16, 999)}),
        _m(23, {
          253: (_u32, 100),
          0: (_u8, 0),
          3: (_u32z, 1234),
          5: (_u16, 1600),
        }),
        _sport(53, 63),
        _m(258, {2: (_u8, 50), 3: (_u8, 70)}),
        _m(259, {254: (_u16, 0), 0: (_u8, 20), 1: (_u8, 18), 3: (_u8, 1)}),
        _m(259, {254: (_u16, 1), 0: (_u8, 0), 1: (_u8, 50), 3: (_u8, 0)}),
        _record(100, 0),
        _record(101, 1500),
        _m(21, {253: (_u32, 101), 0: (_u8, 57), 1: (_u8, 3), 3: (_u32, 1)}),
        _m(319, {253: (_u32, 101), 0: (_u32z, 77), 1: (_u16, 20000)}),
        _m(147, {0: (_u32z, 77), 52: (_u8, 28)}),
        _m(323, {253: (_u32, 200), 0: (_u32z, 77), 1: (_u16, 20000)}),
        _summary(200, 19, maxDepth: 1111),
        _summary(200, 18, diveNumber: 11, maxDepth: 51765),
        _session(100, 200, sub: 63),
      ]);
      final f = readFitDives(b);
      expect(f.id.serial, 1234);
      expect(f.id.manufacturer, 1);
      expect(f.id.product, 2859);
      expect(f.id.timeCreated, 1000);
      expect(f.sessions, hasLength(1));
      final s = f.sessions.single;
      expect(s.fileSessionIndex, 0);
      expect(s.start, 100);
      expect(s.end, 200);
      expect(s.subSport, 63);
      expect(s.diveNumber, 11);
      expect(s.maxDepthMm, 51765);
      expect(s.firmware, 1600);
      expect(s.records, hasLength(2));
      expect(s.events, hasLength(1));
      expect(s.tankUpdates, hasLength(1));
      expect(s.diveGases, hasLength(2));
      expect(s.sensorProfiles, hasLength(1));
      expect(s.tankSummaries, hasLength(1));
      expect(s.diveSettings?.intField(FitDiveSettings.gfLow), 50);
      expect(s.offsetMinutes, isNull);
    });

    test('two dive sessions in one file split records by time span', () {
      final b = buildFit([
        _fileId(),
        _m(258, {2: (_u8, 40)}),
        _m(259, {254: (_u16, 0), 0: (_u8, 0), 1: (_u8, 21)}),
        _record(100, 1),
        _record(150, 2),
        _m(21, {253: (_u32, 160), 0: (_u8, 56), 3: (_u32, 24)}),
        _session(100, 200),
        _record(300, 3),
        _m(21, {253: (_u32, 310), 0: (_u8, 56), 3: (_u32, 25)}),
        _m(259, {254: (_u16, 0), 0: (_u8, 0), 1: (_u8, 32)}),
        _session(300, 400),
      ]);
      final s = readFitDives(b).sessions;
      expect(s, hasLength(2));
      expect([for (final r in s[0].records) r.timestamp], [100, 150]);
      expect([for (final r in s[1].records) r.timestamp], [300]);
      expect(s[0].events.single.timestamp, 160);
      expect(s[1].events.single.timestamp, 310);
      // Untimed messages go by position: the later gas belongs to session 1
      // only, while session 1 inherits the settings from before session 0.
      expect(s[0].diveGases.single.intField(FitDiveGas.oxygen), 21);
      expect(s[1].diveGases.single.intField(FitDiveGas.oxygen), 32);
      expect(s[1].diveSettings?.intField(FitDiveSettings.gfLow), 40);
      expect([s[0].fileSessionIndex, s[1].fileSessionIndex], [0, 1]);
    });

    test('apnea sessions are left out but still count for the index', () {
      final b = buildFit([
        _fileId(),
        _record(100, 1),
        _session(100, 200, sub: 56),
        _record(300, 2),
        _session(300, 400, sub: 54),
        _record(500, 3),
        _session(500, 600, sport: 1),
      ]);
      final s = readFitDives(b).sessions;
      expect(s, hasLength(1));
      expect(s.single.fileSessionIndex, 1);
      expect(s.single.records.single.timestamp, 300);
    });

    test('the local offset comes from the activity; without it from '
        'device settings; else null', () {
      FitMessageSpec activity() =>
          _m(34, {253: (_u32, 200), 5: (_u32, 200 + 3600 * 13)});
      FitMessageSpec settings(int off) => _m(2, {1: (_u32, 0), 2: (_u32, off)});
      final base = [_fileId(), _record(100, 1), _session(100, 200)];

      var s = readFitDives(
        buildFit([settings(3600), ...base, activity()]),
      ).sessions.single;
      expect(s.offsetMinutes, 13 * 60);

      s = readFitDives(buildFit([settings(3600), ...base])).sessions.single;
      expect(s.offsetMinutes, 60);

      // A negative offset is stored as unsigned 32 bit.
      s = readFitDives(
        buildFit([settings(0x100000000 - 5 * 3600), ...base]),
      ).sessions.single;
      expect(s.offsetMinutes, -300);

      // A zero offset in device settings means "unknown".
      s = readFitDives(buildFit([settings(0), ...base])).sessions.single;
      expect(s.offsetMinutes, isNull);

      s = readFitDives(buildFit(base)).sessions.single;
      expect(s.offsetMinutes, isNull);
    });

    test('a missing serial reads as 0, a product name is kept', () {
      final id = readFitDives(
        buildFit([
          _m(0, {0: (_enumT, 4), 1: (_u16, 23), 4: (_u32, 5), 8: (_str, 'X')}),
          _session(100, 200),
        ]),
      ).id;
      expect(id.serial, 0);
      expect(id.product, isNull);
      expect(id.productName, 'X');
    });

    test('the CRC is checked', () {
      expect(
        () => readFitDives(buildFit([_fileId(), _session(1, 2)], badCrc: true)),
        throwsA(isA<FitFormatException>()),
      );
    });

    test('a file with no sessions reads as no dives', () {
      expect(readFitDives(buildFit([_fileId()])).sessions, isEmpty);
    });
  });
}
