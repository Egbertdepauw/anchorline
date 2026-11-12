import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// tool/publish/lib is not the package's lib/ folder; the lint matches on the
// path.
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/content.dart';
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/manifest.dart' show PublishError;
import 'fake_bucket.dart';

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
}
