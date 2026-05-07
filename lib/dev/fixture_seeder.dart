import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/db/database.dart';
import '../data/db/dive_dao.dart';
import '../shearwater/parser/dive_converter.dart';
import '../shearwater/parser/dive_parser.dart';
import '../shearwater/parser/hardware.dart';

/// SharedPreferences key flipped to `true` after the user runs the
/// Settings → Danger zone reset. Future launches will see an empty
/// database AND this flag, and skip the seed so fixtures don't come
/// rushing back. Reinstalling the app clears the flag (fresh install
/// → fixtures appear once, as before).
const _kFixturesBlockedAfterReset = 'fixtures_blocked_after_reset';

/// Records that the user has reset their data — future calls to
/// [seedFixtures] will then no-op even when the database is empty.
Future<void> markFixturesBlocked() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kFixturesBlockedAfterReset, true);
}

/// Seed the database with fixture dives for development.
///
/// Runs on any build mode but only when the database is empty AND the
/// user hasn't explicitly reset their data. Pre-public-release we'll
/// also gate this behind a --dart-define so a fresh install in real
/// users' hands doesn't show fake dives.
Future<void> seedFixtures(AppDatabase db) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_kFixturesBlockedAfterReset) ?? false) return;

  final dao = DiveDao(db);
  final dives = await dao.getAllDives();
  if (dives.isNotEmpty) return;

  const diveNumbers = [711, 712, 713, 714, 715, 716, 717, 718];
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);
  var seeded = 0;

  for (final num in diveNumbers) {
    try {
      final ByteData byteData =
          await rootBundle.load('test/fixtures/dives/dive_$num.bin');
      final rawBlob = byteData.buffer.asUint8List();

      final parsed = parser.parse(rawBlob);
      final converted = DiveConverter.convert(
        parsed: parsed,
        dcSerial: 0xB89641E4,
        dcDiveNumber: num,
        dcModel: ShearwaterModel.petrel3,
      );

      await dao.importDive(
        converted: converted,
        rawBlob: rawBlob,
        parserVersion: 1,
      );
      seeded++;
    } catch (e) {
      debugPrint('Failed to seed dive $num: $e');
    }
  }

  debugPrint('Seeded $seeded fixture dives');
}
