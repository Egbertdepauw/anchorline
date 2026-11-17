import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

// tool/publish/lib is not the package's lib/ folder; the lint matches on the
// path.
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/content.dart';
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/manifest.dart' show PublishError;
import 'fake_bucket.dart';

/// A PNG with just a signature and an IHDR chunk: enough for the size reader.
Uint8List _png(int width, int height) {
  final b = ByteData(33);
  const sig = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  for (var i = 0; i < 8; i++) {
    b.setUint8(i, sig[i]);
  }
  b.setUint32(8, 13);
  for (var i = 0; i < 4; i++) {
    b.setUint8(12 + i, 'IHDR'.codeUnitAt(i));
  }
  b.setUint32(16, width);
  b.setUint32(20, height);
  return b.buffer.asUint8List();
}

Matcher _refusal(String containing) => throwsA(
  isA<PublishError>().having(
    (e) => e.message,
    'message',
    contains(containing),
  ),
);

const _markdown = 'text/markdown; charset=utf-8';

String _text(String title, String updated) =>
    '# $title\n\n_Last updated: ${updated}_\n\nBody.\n';

void main() {
  group('parseLastUpdated', () {
    test('reads the date as ISO', () {
      expect(
        parseLastUpdated('# T\n\n_Last updated: 8 November 2026_\n'),
        '2026-11-08',
      );
    });

    test('is null without the line', () {
      expect(parseLastUpdated('# T\n'), isNull);
    });

    test('is null for a date that does not exist', () {
      expect(parseLastUpdated('_Last updated: 31 Feb 2026_'), isNull);
      expect(parseLastUpdated('_Last updated: 31 February 2026_'), isNull);
    });
  });

  group('firstHeading', () {
    test('returns the first level-one heading, trimmed', () {
      expect(
        firstHeading('# Anchorline Privacy Policy\n\ntext'),
        'Anchorline Privacy Policy',
      );
      expect(firstHeading('intro\n#   Spaced out  \n# Second'), 'Spaced out');
    });

    test('is null without a heading', () {
      expect(firstHeading('## Not first level\n\ntext'), isNull);
    });
  });

  test('encodeContentIndex sorts keys and ends with a newline', () {
    final json = encodeContentIndex({
      'legal/terms': const ContentIndexEntry(
        title: 'Terms',
        updated: '2026-11-08',
        path: 'legal/terms.md',
      ),
      'legal/privacy': const ContentIndexEntry(
        title: 'Privacy',
        updated: '2026-11-08',
        path: 'legal/privacy.md',
      ),
    });
    expect(
      json,
      '{\n'
      '  "format": 1,\n'
      '  "texts": {\n'
      '    "legal/privacy": {\n'
      '      "title": "Privacy",\n'
      '      "updated": "2026-11-08",\n'
      '      "path": "legal/privacy.md"\n'
      '    },\n'
      '    "legal/terms": {\n'
      '      "title": "Terms",\n'
      '      "updated": "2026-11-08",\n'
      '      "path": "legal/terms.md"\n'
      '    }\n'
      '  }\n'
      '}\n',
    );
  });

  group('ContentPublisher', () {
    late Directory repo;

    void write(String relative, String content) {
      final file = File('${repo.path}/$relative');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    setUp(() {
      repo = Directory.systemTemp.createTempSync('content_test_');
      write('docs/PRIVACY.md', _text('Privacy Title', '8 November 2026'));
      write('docs/TERMS.md', _text('Terms Title', '9 November 2026'));
      write(
        'docs/ACCOUNT_DELETION.md',
        _text('Deletion Title', '10 November 2026'),
      );
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('uploads the texts, then the index last', () async {
      final bucket = FakeBucket();
      final result = await ContentPublisher(
        bucket,
        repoRoot: repo.path,
      ).publish();

      expect(bucket.putCalls, [
        'putText content/legal/privacy.md',
        'putText content/legal/terms.md',
        'putText content/legal/account-deletion.md',
        'putText content/index.json',
      ]);
      for (final put in bucket.textPuts.take(3)) {
        expect(put.contentType, _markdown);
        expect(put.cacheControl, 'no-cache');
      }
      expect(bucket.textPuts.last.contentType, 'application/json');
      expect(bucket.textPuts.last.cacheControl, 'no-cache');
      expect(bucket.textPuts.last.text, result.indexJson);
      expect(bucket.textPuts.first.text, contains('# Privacy Title'));
      expect(result.uploadedKeys, [
        'content/legal/privacy.md',
        'content/legal/terms.md',
        'content/legal/account-deletion.md',
        'content/index.json',
      ]);
      expect(result.indexJson, contains('"title": "Deletion Title"'));
      expect(result.indexJson, contains('"updated": "2026-11-09"'));
      expect(result.indexJson, contains('"path": "legal/terms.md"'));
    });

    test('a dry run writes nothing and returns the same index', () async {
      final real = await ContentPublisher(
        FakeBucket(),
        repoRoot: repo.path,
      ).publish();
      final bucket = FakeBucket();
      final dry = await ContentPublisher(
        bucket,
        repoRoot: repo.path,
        dryRun: true,
      ).publish();

      expect(bucket.putCalls, isEmpty);
      expect(dry.indexJson, real.indexJson);
    });

    test('a missing file is refused by name, before any upload', () async {
      File('${repo.path}/docs/TERMS.md').deleteSync();
      final bucket = FakeBucket();
      await expectLater(
        ContentPublisher(bucket, repoRoot: repo.path).publish(),
        throwsA(
          isA<PublishError>().having(
            (e) => e.message,
            'message',
            contains('docs/TERMS.md'),
          ),
        ),
      );
      expect(bucket.putCalls, isEmpty);
    });

    test('a file without a last-updated line is refused first', () async {
      write('docs/ACCOUNT_DELETION.md', '# Delete\n\nNo date here.\n');
      final bucket = FakeBucket();
      await expectLater(
        ContentPublisher(bucket, repoRoot: repo.path).publish(),
        throwsA(
          isA<PublishError>().having(
            (e) => e.message,
            'message',
            contains('docs/ACCOUNT_DELETION.md'),
          ),
        ),
      );
      expect(bucket.putCalls, isEmpty);
    });

    test('a file without a heading is refused', () async {
      write('docs/PRIVACY.md', '_Last updated: 8 November 2026_\n\nBody.\n');
      final bucket = FakeBucket();
      await expectLater(
        ContentPublisher(bucket, repoRoot: repo.path).publish(),
        throwsA(isA<PublishError>()),
      );
      expect(bucket.putCalls, isEmpty);
    });
  });

  group('markdownLinks', () {
    test('finds links and images and skips fenced code', () {
      final links = markdownLinks(
        'See [A](a.md) and ![alt](images/x.png "t").\n'
        '```\n[no](nope.md)\n```\n[B](/manual/b#c)\n',
      );
      expect([for (final l in links) l.target], [
        'a.md',
        'images/x.png',
        '/manual/b#c',
      ]);
      expect(links[1].isImage, isTrue);
      expect(links[1].text, 'alt');
    });
  });

  group('manual', () {
    late Directory repo;

    void write(String relative, String content) {
      final file = File('${repo.path}/$relative');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(content);
    }

    void writePng(String name, int w, int h) {
      final file = File('${repo.path}/docs/user/images/$name');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(_png(w, h));
    }

    Future<String?> commitDate(String path) async => '2026-03-05';

    ContentPublisher publisher(
      FakeBucket bucket, {
      bool dryRun = false,
      Future<String?> Function(String)? date,
    }) => ContentPublisher(
      bucket,
      repoRoot: repo.path,
      dryRun: dryRun,
      commitDate: date ?? commitDate,
    );

    setUp(() {
      repo = Directory.systemTemp.createTempSync('manual_test_');
      write('docs/PRIVACY.md', _text('Privacy Title', '8 November 2026'));
      write('docs/TERMS.md', _text('Terms Title', '9 November 2026'));
      write(
        'docs/ACCOUNT_DELETION.md',
        _text('Deletion Title', '10 November 2026'),
      );
      write(
        'docs/user/index.md',
        '# User manual\n\n- [Dives](dives.md)\n- [Plan](plan.md#top)\n',
      );
      write(
        'docs/user/dives.md',
        '# Dives\n\n![The list](images/dives-1.png)\n\n'
        '[Plan](/manual/plan)\n[Web](https://example.com)\n[Up](#top)\n',
      );
      write('docs/user/plan.md', '# Plan\n\nText.\n');
      writePng('dives-1.png', 390, 844);
      writePng('a-b.png', 10, 20);
    });

    tearDown(() => repo.deleteSync(recursive: true));

    Future<void> expectRefused(String containing, FakeBucket bucket) async {
      await expectLater(
        publisher(bucket).publish(),
        _refusal(containing),
      );
      expect(bucket.putCalls, isEmpty);
      expect(bucket.deleteCalls, isEmpty);
    }

    test('uploads legal, images, images.json, pages, index last', () async {
      final bucket = FakeBucket();
      final result = await publisher(bucket).publish();

      expect(bucket.putCalls, [
        'putText content/legal/privacy.md',
        'putText content/legal/terms.md',
        'putText content/legal/account-deletion.md',
        'putFile content/docs/user/images/a-b.png',
        'putFile content/docs/user/images/dives-1.png',
        'putText content/docs/user/images.json',
        'putText content/docs/user/dives.md',
        'putText content/docs/user/index.md',
        'putText content/docs/user/plan.md',
        'putText content/index.json',
      ]);
      expect(result.uploadedKeys, [
        'content/legal/privacy.md',
        'content/legal/terms.md',
        'content/legal/account-deletion.md',
        'content/docs/user/images/a-b.png',
        'content/docs/user/images/dives-1.png',
        'content/docs/user/images.json',
        'content/docs/user/dives.md',
        'content/docs/user/index.md',
        'content/docs/user/plan.md',
        'content/index.json',
      ]);
      for (final put in bucket.filePuts) {
        expect(put.contentType, 'image/png');
        expect(put.cacheControl, 'public, max-age=86400');
      }
      for (final put in bucket.textPuts) {
        final isJson = put.key.endsWith('.json');
        expect(
          put.contentType,
          isJson ? 'application/json' : _markdown,
          reason: put.key,
        );
        expect(put.cacheControl, 'no-cache', reason: put.key);
      }
      expect(
        bucket.texts['content/docs/user/images.json'],
        '{\n'
        '  "images/a-b.png": {\n'
        '    "width": 10,\n'
        '    "height": 20\n'
        '  },\n'
        '  "images/dives-1.png": {\n'
        '    "width": 390,\n'
        '    "height": 844\n'
        '  }\n'
        '}\n',
      );
      expect(bucket.texts['content/docs/user/dives.md'], contains('# Dives'));
      expect(
        result.indexJson,
        contains(
          '"docs/user/index": {\n'
          '      "title": "User manual",\n'
          '      "updated": "2026-03-05",\n'
          '      "path": "docs/user/index.md"\n'
          '    }',
        ),
      );
      expect(result.indexJson, contains('"docs/user/dives"'));
      expect(result.indexJson, contains('"docs/user/plan"'));
      // Legal dates still come from the text itself.
      expect(result.indexJson, contains('"updated": "2026-11-09"'));
      expect(result.deletedKeys, isEmpty);
    });

    test('stale manual objects go after the index, nothing else', () async {
      final bucket = FakeBucket(
        texts: {
          'content/docs/user/old.md': 'old',
          'content/legal/x.md': 'keep',
          'releases/manifest.json': '{}',
        },
      )..objects['content/docs/user/images/old.png'] = 'abc';
      final result = await publisher(bucket).publish();

      expect(result.deletedKeys, [
        'content/docs/user/images/old.png',
        'content/docs/user/old.md',
      ]);
      expect(bucket.deleteCalls, [
        'delete content/docs/user/images/old.png',
        'delete content/docs/user/old.md',
      ]);
      expect(
        bucket.calls.indexOf('delete content/docs/user/old.md'),
        greaterThan(bucket.calls.indexOf('putText content/index.json')),
      );
      expect(bucket.texts.containsKey('content/legal/x.md'), isTrue);
      expect(bucket.texts.containsKey('releases/manifest.json'), isTrue);
      expect(bucket.calls.where((c) => c.startsWith('list ')), [
        'list content/docs/user/',
      ]);
    });

    test('a dry run reports deletions but changes nothing', () async {
      FakeBucket seeded() => FakeBucket(
        texts: {'content/docs/user/old.md': 'old'},
      );
      final real = await publisher(seeded()).publish();
      final bucket = seeded();
      final dry = await publisher(bucket, dryRun: true).publish();

      expect(bucket.putCalls, isEmpty);
      expect(bucket.deleteCalls, isEmpty);
      expect(dry.deletedKeys, ['content/docs/user/old.md']);
      expect(dry.indexJson, real.indexJson);
      expect(dry.uploadedKeys, real.uploadedKeys);
    });

    test('without docs/user the manual is skipped entirely', () async {
      Directory('${repo.path}/docs/user').deleteSync(recursive: true);
      final bucket = FakeBucket(texts: {'content/docs/user/old.md': 'old'});
      final result = await publisher(bucket).publish();

      expect(bucket.calls.where((c) => c.startsWith('list ')), isEmpty);
      expect(bucket.deleteCalls, isEmpty);
      expect(result.deletedKeys, isEmpty);
      expect(bucket.putCalls.last, 'putText content/index.json');
    });

    test('a missing image is refused by page', () async {
      File('${repo.path}/docs/user/images/dives-1.png').deleteSync();
      await expectRefused('docs/user/dives.md', FakeBucket());
    });

    test('an image without alt text is refused', () async {
      write('docs/user/dives.md', '# Dives\n\n![ ](images/dives-1.png)\n');
      await expectRefused('no alt text', FakeBucket());
    });

    test('an absolute image URL is refused', () async {
      write('docs/user/dives.md', '# Dives\n\n![x](https://e.com/a.png)\n');
      await expectRefused('docs/user/dives.md', FakeBucket());
      write('docs/user/dives.md', '# Dives\n\n![x](/images/dives-1.png)\n');
      await expectRefused('images/<name>.png', FakeBucket());
      write('docs/user/dives.md', '# Dives\n\n![x](images/../x.png)\n');
      await expectRefused('images/<name>.png', FakeBucket());
    });

    test('a link to a page that does not exist is refused', () async {
      write('docs/user/dives.md', '# Dives\n\n[Gone](gone.md)\n');
      await expectRefused('gone.md', FakeBucket());
      write('docs/user/dives.md', '# Dives\n\n[Gone](/manual/gone#x)\n');
      await expectRefused('/manual/gone#x', FakeBucket());
    });

    test('a page without a heading is refused', () async {
      write('docs/user/plan.md', 'No heading.\n');
      await expectRefused('docs/user/plan.md has no "# " heading', FakeBucket());
    });

    test('an uncommitted page is refused', () async {
      final bucket = FakeBucket();
      await expectLater(
        publisher(
          bucket,
          date: (path) async => path.endsWith('plan.md') ? null : '2026-03-05',
        ).publish(),
        _refusal('docs/user/plan.md is not committed'),
      );
      expect(bucket.putCalls, isEmpty);
    });

    test('an invalid PNG is refused', () async {
      write('docs/user/images/bad.png', 'not a png at all, but long enough!!');
      await expectRefused('docs/user/images/bad.png', FakeBucket());
    });

    test('a bad page file name is refused', () async {
      write('docs/user/Bad_Name.md', '# Bad\n');
      await expectRefused('docs/user/Bad_Name.md', FakeBucket());
    });

    test('a manual without index.md is refused', () async {
      File('${repo.path}/docs/user/index.md').deleteSync();
      await expectRefused('docs/user/index.md does not exist', FakeBucket());
    });
  });

  group('gitCommitDate', () {
    late Directory repo;

    Future<void> git(List<String> args, {Map<String, String>? env}) async {
      final r = await Process.run(
        'git',
        ['-C', repo.path, ...args],
        environment: env,
      );
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('git_date_test_');
      await git(['init', '-q']);
      await git(['config', 'user.name', 'Test']);
      await git(['config', 'user.email', 'test@example.com']);
      await git(['config', 'commit.gpgsign', 'false']);
      File('${repo.path}/a.md').writeAsStringSync('# A\n');
      File('${repo.path}/untracked.md').writeAsStringSync('# U\n');
      await git(['add', 'a.md']);
      const date = '2026-03-04T23:30:00-05:00';
      await git(
        ['commit', '-q', '-m', 'add a'],
        env: {'GIT_AUTHOR_DATE': date, 'GIT_COMMITTER_DATE': date},
      );
    });

    tearDown(() => repo.deleteSync(recursive: true));

    test('is the UTC date of the last commit', () async {
      expect(await gitCommitDate(repo.path, 'a.md'), '2026-03-05');
    });

    test('is null for a file git has no commit for', () async {
      expect(await gitCommitDate(repo.path, 'untracked.md'), isNull);
    });

    test('fails when git fails', () async {
      await expectLater(
        gitCommitDate(
          repo.path,
          'a.md',
          runner: (e, a, {environment}) async => ProcessResult(1, 128, '', 'x'),
        ),
        _refusal('git log for a.md failed'),
      );
      // Not a repository at all.
      final plain = Directory.systemTemp.createTempSync('no_git_');
      addTearDown(() => plain.deleteSync(recursive: true));
      await expectLater(
        gitCommitDate(plain.path, 'a.md'),
        throwsA(isA<PublishError>()),
      );
    });
  });

  test("this repository's real manual passes validation", () async {
    final bucket = FakeBucket();
    final result = await ContentPublisher(
      bucket,
      repoRoot: Directory.current.path,
      dryRun: true,
    ).publish();

    final index = jsonDecode(result.indexJson) as Map<String, dynamic>;
    final texts = index['texts'] as Map<String, dynamic>;
    final manual = texts.keys.where((k) => k.startsWith('docs/user/'));
    final pages = Directory('docs/user')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.md'));
    expect(manual, hasLength(pages.length));
    expect(manual, contains('docs/user/index'));
    expect(bucket.putCalls, isEmpty);
  });
}
