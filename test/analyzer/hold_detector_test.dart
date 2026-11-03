import 'package:ccrlogger/analyzer/hold_detector.dart';
import 'package:flutter_test/flutter_test.dart';

import '../_helpers/solo_capture_log.dart';

/// A SOLO data line; [i] only varies the clock at the end.
String _data(int i, {double ti = 22.0}) =>
    'He   0.5 %  O2  19.8 %  Ti  ${ti.toStringAsFixed(1)} ~C  1029.5 hPa   '
    '2026/11/03 15:20:${(i % 60).toString().padLeft(2, '0')}';

Duration _ms(int ms) => Duration(milliseconds: ms);

/// Feeds a data line every [everyMs] from [fromMs] to [toMs] (both
/// included).
void _flow(
  HoldDetector d,
  int fromMs,
  int toMs, {
  int everyMs = 200,
  double ti = 22.0,
}) {
  for (var t = fromMs; t <= toMs; t += everyMs) {
    d.addLine(_ms(t), _data(t ~/ everyMs, ti: ti));
  }
}

/// Ticks every 100 ms from [fromMs] to [toMs] and collects the holds.
List<DetectedHold> _ticks(HoldDetector d, int fromMs, int toMs) => [
  for (var t = fromMs; t <= toMs; t += 100)
    ?d.tick(_ms(t)),
];

void main() {
  group('on the real captures', () {
    test('capture a: two holds, at the 28.7 s and the 7.9 s pause', () {
      final holds = replayCapture(
        readSoloCaptureLog(
          'test/fixtures/analyzer/solo_ok_presses_2026-11-03_a.txt',
        ),
        HoldDetector(),
      );
      expect(holds.map((h) => h.heldAt.inMilliseconds), [58357, 119677]);
      expect(holds[0].heldLine, contains('Ti  22.0'));
      expect(holds[1].heldLine, contains('Ti  22.2'));
      expect(holds[0].window.last.offsetMs, 0);
      expect(holds[0].window.first.offsetMs, greaterThanOrEqualTo(-30000));
    });

    test('capture b: quick double presses and the switch-off make no hold; '
        'the 20.9 s pause makes one', () {
      final holds = replayCapture(
        readSoloCaptureLog(
          'test/fixtures/analyzer/solo_ok_presses_2026-11-03_b.txt',
        ),
        HoldDetector(),
      );
      expect(holds.map((h) => h.heldAt.inMilliseconds), [17518]);
      expect(holds.single.heldLine, contains('Ti  22.5'));
    });

    test('the capture log knows when the USB cable went', () {
      final a = readSoloCaptureLog(
        'test/fixtures/analyzer/solo_ok_presses_2026-11-03_a.txt',
      );
      final b = readSoloCaptureLog(
        'test/fixtures/analyzer/solo_ok_presses_2026-11-03_b.txt',
      );
      expect(a.errors.map((e) => e.inMilliseconds), [143640]);
      expect(b.errors.map((e) => e.inMilliseconds), [40656]);
    });
  });

  group('arming', () {
    test('no hold before 5 s of flow', () {
      final d = HoldDetector();
      _flow(d, 0, 4800);
      expect(_ticks(d, 4800, 10000), isEmpty);
    });

    test('5 s of flow is enough for the first hold', () {
      final d = HoldDetector();
      _flow(d, 0, 5000);
      final holds = _ticks(d, 5000, 10000);
      expect(holds.map((h) => h.heldAt.inMilliseconds), [5000]);
    });

    test('after a hold, 3 s of flow arms the next one', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 13000), hasLength(1));
      // A resume with 2.8 s of flow: not enough.
      _flow(d, 20000, 22800);
      expect(_ticks(d, 22800, 29000), isEmpty);
      // Another resume with 3.2 s of flow: enough.
      _flow(d, 30000, 33200);
      final holds = _ticks(d, 33200, 40000);
      expect(holds.map((h) => h.heldAt.inMilliseconds), [33200]);
    });

    test('dips under 2 s do not reset arming', () {
      final d = HoldDetector();
      // 3 s, a 1.5 s dip, then 1.4 s more: 5.9 s from the first line to the
      // last, although neither run alone is 5 s.
      _flow(d, 0, 3000);
      expect(_ticks(d, 3000, 4500), isEmpty);
      _flow(d, 4500, 5900);
      final holds = _ticks(d, 5900, 9000);
      expect(holds.map((h) => h.heldAt.inMilliseconds), [5900]);
    });

    test('a silence of 2 s or more that did not fire restarts the flow', () {
      final d = HoldDetector();
      // 4.8 s of flow, then a 2.5 s silence that is too early to count.
      _flow(d, 0, 4800);
      expect(_ticks(d, 4800, 7300), isEmpty);
      // The line after it is a resume. 0.4 s of fresh flow is not 5 s, and the
      // 7.7 s since the very first line must not be counted.
      _flow(d, 7300, 7700);
      expect(_ticks(d, 7700, 11000), isEmpty);
      // After another silence, 5 s of flow from that resume arms the first
      // hold.
      _flow(d, 12000, 17000);
      final holds = _ticks(d, 17000, 20000);
      expect(holds.map((h) => h.heldAt.inMilliseconds), [17000]);
    });

    test('a short resume and a second silence is not 3 s of flow', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 13000), hasLength(1));
      // 1 s of flow after the resume, a 4 s silence that makes no hold, then
      // 1 s more: each run is short, and the silence between them is not flow.
      _flow(d, 20000, 21000);
      expect(_ticks(d, 21000, 25000), isEmpty);
      _flow(d, 26000, 27000);
      expect(_ticks(d, 27000, 32000), isEmpty);
    });

    test('non-data lines are not flow', () {
      final d = HoldDetector();
      for (var t = 0; t <= 10000; t += 200) {
        d.addLine(_ms(t), 'Divesoft SOLO');
      }
      expect(_ticks(d, 0, 20000), isEmpty);
    });

    test('non-data lines do not start the flow', () {
      final d = HoldDetector();
      // A banner at the start; the 4 s of data after it is the whole flow.
      d.addLine(_ms(0), 'Divesoft SOLO');
      _flow(d, 4000, 8000);
      expect(_ticks(d, 8000, 12000), isEmpty);
    });

    test('non-data lines do not make a resume', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 13000), hasLength(1));
      // A banner at 20 s is not the resume; the data line at 21 s is, so
      // 2.2 s of flow is short of 3 s.
      d.addLine(_ms(20000), 'Divesoft SOLO');
      _flow(d, 21000, 23200);
      expect(_ticks(d, 23200, 30000), isEmpty);
    });

    test('non-data lines do not shorten a silence', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      // Banner lines during the silence do not count as data.
      for (var t = 10200; t <= 11800; t += 200) {
        d.addLine(_ms(t), 'Divesoft SOLO');
      }
      final holds = _ticks(d, 10000, 12000);
      expect(holds.map((h) => h.heldAt.inMilliseconds), [10000]);
    });
  });

  group('firing', () {
    test('nothing before the first line', () {
      expect(_ticks(HoldDetector(), 0, 20000), isEmpty);
    });

    test('a hold needs 2 s of silence, to the millisecond', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(d.tick(_ms(11999)), isNull);
      final hold = d.tick(_ms(12000));
      expect(hold, isNotNull);
      expect(hold!.heldAt, _ms(10000));
    });

    test('one hold per silence', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      final holds = _ticks(d, 10000, 40000);
      expect(holds, hasLength(1));
      expect(holds.single.heldAt, _ms(10000));
    });

    test('the hold carries the last data line, as given', () {
      final d = HoldDetector();
      _flow(d, 0, 9800);
      const last =
          'He   0.5 %  O2  19.8 %  Ti  22.3 ~C  1029.5 hPa   2026/11/03 15:20:59';
      d.addLine(_ms(10000), last);
      expect(_ticks(d, 10000, 13000).single.heldLine, last);
    });

    test('lines after a hold start the next flow and re-arm it', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 13000), hasLength(1));
      // The resume, a full run of flow, and another silence.
      _flow(d, 20000, 30000);
      final holds = _ticks(d, 30000, 40000);
      expect(holds.map((h) => h.heldAt.inMilliseconds), [30000]);
    });

    test('thresholds can be overridden', () {
      final d = HoldDetector(
        silence: const Duration(seconds: 1),
        firstMinFlow: const Duration(seconds: 1),
        nextMinFlow: const Duration(milliseconds: 500),
        window: const Duration(seconds: 2),
      );
      _flow(d, 0, 2400);
      final first = _ticks(d, 2400, 4000);
      expect(first.map((h) => h.heldAt.inMilliseconds), [2400]);
      // The 2 s window keeps lines from -2000 ms up to the held line.
      expect(first.single.window.first.offsetMs, -2000);
      // 0.6 s of flow is enough after a hold with these thresholds.
      _flow(d, 5000, 5600);
      expect(_ticks(d, 5600, 8000).map((h) => h.heldAt.inMilliseconds), [
        5600,
      ]);
    });
  });

  group('the transport leaving', () {
    test('a detach before 2 s of silence cancels the hold', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 10900), isEmpty);
      d.detached();
      expect(_ticks(d, 11000, 15000), isEmpty);
    });

    test('a detach after a hold forgets the hold count and the flow', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 13000), hasLength(1));
      d.detached();
      // Back on the cable: the next hold is a first hold again, so 4.8 s of
      // flow is too little even though 3 s would do after a hold.
      _flow(d, 20000, 24800);
      expect(_ticks(d, 24800, 30000), isEmpty);
    });

    test('and after a detach, 5 s of flow arms the first hold again', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 13000), hasLength(1));
      d.detached();
      _flow(d, 20000, 25000);
      final holds = _ticks(d, 25000, 30000);
      expect(holds.map((h) => h.heldAt.inMilliseconds), [25000]);
    });

    test('a detach forgets the flow before it', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      d.detached();
      // One new line is not 5 s of flow, however long the old run was.
      d.addLine(_ms(20000), _data(0));
      expect(_ticks(d, 20000, 30000), isEmpty);
    });

    test('a detach forgets the window', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      d.detached();
      _flow(d, 20000, 26000);
      final hold = _ticks(d, 26000, 29000).single;
      // Only lines from after the detach: 6 s, 31 lines.
      expect(hold.window, hasLength(31));
      expect(hold.window.first.offsetMs, -6000);
    });
  });

  group('the window', () {
    test('holds the last 30 s of data lines, oldest first, ending at 0', () {
      final d = HoldDetector();
      _flow(d, 0, 60000);
      final hold = _ticks(d, 60000, 63000).single;
      expect(hold.heldAt, _ms(60000));
      final offsets = hold.window.map((w) => w.offsetMs).toList();
      expect(offsets.first, -30000);
      expect(offsets.last, 0);
      // 30 s at 200 ms, both ends included.
      expect(offsets, hasLength(151));
      expect(offsets, orderedEquals([...offsets]..sort()));
      expect(hold.window.last.line, hold.heldLine);
    });

    test('is trimmed as lines arrive, so a long flow stays bounded', () {
      final d = HoldDetector();
      // 20 minutes of lines, 5 per second.
      _flow(d, 0, 1200000);
      final hold = _ticks(d, 1200000, 1203000).single;
      expect(hold.window, hasLength(151));
      expect(hold.window.first.offsetMs, -30000);
    });

    test('a shorter flow gives a shorter window', () {
      final d = HoldDetector();
      _flow(d, 0, 6000);
      final hold = _ticks(d, 6000, 9000).single;
      expect(hold.window.first.offsetMs, -6000);
      expect(hold.window, hasLength(31));
    });

    test('keeps only data lines', () {
      final d = HoldDetector();
      for (var t = 0; t <= 6000; t += 200) {
        d.addLine(_ms(t), _data(t ~/ 200));
        d.addLine(_ms(t), 'Divesoft SOLO');
      }
      final hold = _ticks(d, 6000, 9000).single;
      expect(hold.window, hasLength(31));
      expect(hold.window.every((w) => w.line.contains('O2')), isTrue);
    });

    test('a hold window starts at the resume', () {
      final d = HoldDetector();
      // The first cylinder: 10 s of Ti 22.0, then a hold.
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 12000), hasLength(1));
      // The second: 25 s of Ti 22.5 from the resume at 12.2 s, then a hold.
      // The first cylinder's lines are still inside the last 30 s of time, so
      // only the resume keeps them out.
      _flow(d, 12200, 37200, ti: 22.5);
      final hold = _ticks(d, 37200, 40000).single;
      expect(hold.heldAt, _ms(37200));
      // The first line after the resume, not a line from before the first
      // hold, and nothing but the second cylinder's lines.
      expect(hold.window.first.offsetMs, -25000);
      expect(hold.window, hasLength(126));
      expect(hold.window.every((w) => w.line.contains('Ti  22.5')), isTrue);
    });

    test('a window that outgrew the resume is still capped at 30 s', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      expect(_ticks(d, 10000, 13000), hasLength(1));
      _flow(d, 20000, 70000, ti: 22.5);
      final hold = _ticks(d, 70000, 73000).single;
      expect(hold.window.first.offsetMs, -30000);
      expect(hold.window, hasLength(151));
      expect(hold.window.every((w) => w.line.contains('Ti  22.5')), isTrue);
    });

    test('a silence that made no hold also cuts the window', () {
      final d = HoldDetector();
      // 4 s of Ti 22.0, then 2.5 s of silence: not armed, so no hold.
      _flow(d, 0, 4000);
      expect(_ticks(d, 4000, 6500), isEmpty);
      // The line after the silence is a resume, so the hold's window holds
      // the 8 s since then and none of the 4 s before.
      _flow(d, 6500, 14500, ti: 22.5);
      final hold = _ticks(d, 14500, 17500).single;
      expect(hold.heldAt, _ms(14500));
      expect(hold.window.first.offsetMs, -8000);
      expect(hold.window, hasLength(41));
      expect(hold.window.every((w) => w.line.contains('Ti  22.5')), isTrue);
    });

    test('the lines of one hold are not changed by the next', () {
      final d = HoldDetector();
      _flow(d, 0, 10000);
      final first = _ticks(d, 10000, 13000).single;
      List<(int, String)> snapshot() => [
        for (final w in first.window) (w.offsetMs, w.line),
      ];
      final before = snapshot();
      expect(before, hasLength(51));
      _flow(d, 20000, 30000, ti: 22.5);
      final second = _ticks(d, 30000, 33000).single;
      expect(snapshot(), before);
      // And the second starts at its own resume.
      expect(second.window.first.offsetMs, -10000);
      expect(second.window, hasLength(51));
    });
  });
}
