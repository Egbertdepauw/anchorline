import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

// tool/publish/lib is not the package's lib/ folder; the lint matches on the
// path.
// ignore: avoid_relative_lib_imports
import '../../../tool/publish/lib/manifest.dart';

FileEntry _file(String name) =>
    FileEntry(url: 'https://dl.example/$name', size: 1000, sha256: 'ab$name');

ReleaseEntry _release(
  String version, {
  int build = 1,
  String date = '2026-11-03',
  String notes = '',
  Map<String, FileEntry>? files,
}) => ReleaseEntry(
  version: version,
  build: build,
  date: date,
  notes: notes,
  files: files ?? {'windows-x64': _file('$version-win')},
);

ReleaseEntry _nightly(int build, String date, {String version = '1.3.0'}) =>
    _release(version, build: build, date: date);

List<String> _versions(Manifest m) => [
  if (m.latest != null) m.latest!.version,
  ...m.previous.map((e) => e.version),
];

Matcher _publishError([String? containing]) => throwsA(
  isA<PublishError>().having(
    (e) => e.message,
    'message',
    containing == null ? isNotEmpty : contains(containing),
  ),
);

void main() {
  group('objectKey', () {
    test('release key', () {
      expect(
        objectKey(
          lane: Lane.releases,
          version: '1.2.0',
          build: 154,
          platformKey: 'windows-x64',
          extension: 'exe',
        ),
        'releases/1.2.0/Anchorline-1.2.0-windows-x64.exe',
      );
    });

    test('nightly key', () {
      expect(
        objectKey(
          lane: Lane.nightly,
          version: '1.3.0',
          build: 157,
          platformKey: 'linux-x64',
          extension: 'AppImage',
        ),
        'nightly/1.3.0-157/Anchorline-Nightly-1.3.0-157-linux-x64.AppImage',
      );
    });

    test('release key does not depend on the build number', () {
      String key(int build) => objectKey(
        lane: Lane.releases,
        version: '1.2.0',
        build: build,
        platformKey: 'linux-x64',
        extension: 'AppImage',
      );
      expect(key(1), key(999));
      expect(key(1), 'releases/1.2.0/Anchorline-1.2.0-linux-x64.AppImage');
    });
  });

  group('addRelease', () {
    test('first release becomes latest, previous stays empty', () {
      final m = addRelease(Manifest.empty(), _release('1.1.0'));
      expect(m.latest!.version, '1.1.0');
      expect(m.previous, isEmpty);
    });

    test('second release becomes latest, the old latest moves to previous', () {
      final first = _release('1.1.0');
      final m = addRelease(
        addRelease(Manifest.empty(), first),
        _release('1.2.0'),
      );
      expect(m.latest!.version, '1.2.0');
      expect(m.previous, hasLength(1));
      expect(m.previous.single, same(first));
    });

    test('a version already in latest is rejected', () {
      final m = addRelease(Manifest.empty(), _release('1.1.0'));
      expect(
        () => addRelease(m, _release('1.1.0', build: 2)),
        _publishError('already published'),
      );
    });

    test('a version already in previous is rejected', () {
      final m = addRelease(
        addRelease(Manifest.empty(), _release('1.1.0')),
        _release('1.2.0'),
      );
      expect(
        () => addRelease(m, _release('1.1.0', build: 2)),
        _publishError('already published'),
      );
    });

    test('force replaces the latest entry and it stays latest', () {
      final m = addRelease(
        addRelease(Manifest.empty(), _release('1.1.0', build: 1)),
        _release('1.2.0', build: 2),
      );
      final replaced = addRelease(
        m,
        _release('1.2.0', build: 3, notes: 'redo'),
        force: true,
      );
      expect(_versions(replaced), ['1.2.0', '1.1.0']);
      expect(replaced.latest!.build, 3);
      expect(replaced.latest!.notes, 'redo');
    });

    test('force replaces a previous entry in place, keeping its position', () {
      var m = Manifest.empty();
      for (final v in ['1.1.0', '1.2.0', '1.3.0']) {
        m = addRelease(m, _release(v, build: 1));
      }
      expect(_versions(m), ['1.3.0', '1.2.0', '1.1.0']);

      final replaced = addRelease(m, _release('1.2.0', build: 9), force: true);
      expect(_versions(replaced), ['1.3.0', '1.2.0', '1.1.0']);
      expect(replaced.previous[0].build, 9);
      expect(replaced.latest!.version, '1.3.0');
    });

    test('force with an unpublished version just adds it', () {
      final m = addRelease(Manifest.empty(), _release('1.1.0'));
      final next = addRelease(m, _release('1.2.0'), force: true);
      expect(_versions(next), ['1.2.0', '1.1.0']);
    });

    test('returns a new manifest and leaves the input untouched', () {
      final m = addRelease(Manifest.empty(), _release('1.1.0'));
      final before = m.encode();
      final next = addRelease(m, _release('1.2.0'));
      expect(next, isNot(same(m)));
      expect(m.encode(), before);
    });
  });

  group('addNightly', () {
    final now = DateTime.utc(2026, 11, 20, 4, 30);

    test('first nightly becomes latest', () {
      final m = addNightly(
        Manifest.empty(),
        _nightly(157, '2026-11-20'),
        now: now,
      );
      expect(m.latest!.build, 157);
      expect(m.previous, isEmpty);
    });

    test('the old latest moves to previous', () {
      var m = addNightly(
        Manifest.empty(),
        _nightly(157, '2026-11-19'),
        now: now,
      );
      m = addNightly(m, _nightly(158, '2026-11-20'), now: now);
      expect(m.latest!.build, 158);
      expect(m.previous.map((e) => e.build), [157]);
    });

    test('the same build number twice is rejected', () {
      final m = addNightly(
        Manifest.empty(),
        _nightly(157, '2026-11-20'),
        now: now,
      );
      expect(
        () => addNightly(m, _nightly(157, '2026-11-20'), now: now),
        _publishError('157'),
      );
    });

    test('a build number already in previous is rejected too', () {
      var m = addNightly(
        Manifest.empty(),
        _nightly(157, '2026-11-19'),
        now: now,
      );
      m = addNightly(m, _nightly(158, '2026-11-20'), now: now);
      expect(
        () => addNightly(m, _nightly(157, '2026-11-20'), now: now),
        _publishError(),
      );
    });

    test('prunes previous entries older than 14 days (calendar dates)', () {
      final m = Manifest(
        latest: _nightly(150, '2026-11-19'),
        previous: [
          _nightly(149, '2026-11-18'),
          _nightly(148, '2026-11-06'), // exactly 14 days back: kept
          _nightly(147, '2026-11-05'), // 15 days back: dropped
          _nightly(146, '2026-10-01'), // dropped
        ],
      );
      final next = addNightly(m, _nightly(151, '2026-11-20'), now: now);
      expect(next.latest!.build, 151);
      expect(next.previous.map((e) => e.build), [150, 149, 148]);
    });

    test('pruning compares calendar dates in UTC, not instants', () {
      // 23:59:59 UTC on the 20th and 00:00:01 UTC on the 20th both keep the
      // 6th and drop the 5th.
      for (final instant in [
        DateTime.utc(2026, 11, 20, 23, 59, 59),
        DateTime.utc(2026, 11, 20, 0, 0, 1),
      ]) {
        final m = Manifest(
          latest: _nightly(150, '2026-11-19'),
          previous: [_nightly(149, '2026-11-06'), _nightly(148, '2026-11-05')],
        );
        final next = addNightly(m, _nightly(151, '2026-11-20'), now: instant);
        expect(next.previous.map((e) => e.build), [
          150,
          149,
        ], reason: '$instant');
      }
    });

    test('a non-UTC now is converted to UTC before taking the date', () {
      // 2026-11-20 01:00 at +05:00 is 2026-11-19 20:00 UTC, so the cutoff is
      // 2026-11-05 and that day is still kept.
      final local = DateTime.parse('2026-11-20T01:00:00+05:00');
      final m = Manifest(
        latest: _nightly(150, '2026-11-19'),
        previous: [_nightly(149, '2026-11-05'), _nightly(148, '2026-11-04')],
      );
      final next = addNightly(m, _nightly(151, '2026-11-20'), now: local);
      expect(next.previous.map((e) => e.build), [150, 149]);
    });

    test('keep is configurable', () {
      final m = Manifest(
        latest: _nightly(150, '2026-11-19'),
        previous: [_nightly(149, '2026-11-17'), _nightly(148, '2026-11-16')],
      );
      final next = addNightly(
        m,
        _nightly(151, '2026-11-20'),
        now: now,
        keep: const Duration(days: 3),
      );
      expect(next.previous.map((e) => e.build), [150, 149]);
    });

    test('the new latest is never pruned, whatever its date', () {
      final next = addNightly(
        Manifest.empty(),
        _nightly(151, '2020-01-01'),
        now: now,
      );
      expect(next.latest!.build, 151);
    });

    test('returns a new manifest and leaves the input untouched', () {
      final m = addNightly(
        Manifest.empty(),
        _nightly(157, '2026-11-19'),
        now: now,
      );
      final before = m.encode();
      addNightly(m, _nightly(158, '2026-11-20'), now: now);
      expect(m.encode(), before);
    });
  });

  group('rollback', () {
    Manifest threeReleases() {
      var m = Manifest.empty();
      for (final v in ['1.0.0', '1.1.0', '1.2.0']) {
        m = addRelease(m, _release(v));
      }
      return m; // latest 1.2.0, previous [1.1.0, 1.0.0]
    }

    test('makes the chosen version latest and keeps every entry once', () {
      final m = rollback(threeReleases(), '1.1.0');
      expect(m.latest!.version, '1.1.0');
      expect(m.previous.first.version, '1.2.0');
      expect(_versions(m), ['1.1.0', '1.2.0', '1.0.0']);
      expect(_versions(m).toSet(), {'1.0.0', '1.1.0', '1.2.0'});
    });

    test('rolling back to an older previous keeps the others in order', () {
      final m = rollback(threeReleases(), '1.0.0');
      expect(_versions(m), ['1.0.0', '1.2.0', '1.1.0']);
    });

    test('an unknown version is rejected', () {
      expect(() => rollback(threeReleases(), '9.9.9'), _publishError('9.9.9'));
    });

    test('rolling back to the current latest is rejected', () {
      expect(() => rollback(threeReleases(), '1.2.0'), _publishError('1.2.0'));
    });

    test('an empty manifest has nothing to roll back to', () {
      expect(() => rollback(Manifest.empty(), '1.0.0'), _publishError());
    });

    test('returns a new manifest and leaves the input untouched', () {
      final m = threeReleases();
      final before = m.encode();
      rollback(m, '1.1.0');
      expect(m.encode(), before);
    });
  });

  group('parse and encode', () {
    test('format 2 is rejected', () {
      expect(() => Manifest.parse('{"format":2}'), _publishError('format'));
    });

    test('a missing format is rejected', () {
      expect(() => Manifest.parse('{"latest":null}'), _publishError('format'));
    });

    test('malformed JSON is a PublishError, not a FormatException', () {
      expect(() => Manifest.parse('{not json'), _publishError());
      expect(() => Manifest.parse(''), _publishError());
    });

    test('JSON that is not an object is rejected', () {
      expect(() => Manifest.parse('[]'), _publishError());
      expect(() => Manifest.parse('"x"'), _publishError());
    });

    test('missing required entry fields are rejected', () {
      String latest(Map<String, Object?> entry) =>
          jsonEncode({'format': 1, 'latest': entry, 'previous': <Object?>[]});
      final good = <String, Object?>{
        'version': '1.0.0',
        'build': 1,
        'date': '2026-11-03',
        'notes': '',
        'files': <String, Object?>{},
      };
      expect(() => Manifest.parse(latest(good)), returnsNormally);
      for (final key in ['version', 'build', 'date', 'files']) {
        final bad = Map<String, Object?>.of(good)..remove(key);
        expect(
          () => Manifest.parse(latest(bad)),
          _publishError(key),
          reason: 'missing $key',
        );
      }
    });

    test('wrong field types and malformed dates are rejected', () {
      Map<String, Object?> entry(String key, Object? value) => {
        'version': '1.0.0',
        'build': 1,
        'date': '2026-11-03',
        'notes': '',
        'files': <String, Object?>{},
        key: value,
      };
      String doc(Map<String, Object?> e) =>
          jsonEncode({'format': 1, 'latest': e, 'previous': <Object?>[]});

      expect(() => Manifest.parse(doc(entry('build', '1'))), _publishError());
      expect(() => Manifest.parse(doc(entry('version', 1))), _publishError());
      expect(() => Manifest.parse(doc(entry('files', []))), _publishError());
      expect(
        () => Manifest.parse(doc(entry('date', 'yesterday'))),
        _publishError(),
      );
      expect(
        () => Manifest.parse(doc(entry('date', '2026-02-31'))),
        _publishError(),
      );
      expect(
        () => Manifest.parse(
          doc(
            entry('files', {
              'macos': {'url': 'u', 'size': '12', 'sha256': 'x'},
            }),
          ),
        ),
        _publishError('macos'),
      );
      expect(
        () => Manifest.parse(
          jsonEncode({'format': 1, 'latest': null, 'previous': 'x'}),
        ),
        _publishError(),
      );
    });

    test('an empty list round-trips with latest written as null', () {
      final text = Manifest.empty().encode();
      expect(
        text,
        '{\n  "format": 1,\n  "latest": null,\n  "previous": []\n}\n',
      );
      final back = Manifest.parse(text);
      expect(back.latest, isNull);
      expect(back.previous, isEmpty);
    });

    test('latest may be absent and previous may be absent', () {
      final m = Manifest.parse('{"format":1}');
      expect(m.latest, isNull);
      expect(m.previous, isEmpty);
    });

    test('encode writes the documented layout with a stable key order', () {
      final m = Manifest(
        latest: ReleaseEntry(
          version: '1.2.0',
          build: 45,
          date: '2026-11-03',
          notes: 'Markdown notes',
          files: {
            'windows-x64': const FileEntry(
              url: 'https://dl.example/releases/1.2.0/a.exe',
              size: 48211200,
              sha256: 'aa',
            ),
          },
        ),
        previous: [
          ReleaseEntry(
            version: '1.1.0',
            build: 41,
            date: '2026-10-01',
            notes: '',
            files: const {},
          ),
        ],
      );
      expect(m.encode(), '''
{
  "format": 1,
  "latest": {
    "version": "1.2.0",
    "build": 45,
    "date": "2026-11-03",
    "notes": "Markdown notes",
    "files": {
      "windows-x64": {
        "url": "https://dl.example/releases/1.2.0/a.exe",
        "size": 48211200,
        "sha256": "aa"
      }
    }
  },
  "previous": [
    {
      "version": "1.1.0",
      "build": 41,
      "date": "2026-10-01",
      "notes": "",
      "files": {}
    }
  ]
}
''');
    });

    test(
      'parse accepts what encode writes and a second encode is identical',
      () {
        var m = Manifest.empty();
        for (final v in ['1.0.0', '1.1.0', '1.2.0']) {
          m = addRelease(m, _release(v, notes: 'Notes for $v\nwith "quotes"'));
        }
        final text = m.encode();
        expect(Manifest.parse(text).encode(), text);
      },
    );

    test(
      'entries without notes (as in the spec example) parse with empty notes',
      () {
        final m = Manifest.parse(
          '{"format":1,"previous":[{"version":"1.1.0","build":41,'
          '"date":"2026-10-01","files":{}}]}',
        );
        expect(m.previous.single.notes, '');
      },
    );

    test('an unknown files key survives a round trip', () {
      const input = '''
{
  "format": 1,
  "latest": {
    "version": "1.2.0",
    "build": 45,
    "date": "2026-11-03",
    "notes": "",
    "files": {
      "windows-x64": {
        "url": "https://dl.example/w.exe",
        "size": 1,
        "sha256": "aa"
      },
      "macos-universal": {
        "url": "https://dl.example/m.dmg",
        "size": 2,
        "sha256": "bb"
      }
    }
  },
  "previous": []
}
''';
      final m = Manifest.parse(input);
      expect(m.latest!.files.keys, ['windows-x64', 'macos-universal']);
      final out = Manifest.parse(m.encode());
      expect(
        out.latest!.files['macos-universal']!.url,
        'https://dl.example/m.dmg',
      );
      expect(out.latest!.files['macos-universal']!.size, 2);
      expect(out.latest!.files['macos-universal']!.sha256, 'bb');
      expect(m.encode(), input);
    });
  });

  group('immutability', () {
    test('manifest and entry collections cannot be modified', () {
      final m = addRelease(
        addRelease(Manifest.empty(), _release('1.1.0')),
        _release('1.2.0'),
      );
      expect(() => m.previous.add(_release('9.9.9')), throwsUnsupportedError);
      expect(() => m.previous.clear(), throwsUnsupportedError);
      expect(
        () => m.latest!.files['linux-x64'] = _file('x'),
        throwsUnsupportedError,
      );
    });

    test('collections handed to the constructors are copied', () {
      final files = {'macos': _file('a')};
      final entry = _release('1.0.0', files: files);
      files['linux-x64'] = _file('b');
      expect(entry.files.keys, ['macos']);

      final previous = [_release('0.9.0')];
      final m = Manifest(latest: entry, previous: previous);
      previous.add(_release('0.8.0'));
      expect(m.previous, hasLength(1));
    });
  });
}
