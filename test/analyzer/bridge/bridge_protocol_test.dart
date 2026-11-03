import 'package:ccrlogger/analyzer/bridge/bridge_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

const _hello =
    'HELLO proto=1 fw=0.1.0 bridge=a1b2c3d4e5f6 epoch=1a2b3c4d '
    'boot=3 up=120000 solo=1 rec=on vbus=off batt=3912 pending=2';

const _solo =
    'He   0.5 %  O2  19.8 %  Ti  22.0 ~C  1029.5 hPa   2026/11/03 15:21:00';

void main() {
  group('parseBridgeMessage', () {
    test('parses HELLO', () {
      final m = parseBridgeMessage(_hello) as BridgeHello;
      expect(
        (
          m.proto,
          m.fw,
          m.bridgeId,
          m.epoch,
          m.boot,
          m.upMs,
          m.soloAttached,
          m.recording,
          m.vbusOn,
          m.batteryMv,
          m.pending,
        ),
        (
          1,
          '0.1.0',
          'a1b2c3d4e5f6',
          '1a2b3c4d',
          3,
          120000,
          true,
          true,
          false,
          3912,
          2,
        ),
      );
    });

    test('HELLO reads rec=off and vbus=on', () {
      final m =
          parseBridgeMessage(
                'HELLO proto=1 fw=0.1.0 bridge=a1b2c3d4e5f6 epoch=1a2b3c4d '
                'boot=3 up=1 solo=0 rec=off vbus=on batt=3000 pending=0',
              )
              as BridgeHello;
      expect((m.soloAttached, m.recording, m.vbusOn), (false, false, true));
    });

    test('parses ST', () {
      final m =
          parseBridgeMessage('ST solo=1 data=0 pending=0 batt=3800 up=5000')
              as BridgeStatus;
      expect(
        (m.soloAttached, m.dataFlowing, m.pending, m.batteryMv, m.upMs),
        (true, false, 0, 3800, 5000),
      );
    });

    test('L, W and H keep the SOLO line byte for byte', () {
      expect((parseBridgeMessage('L $_solo') as BridgeLiveLine).line, _solo);
      final w = parseBridgeMessage('W -2000 $_solo') as BridgeWindowLine;
      expect((w.offsetMs, w.line), (-2000, _solo));
      expect(
        (parseBridgeMessage('H He ***.* %  O2  19.8 %') as BridgeHeldLine).line,
        'He ***.* %  O2  19.8 %',
      );
    });

    test('W accepts offset 0', () {
      final w = parseBridgeMessage('W 0 $_solo') as BridgeWindowLine;
      expect((w.offsetMs, w.line), (0, _solo));
    });

    test('parses REC and END', () {
      final r =
          parseBridgeMessage('REC 1a2b3c4d-7 boot=3 up=99000 wall=0 live=1')
              as BridgeRecordStart;
      expect(
        (r.rid, r.boot, r.upMs, r.wallMs, r.live),
        ('1a2b3c4d-7', 3, 99000, 0, true),
      );
      final wall =
          parseBridgeMessage(
                'REC 1a2b3c4d-8 boot=3 up=99000 wall=1762182000000 live=0',
              )
              as BridgeRecordStart;
      expect((wall.wallMs, wall.live), (1762182000000, false));
      expect(
        (parseBridgeMessage('END 1a2b3c4d-7') as BridgeRecordEnd).rid,
        '1a2b3c4d-7',
      );
    });

    test('a trailing CR or LF is not part of the message', () {
      expect((parseBridgeMessage('END r1\r\n') as BridgeRecordEnd).rid, 'r1');
      expect((parseBridgeMessage('L $_solo\n') as BridgeLiveLine).line, _solo);
    });

    test('unknown keys are ignored (forward compatibility)', () {
      final m = parseBridgeMessage('$_hello color=blue') as BridgeHello;
      expect(m.pending, 2);
      final s =
          parseBridgeMessage('ST solo=1 data=1 pending=0 batt=1 up=1 extra=9')
              as BridgeStatus;
      expect(s.dataFlowing, isTrue);
    });

    test('key order does not matter', () {
      final s =
          parseBridgeMessage('ST up=5000 batt=3800 pending=4 data=1 solo=0')
              as BridgeStatus;
      expect(
        (s.soloAttached, s.dataFlowing, s.pending, s.batteryMv, s.upMs),
        (false, true, 4, 3800, 5000),
      );
    });

    test('unknown or malformed input gives BridgeUnknown and never throws', () {
      for (final s in [
        '',
        ' ',
        'XYZ 1',
        'st solo=1 data=1 pending=0 batt=1 up=1',
        'ST solo=maybe data=1 pending=0 batt=1 up=1',
        'W notanumber x',
      ]) {
        expect(parseBridgeMessage(s), isA<BridgeUnknown>(), reason: s);
      }
    });

    test('BridgeUnknown keeps the raw line', () {
      expect((parseBridgeMessage('XYZ 1') as BridgeUnknown).raw, 'XYZ 1');
    });

    test('a missing required key gives BridgeUnknown', () {
      expect(
        parseBridgeMessage('ST solo=1 data=0 pending=0 batt=3800'),
        isA<BridgeUnknown>(),
      );
      expect(
        parseBridgeMessage(_hello.replaceFirst(' epoch=1a2b3c4d', '')),
        isA<BridgeUnknown>(),
      );
      expect(
        parseBridgeMessage('REC r1 boot=3 up=99000 live=1'),
        isA<BridgeUnknown>(),
      );
    });

    test('bad numbers give BridgeUnknown', () {
      for (final s in [
        'ST solo=1 data=0 pending=x batt=3800 up=5000',
        'ST solo=1 data=0 pending=-1 batt=3800 up=5000',
        'ST solo=1 data=0 pending=0x10 batt=3800 up=5000',
        'ST solo=1 data=0 pending= batt=3800 up=5000',
        'ST solo=1 data=0 pending=1.5 batt=3800 up=5000',
        'ST solo=1 data=0 pending=99999999999999999999 batt=3800 up=5000',
      ]) {
        expect(parseBridgeMessage(s), isA<BridgeUnknown>(), reason: s);
      }
    });

    test('booleans: 0/1 for solo, data and live; on/off for rec and vbus', () {
      expect(
        parseBridgeMessage('ST solo=on data=0 pending=0 batt=1 up=1'),
        isA<BridgeUnknown>(),
      );
      expect(
        parseBridgeMessage('ST solo=1 data=true pending=0 batt=1 up=1'),
        isA<BridgeUnknown>(),
      );
      expect(
        parseBridgeMessage('REC r1 boot=1 up=1 wall=0 live=on'),
        isA<BridgeUnknown>(),
      );
      expect(
        parseBridgeMessage(_hello.replaceFirst('rec=on', 'rec=1')),
        isA<BridgeUnknown>(),
      );
      expect(
        parseBridgeMessage(_hello.replaceFirst('vbus=off', 'vbus=0')),
        isA<BridgeUnknown>(),
      );
    });

    test('REC, END, L, H and W without their payload give BridgeUnknown', () {
      for (final s in [
        'REC',
        'REC boot=3 up=1 wall=0 live=1',
        'END',
        'END ',
        'L',
        'H',
        'W',
        'W -2000',
      ]) {
        expect(parseBridgeMessage(s), isA<BridgeUnknown>(), reason: s);
      }
    });

    test('an empty payload after the separator is kept as an empty line', () {
      expect((parseBridgeMessage('L ') as BridgeLiveLine).line, '');
      expect((parseBridgeMessage('H ') as BridgeHeldLine).line, '');
      final w = parseBridgeMessage('W -500 ') as BridgeWindowLine;
      expect((w.offsetMs, w.line), (-500, ''));
    });
  });

  group('app to bridge formatting', () {
    test('formats app messages', () {
      expect(
        formatTime(DateTime.fromMillisecondsSinceEpoch(1762182000000)),
        'TIME 1762182000000',
      );
      expect(formatLive(true), 'LIVE ON');
      expect(formatLive(false), 'LIVE OFF');
      expect(formatState(BridgeLiveState.sensorError), 'STATE sensor_error');
      expect(
        formatState(BridgeLiveState.stable, mix: 'Tx21/35'),
        'STATE stable Tx21/35',
      );
      expect(formatAck('1a2b3c4d-7'), 'ACK 1a2b3c4d-7');
      expect(
        formatFeedback('r1', FeedbackCode.skipped, 'AIR - NOT LOGGED'),
        'FB r1 skipped AIR - NOT LOGGED',
      );
      expect(
        formatConfig(recording: true, vbusOn: false),
        'CFG rec=on vbus=off',
      );
      expect(
        formatConfig(recording: false, vbusOn: true),
        'CFG rec=off vbus=on',
      );
    });

    test('STATE wire names', () {
      expect(formatState(BridgeLiveState.settling), 'STATE settling');
      expect(formatState(BridgeLiveState.stable), 'STATE stable');
      expect(formatState(BridgeLiveState.sensorError), 'STATE sensor_error');
      expect(formatState(BridgeLiveState.air), 'STATE air');
    });

    test('an empty mix is left out', () {
      expect(formatState(BridgeLiveState.settling, mix: ''), 'STATE settling');
    });

    test('FB code wire names are the lowercase enum names', () {
      expect(
        [for (final c in FeedbackCode.values) formatFeedback('r', c, 'T')],
        [
          'FB r printed T',
          'FB r saved T',
          'FB r check T',
          'FB r skipped T',
          'FB r error T',
        ],
      );
    });

    test('feedback text loses line breaks and is cut to 24 characters', () {
      expect(formatFeedback('r', FeedbackCode.check, 'A\nB'), 'FB r check A B');
      expect(
        formatFeedback('r', FeedbackCode.check, 'A\r\nB\rC'),
        'FB r check A B C',
      );
      expect(
        formatFeedback('r', FeedbackCode.check, 'X' * 30),
        'FB r check ${'X' * 24}',
      );
      expect(kFeedbackTextMax, 24);
    });

    test('formatted messages never contain a line break', () {
      expect(
        formatState(BridgeLiveState.stable, mix: 'a\nb'),
        'STATE stable a b',
      );
    });

    test('protocol version is 1', () {
      expect(kBridgeProtocolVersion, 1);
    });
  });

  group('BridgeRecordAssembler', () {
    BridgeRecord? feed(BridgeRecordAssembler a, List<String> lines) {
      BridgeRecord? last;
      for (final l in lines) {
        final r = a.add(parseBridgeMessage(l));
        if (r != null) last = r;
      }
      return last;
    }

    test('assembles REC, W lines, H and END into one record', () {
      final a = BridgeRecordAssembler();
      final rec = feed(a, [
        'REC r1 boot=3 up=99000 wall=1762182000000 live=1',
        'W -2000 w1',
        'W -1000 w2',
        'W 0 w3',
        'H held',
        'END r1',
      ]);
      expect(rec, isNotNull);
      expect(
        (rec!.rid, rec.boot, rec.upMs, rec.wallMs, rec.live, rec.heldLine),
        ('r1', 3, 99000, 1762182000000, true, 'held'),
      );
      expect(
        [for (final w in rec.window) (w.offsetMs, w.line)],
        [(-2000, 'w1'), (-1000, 'w2'), (0, 'w3')],
      );
    });

    test('END is the only message that returns a record', () {
      final a = BridgeRecordAssembler();
      for (final l in [
        'REC r1 boot=3 up=1 wall=0 live=0',
        'W -1000 w1',
        'H held',
      ]) {
        expect(a.add(parseBridgeMessage(l)), isNull, reason: l);
      }
      expect(a.add(parseBridgeMessage('END r1')), isNotNull);
    });

    test('the window may be empty', () {
      final a = BridgeRecordAssembler();
      final rec = feed(a, [
        'REC r1 boot=3 up=1 wall=0 live=0',
        'H held',
        'END r1',
      ]);
      expect(rec!.window, isEmpty);
      expect(rec.heldLine, 'held');
    });

    test('a second REC before END drops the partial record', () {
      final a = BridgeRecordAssembler();
      final rec = feed(a, [
        'REC r1 boot=3 up=1 wall=0 live=0',
        'W -2000 a1',
        'W -1000 a2',
        'REC r2 boot=3 up=2 wall=0 live=1',
        'W -500 b1',
        'H held2',
        'END r2',
      ]);
      expect(rec!.rid, 'r2');
      expect(rec.live, isTrue);
      expect(rec.heldLine, 'held2');
      expect([for (final w in rec.window) w.line], ['b1']);
    });

    test('END with another rid drops the record', () {
      final a = BridgeRecordAssembler();
      expect(
        feed(a, [
          'REC r1 boot=3 up=1 wall=0 live=0',
          'W -1000 a1',
          'H held',
          'END r2',
        ]),
        isNull,
      );
      // The partial record is gone: a later END r1 does not revive it.
      expect(a.add(parseBridgeMessage('END r1')), isNull);
    });

    test('END without H returns the record with an empty held line', () {
      final a = BridgeRecordAssembler();
      final rec = feed(a, [
        'REC r1 boot=3 up=1 wall=0 live=0',
        'W -2000 a1',
        'W -1000 a2',
        'END r1',
      ]);
      expect(rec, isNotNull);
      expect(rec!.rid, 'r1');
      expect(
        [for (final w in rec.window) (w.offsetMs, w.line)],
        [(-2000, 'a1'), (-1000, 'a2')],
      );
      expect(rec.heldLine, '');
    });

    test('an H line of an earlier record does not carry over', () {
      final a = BridgeRecordAssembler();
      feed(a, ['REC r1 boot=3 up=1 wall=0 live=0', 'H held1', 'END r1']);
      final rec = feed(a, ['REC r2 boot=3 up=2 wall=0 live=0', 'END r2']);
      expect(rec!.rid, 'r2');
      expect(rec.heldLine, '');
    });

    test('messages outside a record give null', () {
      final a = BridgeRecordAssembler();
      for (final l in [
        _hello,
        'ST solo=1 data=1 pending=0 batt=1 up=1',
        'L $_solo',
        'W -1000 stray',
        'H stray',
        'END r1',
        'garbage',
      ]) {
        expect(a.add(parseBridgeMessage(l)), isNull, reason: l);
      }
    });

    test('live lines and status inside a record do not disturb it', () {
      final a = BridgeRecordAssembler();
      final rec = feed(a, [
        'REC r1 boot=3 up=1 wall=0 live=1',
        'W -1000 w1',
        'L $_solo',
        'ST solo=1 data=1 pending=1 batt=3700 up=2',
        'H held',
        'END r1',
      ]);
      expect(rec!.rid, 'r1');
      expect([for (final w in rec.window) w.line], ['w1']);
    });

    test('stray lines before a REC do not leak into it', () {
      final a = BridgeRecordAssembler();
      final rec = feed(a, [
        'W -1000 stray',
        'H stray',
        'REC r1 boot=3 up=1 wall=0 live=0',
        'H held',
        'END r1',
      ]);
      expect(rec!.window, isEmpty);
      expect(rec.heldLine, 'held');
    });

    test('the assembler is reusable for the next record', () {
      final a = BridgeRecordAssembler();
      expect(
        feed(a, ['REC r1 boot=3 up=1 wall=0 live=0', 'H h1', 'END r1'])!.rid,
        'r1',
      );
      expect(
        feed(a, ['REC r2 boot=3 up=2 wall=0 live=0', 'H h2', 'END r2'])!.rid,
        'r2',
      );
    });

    test('the finished record is not affected by later messages', () {
      final a = BridgeRecordAssembler();
      final rec = feed(a, [
        'REC r1 boot=3 up=1 wall=0 live=0',
        'W -1000 w1',
        'H held',
        'END r1',
      ])!;
      a.add(parseBridgeMessage('W 0 late'));
      expect(rec.window, hasLength(1));
      expect(() => rec.window.add(rec.window.first), throwsUnsupportedError);
    });
  });
}
