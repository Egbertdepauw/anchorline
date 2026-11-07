import 'package:intl/intl.dart';

/// What this binary is: which release channel, how it is distributed, and its
/// version and build number.
///
/// CI passes these as `--dart-define`s. Local builds pass none, so they report
/// the `dev` channel and an empty version.
class BuildInfo {
  BuildInfo._();

  /// `release`, `nightly`, or `dev` for builds that were not made by CI.
  static const channel = String.fromEnvironment(
    'BUILD_CHANNEL',
    defaultValue: 'dev',
  );

  /// `app_store`, `play_store`, `website`, or `none` for local builds.
  static const distribution = String.fromEnvironment(
    'DISTRIBUTION_CHANNEL',
    defaultValue: 'none',
  );

  /// Marketing version, e.g. `1.2.0`. Empty for local builds.
  static const version = String.fromEnvironment('APP_VERSION');

  /// Build number, e.g. `154`. Empty for local builds.
  static const build = String.fromEnvironment('APP_BUILD');

  /// UTC date of the build as `yyyy-MM-dd`, e.g. `2026-11-06`. Empty when the
  /// build did not pass it.
  static const buildDate = String.fromEnvironment('APP_BUILD_DATE');

  static const _channelDefined = bool.hasEnvironment('BUILD_CHANNEL');

  static bool get isNightly => channel == 'nightly';

  /// Human-readable version line for the Settings screen.
  static String get label =>
      buildLabel(channel: channel, version: version, build: build);

  /// Sentry release name, or null when this build has no version information.
  static String? get sentryRelease =>
      sentryReleaseName(version: version, build: build);

  /// Sentry environment, or null when no `BUILD_CHANNEL` was passed. Sentry
  /// only runs in release mode, so such a build is a hand-built store or
  /// website build, not a developer's: it keeps Sentry's default environment
  /// (`production`) instead of reporting as `dev`.
  static String? get sentryEnvironment => _channelDefined ? channel : null;
}

/// The version line shown to the user. Only CI channels with a complete
/// version and build number get a real label; everything else is a
/// development build.
String buildLabel({
  required String channel,
  required String version,
  required String build,
}) {
  if (version.isEmpty || build.isEmpty) return 'Development build';
  switch (channel) {
    case 'release':
      return 'Anchorline $version ($build)';
    case 'nightly':
      return 'Anchorline Nightly $version ($build)';
    default:
      return 'Development build';
  }
}

/// `nl.despaankamer.ccrlogger@<version>+<build>`, or null if either part is
/// missing.
String? sentryReleaseName({required String version, required String build}) {
  if (version.isEmpty || build.isEmpty) return null;
  return 'nl.despaankamer.ccrlogger@$version+$build';
}

/// `2026-11-06` as `6 Nov 2026` (English month names whatever the device
/// locale), or null for an empty or malformed date.
String? formatBuildDate(String raw) {
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return null;
  final parsed = DateTime.tryParse(raw);
  if (parsed == null || parsed.toIso8601String().substring(0, 10) != raw) {
    return null;
  }
  return DateFormat('d MMM yyyy', 'en_US').format(parsed);
}

/// The release channel as the About tab names it.
String channelLabel(String channel) {
  switch (channel) {
    case 'release':
      return 'Release';
    case 'nightly':
      return 'Nightly';
    default:
      return 'Development';
  }
}
