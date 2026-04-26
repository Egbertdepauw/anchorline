import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/db/database.dart';
import 'dev/fixture_seeder.dart';
import 'ui/app_shell.dart';
import 'ui/theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dbDir = await getApplicationDocumentsDirectory();
  final dbFile = File(p.join(dbDir.path, 'ccrlogger.sqlite'));
  final db = AppDatabase(NativeDatabase(dbFile));

  await seedFixtures(db);

  runApp(CCRLogApp(db: db));
}

class CCRLogApp extends StatelessWidget {
  final AppDatabase db;

  const CCRLogApp({super.key, required this.db});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CCRLog',
      theme: AppTheme.dark(),
      home: AppShell(db: db),
      debugShowCheckedModeBanner: false,
    );
  }
}
