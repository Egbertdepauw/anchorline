/// Cloud sync configuration constants.
///
/// The Supabase anon key is intentionally embedded — it's a public key
/// guarded by row-level security on the Postgres side. The PowerSync
/// endpoint is read from `--dart-define=POWERSYNC_ENDPOINT=...` so
/// dev/test/prod can target different instances.
library;

class CloudConfig {
  static const supabaseUrl = 'https://eijknwqahweddpzcxhtr.supabase.co';
  static const supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVpamtud3FhaHdlZGRwemN4aHRyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzgwODQxNzQsImV4cCI6MjA5MzY2MDE3NH0.XDKIPITMF6st7JiPlYipB5aHCyLk_iMLi0upwnId4kI';

  /// PowerSync endpoint URL. Empty until the user provisions the instance
  /// and passes `--dart-define=POWERSYNC_ENDPOINT=...` at build time.
  static const powerSyncEndpoint = String.fromEnvironment(
    'POWERSYNC_ENDPOINT',
    defaultValue: '',
  );
}
