import 'dart:io';

import 'package:ccrlogger/sync/attachments/attachment_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

Future<File> _writeTempBytes(Directory dir, String name, List<int> bytes) async {
  final f = File(p.join(dir.path, name));
  await f.writeAsBytes(bytes, flush: true);
  return f;
}

void main() {
  late Directory tmpRoot;
  late Directory cacheRoot;
  late Directory stagingRoot;

  setUp(() async {
    tmpRoot = await Directory.systemTemp.createTemp('ccrlogger_cache_test_');
    cacheRoot = Directory(p.join(tmpRoot.path, 'cache'));
    stagingRoot = Directory(p.join(tmpRoot.path, 'staging'));
    await stagingRoot.create(recursive: true);
  });

  tearDown(() async {
    if (await tmpRoot.exists()) {
      await tmpRoot.delete(recursive: true);
    }
  });

  test('init() creates the cache directory if missing', () async {
    final cache = AttachmentCache(rootDirectory: cacheRoot);
    expect(await cacheRoot.exists(), isFalse);
    await cache.init();
    expect(await cacheRoot.exists(), isTrue);
  });

  test('put + get round-trip stores and returns bytes', () async {
    final cache = AttachmentCache(rootDirectory: cacheRoot);
    final src = await _writeTempBytes(stagingRoot, 'a', [1, 2, 3, 4]);
    final stored = await cache.put('attachments/u1/d1/abc.pdf', src);
    expect(await stored.exists(), isTrue);
    // Source was renamed/copy+deleted into the cache.
    expect(await src.exists(), isFalse);

    final fetched = await cache.get('attachments/u1/d1/abc.pdf');
    expect(fetched, isNotNull);
    expect(await fetched!.readAsBytes(), [1, 2, 3, 4]);
  });

  test('get returns null on miss', () async {
    final cache = AttachmentCache(rootDirectory: cacheRoot);
    expect(await cache.get('attachments/u1/d1/missing'), isNull);
  });

  test('object key with slashes flattens to a single filename', () async {
    final cache = AttachmentCache(rootDirectory: cacheRoot);
    final src = await _writeTempBytes(stagingRoot, 'b', [9]);
    await cache.put('attachments/u1/d1/abc.pdf', src);
    // No subdirectories were created — the cache root has exactly one file.
    final children = await cacheRoot.list().toList();
    expect(children.length, 1);
    expect(p.basename(children.single.path), 'attachments_u1_d1_abc.pdf');
  });

  test('eviction drops oldest entries when over cap', () async {
    // 100-byte cap; three 60-byte files → at least one must be evicted.
    final cache = AttachmentCache(rootDirectory: cacheRoot, maxBytes: 100);
    final blob = List<int>.filled(60, 0);

    final s1 = await _writeTempBytes(stagingRoot, 's1', blob);
    await cache.put('k1', s1);
    // Bump mtime ordering: ensure s1 looks older than the next put.
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final s2 = await _writeTempBytes(stagingRoot, 's2', blob);
    await cache.put('k2', s2);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final s3 = await _writeTempBytes(stagingRoot, 's3', blob);
    await cache.put('k3', s3);

    // After putting s3 we're at 180 bytes; eviction trims to ≤100.
    // The oldest (k1) is evicted; if necessary k2 too.
    expect(await cache.get('k1'), isNull);
    expect(await cache.get('k3'), isNotNull);
  });

  test('clear() removes everything under the root', () async {
    final cache = AttachmentCache(rootDirectory: cacheRoot);
    final s1 = await _writeTempBytes(stagingRoot, 's1', [1]);
    final s2 = await _writeTempBytes(stagingRoot, 's2', [2]);
    await cache.put('k1', s1);
    await cache.put('k2', s2);
    expect(await cache.get('k1'), isNotNull);
    expect(await cache.get('k2'), isNotNull);

    await cache.clear();

    expect(await cache.get('k1'), isNull);
    expect(await cache.get('k2'), isNull);
    // Root directory itself still exists, so future puts just work.
    expect(await cacheRoot.exists(), isTrue);
  });

  test('put overwrites an existing entry for the same key', () async {
    final cache = AttachmentCache(rootDirectory: cacheRoot);
    final s1 = await _writeTempBytes(stagingRoot, 's1', [1, 1, 1]);
    await cache.put('k', s1);

    final s2 = await _writeTempBytes(stagingRoot, 's2', [9, 9, 9, 9, 9]);
    await cache.put('k', s2);

    final got = await cache.get('k');
    expect(await got!.readAsBytes(), [9, 9, 9, 9, 9]);
  });
}
