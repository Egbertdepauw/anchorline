import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:powersync/powersync.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/db/database.dart';
import 'dev/fixture_seeder.dart';
import 'sync/cloud/auth_service.dart';
import 'sync/cloud/ccrlogger_backend_connector.dart';
import 'sync/cloud/cloud_config.dart';
import 'sync/cloud/cloud_data_wiper.dart';
import 'sync/cloud/cloud_sync_coordinator.dart';
import 'sync/cloud/powersync_database.dart';
import 'ui/app_shell.dart';
import 'ui/notifiers/settings_notifier.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: CloudConfig.supabaseUrl,
    anonKey: CloudConfig.supabaseAnonKey,
  );

  final dbDir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dbDir.path, 'ccrlogger.sqlite'));
  final db = AppDatabase(NativeDatabase(dbFile));

  await seedFixtures(db);

  final powerSyncDb = await openPowerSyncDatabase();

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

  runApp(CCRLogApp(
    db: db,
    powerSyncDb: powerSyncDb,
    settings: settings,
    authService: authService,
    cloudSyncCoordinator: cloudSyncCoordinator,
    cloudDataWiper: CloudDataWiper(Supabase.instance.client),
  ));
}

class CCRLogApp extends StatelessWidget {
  final AppDatabase db;
  final PowerSyncDatabase powerSyncDb;
  final SettingsNotifier settings;
  final AuthService authService;
  final CloudSyncCoordinator cloudSyncCoordinator;
  final CloudDataWiper cloudDataWiper;

  const CCRLogApp({
    super.key,
    required this.db,
    required this.powerSyncDb,
    required this.settings,
    required this.authService,
    required this.cloudSyncCoordinator,
    required this.cloudDataWiper,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCRLog',
      theme: AppTheme.dark(),
      home: AppShell(
        db: db,
        powerSyncDb: powerSyncDb,
        settingsNotifier: settings,
        authService: authService,
        cloudSyncCoordinator: cloudSyncCoordinator,
        cloudDataWiper: cloudDataWiper,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
