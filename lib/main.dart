import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:git2dart/git2dart.dart' show PlatformSpecific;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/db/database.dart';
import 'data/db/equipment_dao.dart';
import 'dev/fixture_seeder.dart';
import 'sync/cloud/auth_service.dart';
import 'sync/cloud/ccrlogger_backend_connector.dart';
import 'sync/cloud/cloud_config.dart';
import 'sync/cloud/cloud_data_wiper.dart';
import 'sync/cloud/cloud_sync_coordinator.dart';
import 'sync/cloud/dives_powersync_migrator.dart';
import 'sync/cloud/powersync_database.dart';
import 'sync/cloud/usage_tracker.dart';
import 'ui/app_shell.dart';
import 'ui/notifiers/settings_notifier.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Android: libgit2 (used by the Subsurface Cloud sync feature) ships
  // without a CA bundle and Android's system trust store is at a path
  // libgit2 can't read. git2dart includes a helper that extracts a
  // bundled cacert.pem into the app's cache dir and points libgit2 at
  // it. Without this call, every clone over HTTPS fails with
  // "GIT_ERROR_SSL: the SSL certificate is invalid". No-op on
  // non-Android platforms.
  await PlatformSpecific.androidInitialize();

  await Supabase.initialize(
    url: CloudConfig.supabaseUrl,
    anonKey: CloudConfig.supabaseAnonKey,
  );

  final dbDir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dbDir.path, 'ccrlogger.sqlite'));
  final db = AppDatabase(NativeDatabase(dbFile));

  // PowerSync owns dive metadata + samples now (Phase 2.5), so the
  // seeder must run after both databases are open.
  final powerSyncDb = await openPowerSyncDatabase();

  // One-shot Drift → PowerSync migration for users upgrading from a
  // pre-2.5 build. Idempotent — safe to run on every launch.
  final session = SupabaseAuthSessionSource(Supabase.instance.client);
  await DivesPowerSyncMigrator(db, powerSyncDb, session).migrate();

  // One-shot local GC: drop dive_bailout_carry rows orphaned by a dive that no
  // longer exists anywhere. Runs before sync connects (below), on the last
  // persisted checkpoint, so it can't race a download. Idempotent — 0 rows on
  // a clean DB. Non-fatal: a failure here must never block app launch.
  try {
    final purged =
        await EquipmentDao(db, powerSyncDb, session).purgeOrphanedBailoutCarry();
    if (purged > 0) {
      debugPrint('purgeOrphanedBailoutCarry: removed $purged orphan row(s)');
    }
  } catch (e, st) {
    debugPrint('purgeOrphanedBailoutCarry failed: $e\n$st');
  }

  // Skip seeding in release builds — beta and store users land on a
  // genuinely empty dive list and import their own dives via BLE or
  // Subsurface bootstrap. Debug / profile keeps the fixtures so the
  // dev loop stays fast.
  if (!kReleaseMode) {
    await seedFixtures(
      db,
      psDb: powerSyncDb,
      session: session,
    );
  }

  final settings = SettingsNotifier();
  await settings.load();

  final authService =
      AuthService(backfiller: OwnerIdBackfiller(db, powerSyncDb));

  // Held for the app lifetime; tear-down happens at process exit. AppShell
  // calls forceReconnect() on lifecycle resume to recover from stale
  // WebSockets after Mac sleep / backgrounding.
  final cloudSyncCoordinator = CloudSyncCoordinator(
    database: powerSyncDb,
    connector: CcrloggerBackendConnector(Supabase.instance.client),
    authService: authService,
  )..start();

  final usageTracker = UsageTracker(Supabase.instance.client);

  final app = CCRLogApp(
    db: db,
    powerSyncDb: powerSyncDb,
    settings: settings,
    authService: authService,
    cloudSyncCoordinator: cloudSyncCoordinator,
    cloudDataWiper: CloudDataWiper(Supabase.instance.client),
    usageTracker: usageTracker,
  );

  // Sentry crash + unhandled-exception reporting is gated on release
  // mode only — keeps dev iterations out of the beta error stream and
  // avoids eating into the free 5 k quota. The DSN below is the
  // production Anchorline project on Sentry; it's safe to commit
  // because Sentry DSNs are designed to be public (they're embedded
  // in every shipped client and required at runtime to ingest events).
  // To point a custom build at a different project, override via
  // `flutter build ... --dart-define=SENTRY_DSN=https://...@sentry.io/...`.
  // To disable reporting entirely for a build, override with an empty
  // string: `--dart-define=SENTRY_DSN=`.
  const sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue:
        'https://8c89ac86495e4bacb457c091591a16bd@o4508376376147968.ingest.de.sentry.io/4511415503487056',
  );
  if (kReleaseMode && sentryDsn.isNotEmpty) {
    await SentryFlutter.init(
      (options) {
        options.dsn = sentryDsn;
        // Crashes + unhandled exceptions only — no performance traces.
        // tracesSampleRate: 0 keeps overhead minimal and stays inside
        // the free-tier quota for a small beta cohort.
        options.tracesSampleRate = 0;
        // Drop benign network noise the Supabase SDK reports while it's
        // retrying internally. AuthRetryableFetchException is the SDK's
        // own "this attempt failed, I'll retry" signal — the diver's
        // device just blipped offline (cell tower handoff, sleep
        // wake-up, etc.). The SDK retries and recovers without our
        // help; sending these to Sentry pollutes the dashboard with
        // events we can't action.
        options.beforeSend = (event, hint) {
          final thrown = event.throwable?.toString() ??
              event.exceptions?.firstOrNull?.type ??
              '';
          if (thrown.contains('AuthRetryableFetchException') ||
              thrown.contains('Failed host lookup') ||
              thrown.contains('SocketException')) {
            return null; // swallow
          }
          return event;
        };
      },
      appRunner: () => runApp(app),
    );
  } else {
    runApp(app);
  }
}

class CCRLogApp extends StatelessWidget {
  final AppDatabase db;
  final PowerSyncDatabase powerSyncDb;
  final SettingsNotifier settings;
  final AuthService authService;
  final CloudSyncCoordinator cloudSyncCoordinator;
  final CloudDataWiper cloudDataWiper;
  final UsageTracker usageTracker;

  const CCRLogApp({
    super.key,
    required this.db,
    required this.powerSyncDb,
    required this.settings,
    required this.authService,
    required this.cloudSyncCoordinator,
    required this.cloudDataWiper,
    required this.usageTracker,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anchorline',
      theme: AppTheme.dark(),
      home: AppShell(
        db: db,
        powerSyncDb: powerSyncDb,
        settingsNotifier: settings,
        authService: authService,
        cloudSyncCoordinator: cloudSyncCoordinator,
        cloudDataWiper: cloudDataWiper,
        usageTracker: usageTracker,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
