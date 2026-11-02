import 'package:flutter_test/flutter_test.dart';

// tool/ci/lib is not the package's lib/ folder; the lint matches on the path.
// ignore: avoid_relative_lib_imports
import '../../../tool/ci/lib/version_rules.dart';

void main() {
  test('nightly version is the next minor of the highest tag', () {
    expect(nextNightlyVersion(['v1.1.0']).name, '1.2.0');
    expect(nextNightlyVersion(['v1.1.0', 'v1.2.0', 'v1.2.1']).name, '1.3.0');
    expect(
      nextNightlyVersion(['v1.2.0', 'v1.2.3', 'v1.10.0', 'v1.9.0']).name,
      '1.11.0',
    );
    expect(
      nextNightlyVersion(['v1.4', 'v2.0.0-beta', 'release-1', 'v1.1.0']).name,
      '1.2.0',
    );
    expect(nextNightlyVersion(<String>[]).name, '0.1.0');
  });

  test('build number is base plus run number', () {
    expect(buildNumberFor(100, 57), 157);
  });

  test('minor release on main', () {
    final p = planRelease(
      tag: TagFacts(
        'v1.2.0',
        annotated: true,
        onMain: true,
        onReleaseBranch: false,
      ),
      allTags: ['v1.1.0', 'v1.2.0'],
      publishedVersions: {'1.1.0'},
      base: 100,
      runNumber: 54,
    );
    expect(
      (p.channel, p.version, p.buildNumber, p.build),
      (Channel.release, '1.2.0', 154, true),
    );
  });

  test('hotfix on its release branch', () {
    final p = planRelease(
      tag: TagFacts(
        'v1.2.1',
        annotated: true,
        onMain: false,
        onReleaseBranch: true,
      ),
      allTags: ['v1.2.0', 'v1.2.1'],
      publishedVersions: {'1.2.0'},
      base: 100,
      runNumber: 58,
    );
    expect(p.version, '1.2.1');
  });

  test('release tag errors', () {
    void bad(TagFacts t, String msg, {Set<String> published = const {}}) =>
        expect(
          () => planRelease(
            tag: t,
            allTags: [t.name],
            publishedVersions: published,
            base: 100,
            runNumber: 1,
          ),
          throwsA(
            isA<VersionRuleError>().having(
              (e) => e.message,
              'message',
              contains(msg),
            ),
          ),
        );
    bad(
      TagFacts('v1.2', annotated: true, onMain: true, onReleaseBranch: false),
      'vX.Y.Z',
    );
    bad(
      TagFacts(
        'v1.2.0',
        annotated: false,
        onMain: true,
        onReleaseBranch: false,
      ),
      'annotated',
    );
    bad(
      TagFacts(
        'v1.2.0',
        annotated: true,
        onMain: false,
        onReleaseBranch: false,
      ),
      'must be on main',
    );
    bad(
      TagFacts('v1.2.1', annotated: true, onMain: true, onReleaseBranch: false),
      'release/1.2',
    );
    bad(
      TagFacts('v1.2.0', annotated: true, onMain: true, onReleaseBranch: false),
      'already released',
      published: {'1.2.0'},
    );
  });

  test(
    'scheduled nightly skips when main is unchanged; button always builds',
    () {
      final skip = planNightly(
        allTags: ['v1.2.0'],
        base: 100,
        runNumber: 60,
        scheduled: true,
        headSha: 'abc',
        lastDeliveredSha: 'abc',
      );
      expect(skip.build, false);
      expect(skip.reason, contains('unchanged'));
      final run = planNightly(
        allTags: ['v1.2.0'],
        base: 100,
        runNumber: 61,
        scheduled: false,
        headSha: 'abc',
        lastDeliveredSha: 'abc',
      );
      expect((run.build, run.version, run.buildNumber), (true, '1.3.0', 161));
    },
  );

  test('release checks run in order: shape, annotated, branch, published', () {
    String errorFor(TagFacts t, {Set<String> published = const {}}) {
      try {
        planRelease(
          tag: t,
          allTags: [t.name],
          publishedVersions: published,
          base: 100,
          runNumber: 1,
        );
      } on VersionRuleError catch (e) {
        return e.message;
      }
      fail('expected a VersionRuleError for ${t.name}');
    }

    expect(
      errorFor(
        TagFacts(
          'v1.2.0',
          annotated: false,
          onMain: false,
          onReleaseBranch: false,
        ),
        published: {'1.2.0'},
      ),
      contains('annotated'),
    );
    expect(
      errorFor(
        TagFacts(
          'v1.2.0',
          annotated: true,
          onMain: false,
          onReleaseBranch: false,
        ),
        published: {'1.2.0'},
      ),
      contains('must be on main'),
    );
    expect(
      errorFor(
        TagFacts(
          'v1.2.1',
          annotated: true,
          onMain: true,
          onReleaseBranch: true,
        ),
        published: {'1.2.1'},
      ),
      contains('already released'),
    );
  });

  test('a hotfix tag also reachable from main is fine on its branch', () {
    final p = planRelease(
      tag: TagFacts(
        'v1.2.1',
        annotated: true,
        onMain: true,
        onReleaseBranch: true,
      ),
      allTags: ['v1.2.0', 'v1.2.1'],
      publishedVersions: {'1.2.0'},
      base: 100,
      runNumber: 3,
    );
    expect(
      (p.channel, p.version, p.buildNumber),
      (Channel.release, '1.2.1', 103),
    );
  });

  test('versions compare numerically per component', () {
    expect(
      SemVer.parseTag('v1.10.0')!.compareTo(SemVer.parseTag('v1.9.0')!),
      1,
    );
    expect(SemVer.parseTag('v1.2.0'), SemVer.parseTag('v1.2.0'));
    expect(SemVer.parseTag('v1.2'), isNull);
    expect(SemVer.parseTag('v99999999999999999999.0.0'), isNull);
  });

  test(
    'scheduled nightly builds when main changed or nothing was delivered',
    () {
      final changed = planNightly(
        allTags: ['v1.2.0'],
        base: 100,
        runNumber: 62,
        scheduled: true,
        headSha: 'def',
        lastDeliveredSha: 'abc',
      );
      expect(changed.channel, Channel.nightly);
      expect(changed.build, true);
      final first = planNightly(
        allTags: <String>[],
        base: 100,
        runNumber: 1,
        scheduled: true,
        headSha: 'abc',
      );
      expect(
        (first.build, first.version, first.buildNumber),
        (true, '0.1.0', 101),
      );
    },
  );

  test('dry run carries the nightly version', () {
    expect(
      planDryRun(allTags: ['v1.2.0'], base: 100, runNumber: 9).version,
      '1.3.0',
    );
  });
}
