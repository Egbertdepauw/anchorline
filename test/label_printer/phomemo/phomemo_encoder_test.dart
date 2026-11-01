import 'dart:typed_data';

import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/label_printer/phomemo/phomemo_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// 384 x 2: the first row all black, the second row all white.
LabelBitmap _twoRowBitmap() {
  final bits = Uint8List(96)..fillRange(0, 48, 0xFF);
  return LabelBitmap(width: 384, height: 2, bits: bits);
}

const _header = <int>[
  0x1B, 0x4E, 0x0D, 0x05, // speed 5
  0x1B, 0x4E, 0x04, 0x0A, // density 10
  0x1F, 0x11, 0x0A, // media: gap label
];

const _footer = <int>[0x1F, 0xF0, 0x05, 0x00, 0x1F, 0xF0, 0x03, 0x00];

Uint8List _concat(Iterable<Uint8List> parts) =>
    Uint8List.fromList([for (final p in parts) ...p]);

/// Indices at which [a] and [b] (same length) differ.
List<int> _diff(Uint8List a, Uint8List b) => [
  for (var i = 0; i < a.length; i++)
    if (a[i] != b[i]) i,
];

void main() {
  group('encodePhomemoM110Job', () {
    test('384 x 2 is header, raster header, 96 raster bytes, footer', () {
      final job = encodePhomemoM110Job(_twoRowBitmap());

      expect(job.length, 123);
      expect(job.sublist(0, 19), [
        ..._header,
        0x1D, 0x76, 0x30, 0x00, 0x30, 0x00, 0x02, 0x00, // 48 bytes x 2 rows
      ]);
      expect(job.sublist(19, 67), everyElement(0xFF));
      expect(job.sublist(67, 115), everyElement(0x00));
      expect(job.sublist(115), _footer);
    });

    test('blank 384 x 240 is 11547 bytes with 30 00 F0 00 as the size', () {
      final job = encodePhomemoM110Job(LabelBitmap.blank(384, 240));

      expect(job.length, 11547);
      expect(job.sublist(11, 19), [
        0x1D, 0x76, 0x30, 0x00, 0x30, 0x00, 0xF0, 0x00, //
      ]);
      expect(job.sublist(19, 19 + 11520), everyElement(0x00));
      expect(job.sublist(11539), _footer);
    });

    test('copies: 2 is the single job twice', () {
      final single = encodePhomemoM110Job(_twoRowBitmap());
      final double = encodePhomemoM110Job(_twoRowBitmap(), copies: 2);

      expect(double.length, 246);
      expect(double, [...single, ...single]);
    });

    test('copies is clamped to 1-9', () {
      final single = encodePhomemoM110Job(_twoRowBitmap());

      expect(encodePhomemoM110Job(_twoRowBitmap(), copies: 0), single);
      expect(encodePhomemoM110Job(_twoRowBitmap(), copies: -4), single);
      expect(
        encodePhomemoM110Job(_twoRowBitmap(), copies: 9).length,
        9 * single.length,
      );
      expect(
        encodePhomemoM110Job(_twoRowBitmap(), copies: 10).length,
        9 * single.length,
      );
      expect(
        encodePhomemoM110Job(_twoRowBitmap(), copies: 100).length,
        9 * single.length,
      );
    });

    test('density: 0x0D changes byte 7 only', () {
      final base = encodePhomemoM110Job(_twoRowBitmap());
      final dense = encodePhomemoM110Job(_twoRowBitmap(), density: 0x0D);

      expect(dense.length, base.length);
      expect(base[7], 0x0A);
      expect(dense[7], 0x0D);
      expect(_diff(base, dense), [7]);
    });

    test('speed changes byte 3 only', () {
      final base = encodePhomemoM110Job(_twoRowBitmap());
      final slow = encodePhomemoM110Job(_twoRowBitmap(), speed: 2);

      expect(slow[3], 2);
      expect(_diff(base, slow), [3]);
    });

    test('density and speed outside a byte are rejected', () {
      expect(
        () => encodePhomemoM110Job(_twoRowBitmap(), density: 256),
        throwsArgumentError,
      );
      expect(
        () => encodePhomemoM110Job(_twoRowBitmap(), density: -1),
        throwsArgumentError,
      );
      expect(
        () => encodePhomemoM110Job(_twoRowBitmap(), speed: 256),
        throwsArgumentError,
      );
    });

    test('a bitmap that is not 384 wide throws ArgumentError', () {
      expect(
        () => encodePhomemoM110Job(LabelBitmap.blank(383, 240)),
        throwsArgumentError,
      );
      expect(
        () => encodePhomemoM110Job(LabelBitmap.blank(392, 240)),
        throwsArgumentError,
      );
    });

    test('a bitmap with no rows or more than 65535 rows throws', () {
      expect(
        () => encodePhomemoM110Job(LabelBitmap.blank(384, 0)),
        throwsArgumentError,
      );
      expect(
        () => encodePhomemoM110Job(LabelBitmap.blank(384, 65536)),
        throwsArgumentError,
      );
    });

    test('row bits go out unchanged, MSB first', () {
      final bits = Uint8List(96)
        ..[0] = 0x81
        ..[48] = 0x18;
      final job = encodePhomemoM110Job(
        LabelBitmap(width: 384, height: 2, bits: bits),
      );

      expect(job[19], 0x81);
      expect(job[19 + 48], 0x18);
    });
  });

  group('chunkBytes', () {
    test('250 bytes at 100 gives [100, 100, 50] and concatenates back', () {
      final data = Uint8List.fromList(List.generate(250, (i) => i));

      final chunks = chunkBytes(data, 100);

      expect(chunks.map((c) => c.length), [100, 100, 50]);
      expect(_concat(chunks), data);
    });

    test('an exact multiple has no short tail', () {
      final chunks = chunkBytes(Uint8List(256), 128);
      expect(chunks.map((c) => c.length), [128, 128]);
    });

    test('no data gives no chunks', () {
      expect(chunkBytes(Uint8List(0), 100), isEmpty);
    });

    test('a chunk size below 1 throws', () {
      expect(() => chunkBytes(Uint8List(5), 0), throwsArgumentError);
      expect(() => chunkBytes(Uint8List(5), -1), throwsArgumentError);
    });
  });

  group('planPhomemoM110Writes', () {
    final plan = planPhomemoM110Writes(LabelBitmap.blank(384, 240));

    test('a 384 x 240 label is 95 writes', () {
      expect(plan.length, 95);
    });

    test('the 3 header commands and raster header pause 30 ms', () {
      expect(plan[0].bytes, [0x1B, 0x4E, 0x0D, 0x05]);
      expect(plan[1].bytes, [0x1B, 0x4E, 0x04, 0x0A]);
      expect(plan[2].bytes, [0x1F, 0x11, 0x0A]);
      expect(plan[3].bytes, [0x1D, 0x76, 0x30, 0x00, 0x30, 0x00, 0xF0, 0x00]);
      for (var i = 0; i < 4; i++) {
        expect(plan[i].pauseAfter, const Duration(milliseconds: 30));
      }
    });

    test('writes 5-93 are 128-byte raster chunks pausing 20 ms', () {
      for (var i = 4; i < 93; i++) {
        expect(plan[i].bytes.length, 128, reason: 'write ${i + 1}');
        expect(
          plan[i].pauseAfter,
          const Duration(milliseconds: 20),
          reason: 'write ${i + 1}',
        );
      }
    });

    test('write 94, the last raster chunk, pauses 300 ms', () {
      expect(plan[93].bytes.length, 128);
      expect(plan[93].pauseAfter, const Duration(milliseconds: 300));
    });

    test('write 95 is the 8-byte footer pausing 500 ms', () {
      expect(plan[94].bytes, _footer);
      expect(plan[94].pauseAfter, const Duration(milliseconds: 500));
    });

    test('all writes concatenate to the encoded job', () {
      expect(
        _concat(plan.map((w) => w.bytes)),
        encodePhomemoM110Job(LabelBitmap.blank(384, 240)),
      );
    });

    test('a raster shorter than one chunk is a single 300 ms write', () {
      final p = planPhomemoM110Writes(_twoRowBitmap());

      expect(p.length, 6);
      expect(p[4].bytes.length, 96);
      expect(p[4].pauseAfter, const Duration(milliseconds: 300));
      expect(p[5].bytes, _footer);
    });

    test('a smaller chunk size splits the raster further', () {
      final p = planPhomemoM110Writes(_twoRowBitmap(), chunkSize: 20);

      // 4 header writes + ceil(96 / 20) = 5 raster writes + footer.
      expect(p.length, 10);
      expect(p.sublist(4, 9).map((w) => w.bytes.length), [20, 20, 20, 20, 16]);
      expect(
        p.sublist(4, 8).map((w) => w.pauseAfter),
        everyElement(const Duration(milliseconds: 20)),
      );
      expect(p[8].pauseAfter, const Duration(milliseconds: 300));
      expect(
        _concat(p.map((w) => w.bytes)),
        encodePhomemoM110Job(_twoRowBitmap()),
      );
    });

    test('copies repeat the whole write plan once per copy', () {
      final two = planPhomemoM110Writes(LabelBitmap.blank(384, 240), copies: 2);

      expect(two.length, 190);
      expect(two.sublist(0, 95).map((w) => w.bytes), plan.map((w) => w.bytes));
      expect(two.sublist(95).map((w) => w.bytes), plan.map((w) => w.bytes));
      expect(
        two.map((w) => w.pauseAfter),
        [...plan, ...plan].map((w) => w.pauseAfter),
      );
      expect(
        _concat(two.map((w) => w.bytes)),
        encodePhomemoM110Job(LabelBitmap.blank(384, 240), copies: 2),
      );
    });

    test('copies is clamped to 1-9', () {
      final bitmap = _twoRowBitmap();
      expect(planPhomemoM110Writes(bitmap, copies: 0).length, 6);
      expect(planPhomemoM110Writes(bitmap, copies: 99).length, 54);
    });

    test('density and speed reach the header writes', () {
      final p = planPhomemoM110Writes(_twoRowBitmap(), density: 0x0D, speed: 3);
      expect(p[0].bytes, [0x1B, 0x4E, 0x0D, 0x03]);
      expect(p[1].bytes, [0x1B, 0x4E, 0x04, 0x0D]);
    });

    test('a chunk size shorter than the 8-byte footer throws', () {
      expect(
        () => planPhomemoM110Writes(_twoRowBitmap(), chunkSize: 7),
        throwsArgumentError,
      );
    });

    test('a bitmap that is not 384 wide throws ArgumentError', () {
      expect(
        () => planPhomemoM110Writes(LabelBitmap.blank(100, 10)),
        throwsArgumentError,
      );
    });
  });

  group('BLE and timing constants', () {
    test('defaults match the reference implementations', () {
      expect(kPhomemoDefaultSpeed, 5);
      expect(kPhomemoDefaultDensity, 0x0A);
      expect(kPhomemoMediaGapLabel, 0x0A);
      expect(kPhomemoChunkSize, 128);
      expect(kPhomemoCommandPause, const Duration(milliseconds: 30));
      expect(kPhomemoChunkPause, const Duration(milliseconds: 20));
      expect(kPhomemoBeforeFooterPause, const Duration(milliseconds: 300));
      expect(kPhomemoAfterFooterPause, const Duration(milliseconds: 500));
      expect(kPhomemoDoneTimeout, const Duration(seconds: 3));
    });

    test('BLE ids, name prefixes and status queries', () {
      expect(kPhomemoServiceUuid, 'ff00');
      expect(kPhomemoWriteUuid, 'ff02');
      expect(kPhomemoNotifyUuid, 'ff03');
      expect(kPhomemoNamePrefixes, ['Q199', 'M110', 'M120', 'M220']);
      expect(kPhomemoQueryPaper, [0x1F, 0x11, 0x11]);
      expect(kPhomemoQueryCover, [0x1F, 0x11, 0x12]);
      expect(kPhomemoQueryBattery, [0x1F, 0x11, 0x08]);
    });
  });
}
