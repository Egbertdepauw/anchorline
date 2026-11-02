import 'package:ccrlogger/build_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('buildLabel', () {
    test('release shows the version and build', () {
      expect(
        buildLabel(channel: 'release', version: '1.2.0', build: '154'),
        'Anchorline 1.2.0 (154)',
      );
    });

    test('nightly shows the Nightly marker, version and build', () {
      expect(
        buildLabel(channel: 'nightly', version: '1.3.0', build: '157'),
        'Anchorline Nightly 1.3.0 (157)',
      );
    });

    test('dev without values is a development build', () {
      expect(
        buildLabel(channel: 'dev', version: '', build: ''),
        'Development build',
      );
    });

    test('nightly without values falls back to a development build', () {
      expect(
        buildLabel(channel: 'nightly', version: '', build: ''),
        'Development build',
      );
    });

    test('release without values falls back to a development build', () {
      expect(
        buildLabel(channel: 'release', version: '', build: ''),
        'Development build',
      );
    });

    test('a missing version or build alone falls back to a development build',
        () {
      expect(
        buildLabel(channel: 'release', version: '1.2.0', build: ''),
        'Development build',
      );
      expect(
        buildLabel(channel: 'nightly', version: '', build: '157'),
        'Development build',
      );
    });

    test('dev with values is still a development build', () {
      expect(
        buildLabel(channel: 'dev', version: '1.2.0', build: '154'),
        'Development build',
      );
    });
  });

  group('sentryReleaseName', () {
    test('joins bundle id, version and build', () {
      expect(
        sentryReleaseName(version: '1.2.0', build: '154'),
        'nl.despaankamer.ccrlogger@1.2.0+154',
      );
    });

    test('is null when version and build are both empty', () {
      expect(sentryReleaseName(version: '', build: ''), isNull);
    });

    test('is null when only one of version or build is empty', () {
      expect(sentryReleaseName(version: '1.2.0', build: ''), isNull);
      expect(sentryReleaseName(version: '', build: '154'), isNull);
    });
  });

  group('BuildInfo defaults (no --dart-define passed)', () {
    test('local builds are dev builds with no distribution', () {
      expect(BuildInfo.channel, 'dev');
      expect(BuildInfo.distribution, 'none');
      expect(BuildInfo.version, isEmpty);
      expect(BuildInfo.build, isEmpty);
      expect(BuildInfo.isNightly, isFalse);
      expect(BuildInfo.label, 'Development build');
      expect(BuildInfo.sentryRelease, isNull);
      // Hand-built release-mode builds keep Sentry's default environment.
      expect(BuildInfo.sentryEnvironment, isNull);
    });
  });
}
