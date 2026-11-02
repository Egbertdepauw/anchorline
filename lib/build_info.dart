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

  static bool get isNightly => channel == 'nightly';

  /// Human-readable version line for the Settings screen.
  static String get label =>
      buildLabel(channel: channel, version: version, build: build);

  /// Sentry release name, or null when this build has no version information.
  static String? get sentryRelease =>
      sentryReleaseName(version: version, build: build);
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
