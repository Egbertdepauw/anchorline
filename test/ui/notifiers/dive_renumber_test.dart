import 'package:ccrlogger/ui/notifiers/dive_renumber.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('assigns start..start+n-1 in date order (oldest = start)', () {
    final targets = [
      (diveId: 'newest', startTime: 300),
      (diveId: 'oldest', startTime: 100),
      (diveId: 'mid', startTime: 200),
    ];
    final r = computeRenumber(targets, 482);
    expect(r['oldest'], 482);
    expect(r['mid'], 483);
    expect(r['newest'], 484);
  });

  test('single target gets the start number', () {
    expect(computeRenumber([(diveId: 'a', startTime: 5)], 1), {'a': 1});
  });

  test('empty targets → empty map', () {
    expect(computeRenumber(const [], 1), isEmpty);
  });
}
