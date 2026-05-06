import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data/db/database.dart';
import 'dev/fixture_seeder.dart';
import 'sync/cloud/auth_service.dart';
import 'sync/cloud/cloud_config.dart';
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

  final settings = SettingsNotifier();
  await settings.load();

  final authService = AuthService(backfiller: OwnerIdBackfiller(db));

  runApp(CCRLogApp(db: db, settings: settings, authService: authService));
}

class CCRLogApp extends StatelessWidget {
  final AppDatabase db;
  final SettingsNotifier settings;
  final AuthService authService;

  const CCRLogApp({
    super.key,
    required this.db,
    required this.settings,
    required this.authService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCRLog',
      theme: AppTheme.dark(),
      home: AppShell(
        db: db,
        settingsNotifier: settings,
        authService: authService,
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}
