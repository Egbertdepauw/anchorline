import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../data/db/database.dart';
import '../data/db/dive_dao.dart';
import '../shearwater/parser/dive_converter.dart';
import '../shearwater/parser/dive_parser.dart';
import '../shearwater/parser/hardware.dart';

/// Seed the database with fixture dives for development.
///
/// Only runs in debug mode and only if the database is empty.
/// Loads fixture .bin files from bundled assets.
Future<void> seedFixtures(AppDatabase db) async {
  if (!kDebugMode) return;

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
