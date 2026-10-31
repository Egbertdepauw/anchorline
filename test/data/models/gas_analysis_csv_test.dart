import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/data/models/gas_analysis_csv.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('header matches the prototype columns', () {
    expect(
        gasAnalysesToCsv(const []),
        '"time","cylinder","diver","mix","o2","he","mod_1_1","mod_1_4",'
        '"mod_1_6","pressure_bar","temp_c","stable"\n');
  });

  test('rows: whole-number mix, one-decimal values, derived MODs', () {
    final csv = gasAnalysesToCsv([
      GasAnalysis(
        id: '1',
        cylinderId: 'c1',
        cylinderLabel: 'S80 "left"',
        analysedBy: 'Egbert',
        analysedAt: DateTime.utc(2026, 10, 30, 18, 5),
        o2Percent: 21.4,
        hePercent: 34.6,
        fillPressureBar: 232,
        tempC: 21.36,
        stable: true,
      ),
      GasAnalysis(
        id: '2',
        analysedAt: DateTime.utc(2026, 10, 29),
        o2Percent: 100,
        hePercent: 0,
        stable: false,
      ),
    ]);
    final lines = csv.trimRight().split('\n');
    expect(lines, hasLength(3));
    // MOD 1.1 = (1.1/0.214 − 1)·10 = 41.4; 1.4 → 55.4; 1.6 → 64.8.
    expect(
        lines[1],
        '"2026-10-30T18:05:00.000Z","S80 ""left""","Egbert","Tx21/35",'
        '"21.4","34.6","41.4","55.4","64.8","232.0","21.4","true"');
    // Pure O2: MODs 1 / 4 / 6 m; no cylinder, no pressure → blank.
    expect(
        lines[2],
        '"2026-10-29T00:00:00.000Z","","","O2","100.0","0.0","1.0","4.0",'
        '"6.0","","","false"');
  });

  test('mod ppO2 set round-trips and tolerates garbage', () {
    expect(decodeModPpo2s(encodeModPpo2s(const [1.1, 1.4, 1.6])),
        [1.1, 1.4, 1.6]);
    expect(decodeModPpo2s(null), isEmpty);
    expect(decodeModPpo2s('not json'), isEmpty);
    expect(decodeModPpo2s('{"a":1}'), isEmpty);
  });
}
