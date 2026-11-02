import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// tool/publish/lib is not the package's lib/ folder; the lint matches on the
// path.
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/manifest.dart';
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/publisher.dart';
import 'fake_bucket.dart';

const _baseUrl = 'https://dl.example';
const _releasesKey = 'releases/manifest.json';
const _nightlyKey = 'nightly/manifest.json';

const _winBytes = 'windows installer bytes';
const _linuxBytes = 'linux appimage bytes';
const _macBytes = 'macos dmg bytes';

String _sha(String text) => sha256.convert(utf8.encode(text)).toString();

Matcher _publishError([String? containing]) => throwsA(
  isA<PublishError>().having(
    (e) => e.message,
    'message',
    containing == null ? isNotEmpty : contains(containing),
  ),
);

ReleaseEntry _entry(
  String version, {
  int build = 1,
  String date = '2026-11-01',
  String notes = '',
}) => ReleaseEntry(
  version: version,
  build: build,
  date: date,
  notes: notes,
  files: {
    'windows-x64': FileEntry(
      url: '$_baseUrl/old/$version',
      size: 1,
      sha256: 'ab',
    ),
  },
);

String _manifestText({ReleaseEntry? latest, List<ReleaseEntry>? previous}) =>
    Manifest(latest: latest, previous: previous ?? const []).encode();

void main() {
  late Directory tmp;
  late String win;
  late String linux;
  late String mac;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('publisher_test_');
    String write(String name, String content) {
      final path = '${tmp.path}/$name';
      File(path).writeAsStringSync(content);
      return path;
    }

    win = write('build-output.exe', _winBytes);
    linux = write('Anchorline-x86_64.AppImage', _linuxBytes);
    mac = write('Anchorline.dmg', _macBytes);
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  Publisher publisher(
    FakeBucket bucket, {
    DateTime? now,
    bool dryRun = false,
    String baseUrl = _baseUrl,
  }) => Publisher(
    bucket,
    baseUrl: baseUrl,
    now: () => now ?? DateTime.utc(2026, 11, 3, 8),
    dryRun: dryRun,
  );

  Future<Manifest> publishRelease(
    Publisher p, {
    String version = '1.2.0',
    int build = 45,
    String notes = 'Release notes',
    Map<String, String>? files,
    bool force = false,
  }) => p.publish(
    lane: Lane.releases,
    version: version,
    build: build,
    notes: notes,
    files: files ?? {'windows-x64': win, 'linux-x64': linux},
    force: force,
  );

  Future<Manifest> publishNightly(
    Publisher p, {
    String version = '1.3.0',
    int build = 157,
    String notes = '',
    Map<String, String>? files,
  }) => p.publish(
    lane: Lane.nightly,
    version: version,
    build: build,
    notes: notes,
    files: files ?? {'windows-x64': win, 'linux-x64': linux, 'macos': mac},
  );

  group('publish, releases lane', () {
    test(
      'uploads and verifies every file before the one manifest write',
      () async {
        final bucket = FakeBucket();
        await publishRelease(publisher(bucket));

        expect(bucket.calls, [
          'getText $_releasesKey',
          'putFile releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
          'putFile releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage',
          'sha256Of releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
          'sha256Of releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage',
          'putText $_releasesKey',
        ]);
      },
    );

    test('uploads the local files under the canonical object keys', () async {
      final bucket = FakeBucket();
      await publishRelease(publisher(bucket));

      expect(bucket.filePuts.map((p) => (p.key, p.path, p.contentType)), [
        (
          'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
          win,
          'application/vnd.microsoft.portable-executable',
        ),
        (
          'releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage',
          linux,
          'application/vnd.appimage',
        ),
      ]);
    });

    test('writes the manifest as no-cache JSON that parses back', () async {
      final bucket = FakeBucket();
      final result = await publishRelease(publisher(bucket));

      expect(bucket.textPuts, hasLength(1));
      final put = bucket.textPuts.single;
      expect(put.key, _releasesKey);
      expect(put.contentType, 'application/json');
      expect(put.cacheControl, 'no-cache');
      expect(put.text, result.encode());

      final latest = Manifest.parse(put.text).latest!;
      expect(latest.version, '1.2.0');
      expect(latest.build, 45);
      expect(latest.notes, 'Release notes');
      expect(latest.date, '2026-11-03');
      expect(
        latest.files['windows-x64']!.url,
        '$_baseUrl/releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      );
      expect(latest.files['windows-x64']!.size, _winBytes.length);
      expect(latest.files['windows-x64']!.sha256, _sha(_winBytes));
      expect(
        latest.files['linux-x64']!.url,
        '$_baseUrl/releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage',
      );
      expect(latest.files['linux-x64']!.size, _linuxBytes.length);
      expect(latest.files['linux-x64']!.sha256, _sha(_linuxBytes));
    });

    test('moves the old latest into previous', () async {
      final bucket = FakeBucket(
        texts: {_releasesKey: _manifestText(latest: _entry('1.1.0'))},
      );
      final result = await publishRelease(publisher(bucket));

      expect(result.latest!.version, '1.2.0');
      expect(result.previous.map((e) => e.version), ['1.1.0']);
    });

    test('a hotfix for an older line does not become the latest', () async {
      final bucket = FakeBucket(
        texts: {_releasesKey: _manifestText(latest: _entry('1.2.0'))},
      );
      final result = await publishRelease(publisher(bucket), version: '1.1.1');

      expect(result.latest!.version, '1.2.0');
      expect(result.previous.map((e) => e.version), ['1.1.1']);
      expect(
        Manifest.parse(bucket.texts[_releasesKey]!).latest!.version,
        '1.2.0',
      );
    });

    test('a trailing slash on the base URL does not double up', () async {
      final bucket = FakeBucket();
      final result = await publishRelease(
        publisher(bucket, baseUrl: '$_baseUrl/'),
      );

      expect(
        result.latest!.files['windows-x64']!.url,
        '$_baseUrl/releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      );
    });

    test('the entry date is the UTC calendar date of now', () async {
      final bucket = FakeBucket();
      // 23:30 at UTC-5 on the 3rd is already the 4th in UTC.
      final result = await publishRelease(
        publisher(bucket, now: DateTime.parse('2026-11-03T23:30:00-05:00')),
      );

      expect(result.latest!.date, '2026-11-04');
    });

    test(
      'a version that is already published is refused before any put',
      () async {
        final bucket = FakeBucket(
          texts: {_releasesKey: _manifestText(latest: _entry('1.2.0'))},
        );

        await expectLater(
          publishRelease(publisher(bucket)),
          _publishError('1.2.0'),
        );
        expect(bucket.putCalls, isEmpty);
        expect(bucket.calls.where((c) => c.startsWith('sha256Of')), isEmpty);
      },
    );

    test('force replaces an existing version', () async {
      final bucket = FakeBucket(
        texts: {_releasesKey: _manifestText(latest: _entry('1.2.0'))},
      );
      final result = await publishRelease(publisher(bucket), force: true);

      expect(result.latest!.version, '1.2.0');
      expect(result.latest!.build, 45);
      expect(result.previous, isEmpty);
      expect(bucket.textPuts, hasLength(1));
    });

    test(
      'a bad checksum after upload stops before the manifest is written',
      () async {
        final bucket = FakeBucket(
          texts: {_releasesKey: _manifestText(latest: _entry('1.1.0'))},
        );
        bucket.hashOverride['releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage'] =
            'deadbeef';

        await expectLater(
          publishRelease(publisher(bucket)),
          _publishError('Anchorline-1.2.0-linux-x64.AppImage'),
        );
        expect(bucket.textPuts, isEmpty);
        expect(
          Manifest.parse(bucket.texts[_releasesKey]!).latest!.version,
          '1.1.0',
        );
      },
    );

    test(
      'an upload that cannot be found afterwards stops before the manifest',
      () async {
        final bucket = FakeBucket();
        bucket.dropUploads.add(
          'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
        );

        await expectLater(
          publishRelease(publisher(bucket)),
          _publishError('Anchorline-1.2.0-windows-x64.exe'),
        );
        expect(bucket.textPuts, isEmpty);
      },
    );

    test(
      'an interrupted earlier run: leftover objects are overwritten',
      () async {
        // The files of 1.2.0 are in the bucket, with other bytes, but the list
        // never got 1.2.0.
        final bucket = FakeBucket(
          texts: {_releasesKey: _manifestText(latest: _entry('1.1.0'))},
        );
        bucket.objects['releases/1.2.0/Anchorline-1.2.0-windows-x64.exe'] =
            _sha('half an upload');
        bucket.objects['releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage'] =
            _sha('another half');

        final result = await publishRelease(publisher(bucket));

        expect(result.latest!.version, '1.2.0');
        expect(bucket.filePuts, hasLength(2));
        expect(bucket.textPuts, hasLength(1));
        expect(
          bucket.objects['releases/1.2.0/Anchorline-1.2.0-windows-x64.exe'],
          _sha(_winBytes),
        );
      },
    );

    test('dry run reads the list but changes nothing', () async {
      final bucket = FakeBucket(
        texts: {_releasesKey: _manifestText(latest: _entry('1.1.0'))},
      );
      final result = await publishRelease(publisher(bucket, dryRun: true));

      expect(bucket.calls, ['getText $_releasesKey']);
      expect(result.latest!.version, '1.2.0');
      expect(result.latest!.files['windows-x64']!.sha256, _sha(_winBytes));
      expect(result.previous.map((e) => e.version), ['1.1.0']);
    });

    test('dry run still refuses a version that is already published', () async {
      final bucket = FakeBucket(
        texts: {_releasesKey: _manifestText(latest: _entry('1.2.0'))},
      );

      await expectLater(
        publishRelease(publisher(bucket, dryRun: true)),
        _publishError('1.2.0'),
      );
    });

    test('a list that cannot be read is not overwritten', () async {
      final bucket = FakeBucket(texts: {_releasesKey: '{"format": 2}'});

      await expectLater(
        publishRelease(publisher(bucket)),
        _publishError('unsupported manifest format'),
      );
      expect(bucket.putCalls, isEmpty);
    });
  });

  group('publish, nightly lane', () {
    test(
      'writes nightly/manifest.json with urls under nightly/<V>-<N>/',
      () async {
        final bucket = FakeBucket();
        final result = await publishNightly(publisher(bucket));

        expect(bucket.textPuts.single.key, _nightlyKey);
        expect(bucket.texts.containsKey(_releasesKey), isFalse);
        for (final file in result.latest!.files.values) {
          expect(file.url, startsWith('$_baseUrl/nightly/1.3.0-157/'));
        }
        expect(
          result.latest!.files['macos']!.url,
          '$_baseUrl/nightly/1.3.0-157/Anchorline-Nightly-1.3.0-157-macos.dmg',
        );
        expect(result.latest!.build, 157);
        expect(result.latest!.notes, '');
      },
    );

    test('uploads in platform order with the right content types', () async {
      final bucket = FakeBucket();
      await publishNightly(
        publisher(bucket),
        // Deliberately not in platform order.
        files: {'macos': mac, 'linux-x64': linux, 'windows-x64': win},
      );

      expect(bucket.filePuts.map((p) => (p.key, p.contentType)), [
        (
          'nightly/1.3.0-157/Anchorline-Nightly-1.3.0-157-windows-x64.exe',
          'application/vnd.microsoft.portable-executable',
        ),
        (
          'nightly/1.3.0-157/Anchorline-Nightly-1.3.0-157-linux-x64.AppImage',
          'application/vnd.appimage',
        ),
        (
          'nightly/1.3.0-157/Anchorline-Nightly-1.3.0-157-macos.dmg',
          'application/x-apple-diskimage',
        ),
      ]);
      expect(bucket.calls.last, 'putText $_nightlyKey');
    });

    test('drops entries older than 14 days when it writes', () async {
      final bucket = FakeBucket(
        texts: {
          _nightlyKey: _manifestText(
            latest: _entry('1.3.0', build: 156, date: '2026-11-02'),
            previous: [_entry('1.3.0', build: 120, date: '2026-10-10')],
          ),
        },
      );
      final result = await publishNightly(publisher(bucket));

      expect(result.latest!.build, 157);
      expect(result.previous.map((e) => e.build), [156]);
    });

    test(
      'a build number that is already published is refused before any put',
      () async {
        final bucket = FakeBucket(
          texts: {
            _nightlyKey: _manifestText(latest: _entry('1.3.0', build: 157)),
          },
        );

        await expectLater(
          publishNightly(publisher(bucket)),
          _publishError('157'),
        );
        expect(bucket.putCalls, isEmpty);
      },
    );

    test('dry run changes nothing', () async {
      final bucket = FakeBucket();
      final result = await publishNightly(publisher(bucket, dryRun: true));

      expect(bucket.calls, ['getText $_nightlyKey']);
      expect(result.latest!.build, 157);
    });
  });

  group('publish refuses bad input before anything is uploaded', () {
    final cases = <String, Future<Manifest> Function(Publisher)>{
      'an unknown platform key': (p) =>
          publishRelease(p, files: {'windows-arm64': win}),
      'an unsupported file extension': (p) => publishRelease(
        p,
        files: {'windows-x64': '${tmp.path}/Anchorline.zip'},
      ),
      'a file that does not exist': (p) =>
          publishRelease(p, files: {'windows-x64': '${tmp.path}/missing.exe'}),
      'no files at all': (p) => publishRelease(p, files: {}),
      'a release version that is not X.Y.Z': (p) =>
          publishRelease(p, version: '1.2'),
      'a nightly version that is not X.Y.Z': (p) =>
          publishNightly(p, version: '1.3.0-beta'),
      'a build number of zero': (p) => publishRelease(p, build: 0),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        // Make the local file cases real: the .zip exists, the .exe does not.
        File('${tmp.path}/Anchorline.zip').writeAsStringSync('zip');
        final bucket = FakeBucket();

        await expectLater(entry.value(publisher(bucket)), _publishError());
        expect(bucket.putCalls, isEmpty);
      });
    }
  });

  group('rollback', () {
    test('writes only the manifest', () async {
      final bucket = FakeBucket(
        texts: {
          _releasesKey: _manifestText(
            latest: _entry('1.2.0'),
            previous: [_entry('1.1.0'), _entry('1.0.0')],
          ),
        },
      );
      final result = await publisher(bucket).rollback('1.1.0');

      expect(bucket.calls, ['getText $_releasesKey', 'putText $_releasesKey']);
      expect(result.latest!.version, '1.1.0');
      expect(result.previous.map((e) => e.version), ['1.2.0', '1.0.0']);

      final put = bucket.textPuts.single;
      expect(put.contentType, 'application/json');
      expect(put.cacheControl, 'no-cache');
      expect(put.text, result.encode());
    });

    test(
      'a version that is not in the list is refused before any put',
      () async {
        final bucket = FakeBucket(
          texts: {_releasesKey: _manifestText(latest: _entry('1.2.0'))},
        );

        await expectLater(
          publisher(bucket).rollback('0.9.0'),
          _publishError('0.9.0'),
        );
        expect(bucket.putCalls, isEmpty);
      },
    );

    test('with nothing published yet it is refused', () async {
      final bucket = FakeBucket();

      await expectLater(
        publisher(bucket).rollback('1.1.0'),
        _publishError('1.1.0'),
      );
      expect(bucket.putCalls, isEmpty);
    });

    test('dry run reads the list but changes nothing', () async {
      final bucket = FakeBucket(
        texts: {
          _releasesKey: _manifestText(
            latest: _entry('1.2.0'),
            previous: [_entry('1.1.0')],
          ),
        },
      );
      final result = await publisher(bucket, dryRun: true).rollback('1.1.0');

      expect(bucket.calls, ['getText $_releasesKey']);
      expect(result.latest!.version, '1.1.0');
    });
  });
}
