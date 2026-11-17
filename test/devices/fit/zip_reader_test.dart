import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ccrlogger/devices/fit/zip_reader.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/zip_builder.dart';

/// Wraps a [RandomAccessFile] and records the largest single read.
class CountingFile implements RandomAccessFile {
  CountingFile(this.inner);
  final RandomAccessFile inner;
  int largestRead = 0;

  @override
  Future<Uint8List> read(int count) {
    largestRead = max(largestRead, count);
    return inner.read(count);
  }

  @override
  Future<int> readInto(List<int> buffer, [int start = 0, int? end]) {
    largestRead = max(largestRead, (end ?? buffer.length) - start);
    return inner.readInto(buffer, start, end);
  }

  @override
  Future<RandomAccessFile> setPosition(int position) async {
    await inner.setPosition(position);
    return this;
  }

  @override
  Future<int> length() => inner.length();

  @override
  Future<int> position() => inner.position();

  @override
  Future<void> close() => inner.close();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('CountingFile: ${invocation.memberName}');
}

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('zip_reader_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<ZipReader> openBytes(Uint8List zip, {String name = 'a.zip'}) async {
    final f = File('${tmp.path}/$name')..writeAsBytesSync(zip);
    return ZipReader.open(await f.open());
  }

  test('lists and reads stored and deflated entries', () async {
    final big = Uint8List.fromList(
        List.generate(5000, (i) => (i * 7) % 251));
    final zip = buildZip([
      ZipSpec('dir/', Uint8List(0)),
      ZipSpec('a.txt', bytesOf('hello stored')),
      ZipSpec('b.bin', big, deflate: true),
      ZipSpec('c.fit', bytesOf('descriptor'),
          deflate: true, dataDescriptor: true),
      ZipSpec('d.fit', bytesOf('descriptor stored'), dataDescriptor: true),
    ]);
    final r = await openBytes(zip);
    expect(r.entries.map((e) => e.name),
        ['dir/', 'a.txt', 'b.bin', 'c.fit', 'd.fit']);
    expect(r.entries[0].isDirectory, isTrue);
    expect(r.entries[1].isStored, isTrue);
    expect(r.entries[2].isStored, isFalse);
    expect(r.entries[2].size, 5000);
    expect(await r.read(r.entries[1]), bytesOf('hello stored'));
    expect(await r.read(r.entries[2]), big);
    expect(await r.read(r.entries[3]), bytesOf('descriptor'));
    expect(await r.read(r.entries[4]), bytesOf('descriptor stored'));
  });

  test('a Zip64 archive (forced Zip64 records) lists and reads', () async {
    final zip = buildZip([
      ZipSpec('one.fit', bytesOf('first'), zip64: true),
      ZipSpec('two.fit', bytesOf('second' * 100),
          deflate: true, zip64: true),
      ZipSpec('three.fit', bytesOf('third')),
    ], zip64: true);
    final r = await openBytes(zip);
    expect(r.entries.length, 3);
    expect(await r.read(r.entries[0]), bytesOf('first'));
    expect(await r.read(r.entries[1]), bytesOf('second' * 100));
    expect(await r.read(r.entries[2]), bytesOf('third'));
  });

  test('a stored inner zip opens in place through storedSpan', () async {
    final inner = buildZip([ZipSpec('x.fit', bytesOf('inner data'))]);
    final outer = buildZip([
      ZipSpec('readme.txt', bytesOf('pad pad pad')),
      ZipSpec('inner.zip', inner),
    ]);
    final f = File('${tmp.path}/outer.zip')..writeAsBytesSync(outer);
    final raf = await f.open();
    final o = await ZipReader.open(raf);
    final span = o.storedSpan(o.entries[1]);
    expect(span.length, inner.length);
    final i = await ZipReader.open(raf, base: span.base, length: span.length);
    expect(i.entries.single.name, 'x.fit');
    expect(await i.read(i.entries.single), bytesOf('inner data'));
    expect(() => o.storedSpan(o.entries[0]), returnsNormally);
  });

  test('storedSpan rejects a deflated entry', () async {
    final r = await openBytes(
        buildZip([ZipSpec('a', bytesOf('aaaa' * 50), deflate: true)]));
    expect(() => r.storedSpan(r.entries.single),
        throwsA(isA<ZipFormatException>()));
  });

  test('extractTo never reads more than 1 MB at once', () async {
    final data = Uint8List(3 * 1024 * 1024 + 123);
    for (var i = 0; i < data.length; i++) {
      data[i] = (i * 31) & 0xFF;
    }
    final zip = buildZip([
      ZipSpec('s.bin', data),
      ZipSpec('d.bin', data, deflate: true),
    ]);
    final f = File('${tmp.path}/big.zip')..writeAsBytesSync(zip);
    final counting = CountingFile(await f.open());
    final r = await ZipReader.open(counting);
    for (var k = 0; k < 2; k++) {
      final target = File('${tmp.path}/out$k.bin');
      await r.extractTo(r.entries[k], target);
      expect(target.readAsBytesSync(), data);
    }
    expect(counting.largestRead, lessThanOrEqualTo(1 << 20));
    expect(counting.largestRead, greaterThan(0));
  });

  test('a 50 MB zip of stored entries reads entry by entry with bounded reads',
      () async {
    const mb = 1024 * 1024;
    final zeros = Uint8List(10 * mb);
    final zip = buildZip(
        [for (var i = 0; i < 5; i++) ZipSpec('z$i.bin', zeros)]);
    expect(zip.length, greaterThan(50 * mb));
    final f = File('${tmp.path}/50mb.zip')..writeAsBytesSync(zip);
    final counting = CountingFile(await f.open());
    final r = await ZipReader.open(counting);
    expect(r.entries.length, 5);
    for (final e in r.entries) {
      final b = await r.read(e, maxSize: 10 * mb);
      expect(b.length, 10 * mb);
    }
    expect(counting.largestRead, lessThanOrEqualTo(1 << 20));
    await expectLater(r.read(r.entries.first, maxSize: 5 * mb),
        throwsA(isA<ZipFormatException>()));
    await counting.close();
  });

  group('corrupt input', () {
    test('a corrupt central directory throws', () async {
      final zip = buildZip([ZipSpec('a', bytesOf('abc'))]);
      // Smash the central directory signature.
      final cd = zip.length - 22 - (46 + 1);
      zip[cd] = 0;
      await expectLater(
          openBytes(zip), throwsA(isA<ZipFormatException>()));
    });

    test('no end-of-central-directory record throws', () async {
      await expectLater(openBytes(Uint8List(100)),
          throwsA(isA<ZipFormatException>()));
      await expectLater(openBytes(Uint8List(0)),
          throwsA(isA<ZipFormatException>()));
    });

    test('a size mismatch throws', () async {
      final zip = buildZip([ZipSpec('a', bytesOf('abcdef'))]);
      // Central directory uncompressed size (offset 24 in the record) wrong.
      final cd = zip.length - 22 - (46 + 1);
      zip[cd + 24] = 9;
      final r = await openBytes(zip);
      await expectLater(
          r.read(r.entries.single), throwsA(isA<ZipFormatException>()));
    });

    test('a deflated entry whose size lies throws', () async {
      final zip = buildZip([
        ZipSpec('a', bytesOf('abcdef' * 40), deflate: true),
      ]);
      final cd = zip.length - 22 - (46 + 1);
      zip[cd + 24] += 1;
      final r = await openBytes(zip);
      await expectLater(
          r.read(r.entries.single), throwsA(isA<ZipFormatException>()));
      await expectLater(r.extractTo(r.entries.single,
              File('${tmp.path}/never.bin')),
          throwsA(isA<ZipFormatException>()));
      expect(File('${tmp.path}/never.bin').existsSync(), isFalse);
    });

    test('a CRC mismatch throws from read and extractTo', () async {
      final zip = buildZip([
        ZipSpec('a', bytesOf('abcdef'), corruptCrc: true),
        ZipSpec('b', bytesOf('abcdef' * 20), deflate: true, corruptCrc: true),
      ]);
      final r = await openBytes(zip);
      for (final e in r.entries) {
        await expectLater(r.read(e), throwsA(isA<ZipFormatException>()));
        final t = File('${tmp.path}/crc_${e.name}');
        await expectLater(
            r.extractTo(e, t), throwsA(isA<ZipFormatException>()));
        expect(t.existsSync(), isFalse);
      }
    });

    test('a bad local header fails only that stored entry', () async {
      final zip = buildZip([
        ZipSpec('good.txt', bytesOf('good')),
        ZipSpec('b.txt', bytesOf('bad one')),
      ]);
      // Zero the second entry's local header signature.
      final at = 30 + 'good.txt'.length + 4;
      zip.fillRange(at, at + 4, 0);
      final r = await openBytes(zip);
      expect(await r.read(r.entries[0]), bytesOf('good'));
      expect(() => r.storedSpan(r.entries[1]),
          throwsA(isA<ZipFormatException>()));
      await expectLater(
          r.read(r.entries[1]), throwsA(isA<ZipFormatException>()));
    });

    test('an unsupported method throws', () async {
      final zip = buildZip([ZipSpec('a', bytesOf('abc'), method: 12)]);
      final r = await openBytes(zip);
      await expectLater(
          r.read(r.entries.single), throwsA(isA<ZipFormatException>()));
    });

    test('an encrypted entry throws', () async {
      final zip = buildZip([ZipSpec('a', bytesOf('abc'), encrypted: true)]);
      final r = await openBytes(zip);
      await expectLater(
          r.read(r.entries.single), throwsA(isA<ZipFormatException>()));
    });

    test('read refuses an entry above maxSize', () async {
      final r = await openBytes(
          buildZip([ZipSpec('a', Uint8List(2000), deflate: true)]));
      await expectLater(r.read(r.entries.single, maxSize: 1000),
          throwsA(isA<ZipFormatException>()));
    });
  });
}
