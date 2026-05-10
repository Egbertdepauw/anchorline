/// Cloud sync configuration constants.
///
/// The Supabase anon key is intentionally embedded — it's a public key
/// guarded by row-level security on the Postgres side. The PowerSync
/// endpoint is read from `--dart-define=POWERSYNC_ENDPOINT=...` so
/// dev/test/prod can target different instances.
library;

class CloudConfig {
  static const supabaseUrl = 'https://pnbtiwgflfkpdqnfsoaj.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBuYnRpd2dmbGZrcGRxbmZzb2FqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzg0MjY2MjUsImV4cCI6MjA5NDAwMjYyNX0.Wag2WwI4hjRXnJDMk9ARB0zFjTcFzxapX_p6EV3PC38';

  /// PowerSync endpoint URL. Defaults to the dev instance so Xcode builds
  /// (which don't pass `--dart-define`) work out of the box. Override at
  /// `flutter build` time via `--dart-define=POWERSYNC_ENDPOINT=...` to
  /// point at staging or prod.
  static const powerSyncEndpoint = String.fromEnvironment(
    'POWERSYNC_ENDPOINT',
    defaultValue: 'https://69fb928d8d064eb85ee99fd1.powersync.journeyapps.com',
  );

  /// Base URL of the Cloudflare Worker that mints presigned R2 URLs for
  /// dive attachments (sign-upload / sign-download / delete). Defaults
  /// to the deployed dev Worker so Xcode-driven builds (which don't pass
  /// `--dart-define`) work out of the box. Override at `flutter build`
  /// time via `--dart-define=ATTACHMENTS_SIGNER_URL=…` to point at
  /// staging or prod. No trailing slash.
  static const attachmentsSignerUrl = String.fromEnvironment(
    'ATTACHMENTS_SIGNER_URL',
    defaultValue: 'https://ccrlogger-attachments.ccrlogger.workers.dev',
  );
}
