import 'package:ccrlogger/analysis/stats/stats_result.dart';
import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/db/dive_derived_stats_dao.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late DiveDerivedStatsDao dao;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    dao = DiveDerivedStatsDao(db);
  });
  tearDown(() async => db.close());

  test('upsertAll then getByIds round-trips values', () async {
    await dao.upsertAll([
      (diveId: 'a', parserVersion: 1,
       stats: const DerivedStats(minWaterTempC: 4.0, maxWaterTempC: 12.0, timeInDecoSeconds: 600)),
      (diveId: 'b', parserVersion: 1,
       stats: const DerivedStats(minWaterTempC: null, maxWaterTempC: null, timeInDecoSeconds: 0)),
    ]);
    final got = await dao.getByIds(['a', 'b', 'missing']);
    expect(got.length, 2);
    expect(got['a']!.parserVersion, 1);
    expect(got['a']!.stats.minWaterTempC, 4.0);
    expect(got['a']!.stats.timeInDecoSeconds, 600);
    expect(got['b']!.stats.minWaterTempC, isNull);
    expect(got.containsKey('missing'), isFalse);
  });

  test('upsertAll updates an existing row (parser-version bump)', () async {
    await dao.upsertAll([
      (diveId: 'a', parserVersion: 1,
       stats: const DerivedStats(minWaterTempC: 4.0, timeInDecoSeconds: 600)),
    ]);
    await dao.upsertAll([
      (diveId: 'a', parserVersion: 2,
       stats: const DerivedStats(minWaterTempC: 5.5, timeInDecoSeconds: 720)),
    ]);
    final got = await dao.getByIds(['a']);
    expect(got['a']!.parserVersion, 2);
    expect(got['a']!.stats.minWaterTempC, 5.5);
    expect(got['a']!.stats.timeInDecoSeconds, 720);
  });

  test('getByIds returns empty for empty input', () async {
    expect(await dao.getByIds([]), isEmpty);
  });
}
