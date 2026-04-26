import 'dart:io';

import 'package:flutter/foundation.dart';

import '../data/db/database.dart';
import '../data/db/dive_dao.dart';
import '../shearwater/parser/dive_converter.dart';
import '../shearwater/parser/dive_parser.dart';
import '../shearwater/parser/hardware.dart';

Future<void> seedFixtures(AppDatabase db) async {
  if (!kDebugMode) return;

  final dao = DiveDao(db);
  final dives = await dao.getAllDives();
  if (dives.isNotEmpty) return;

  const diveNumbers = [711, 712, 713, 714, 715, 716, 717, 718];
  final parser = ShearwaterDiveParser(model: ShearwaterModel.petrel3);

  for (final num in diveNumbers) {
    final file = File('test/fixtures/dives/dive_$num.bin');
    if (!file.existsSync()) continue;

    final rawBlob = file.readAsBytesSync();
    final parsed = parser.parse(rawBlob);
    final converted = DiveConverter.convert(
      parsed: parsed,
      dcSerial: 0xB89641E4,
      dcDiveNumber: num,
      dcModel: ShearwaterModel.petrel3,
    );

    await dao.importDive(converted: converted, rawBlob: rawBlob, parserVersion: 1);
  }

  debugPrint('Seeded ${diveNumbers.length} fixture dives');
}
