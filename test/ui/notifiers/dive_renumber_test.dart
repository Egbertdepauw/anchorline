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

  test('computeSequence: no explicit numbers yields 1..N by chronology', () {
    final dives = [
      (diveId: 'newest', startTime: 300, userNumber: null),
      (diveId: 'oldest', startTime: 100, userNumber: null),
      (diveId: 'mid', startTime: 200, userNumber: null),
    ];
    final s = computeSequence(dives);
    expect(s['oldest'], 1);
    expect(s['mid'], 2);
    expect(s['newest'], 3);
  });

  test('computeSequence: unnumbered newer dives continue from the anchors', () {
    // The reported bug (#66): dives renumbered to 716..718, then two new
    // imports must display 719 and 720 — not their positional fallback.
    final dives = [
      (diveId: 'a', startTime: 100, userNumber: 716),
      (diveId: 'b', startTime: 200, userNumber: 717),
      (diveId: 'c', startTime: 300, userNumber: 718),
      (diveId: 'd', startTime: 400, userNumber: null),
      (diveId: 'e', startTime: 500, userNumber: null),
    ];
    final s = computeSequence(dives);
    expect(s['a'], 716);
    expect(s['b'], 717);
    expect(s['c'], 718);
    expect(s['d'], 719);
    expect(s['e'], 720);
  });

  test('computeSequence: nulls before the first anchor count 1..k', () {
    final dives = [
      (diveId: 'a', startTime: 100, userNumber: null),
      (diveId: 'b', startTime: 200, userNumber: null),
      (diveId: 'c', startTime: 300, userNumber: 500),
      (diveId: 'd', startTime: 400, userNumber: null),
    ];
    final s = computeSequence(dives);
    expect(s['a'], 1);
    expect(s['b'], 2);
    expect(s['c'], 500);
    expect(s['d'], 501);
  });

  test('computeSequence: unnumbered dive between anchors gets previous+1', () {
    // Deliberately allowed to duplicate the next anchor; the user can
    // renumber to resolve it.
    final dives = [
      (diveId: 'a', startTime: 100, userNumber: 10),
      (diveId: 'b', startTime: 200, userNumber: null),
      (diveId: 'c', startTime: 300, userNumber: 11),
    ];
    final s = computeSequence(dives);
    expect(s['a'], 10);
    expect(s['b'], 11);
    expect(s['c'], 11);
  });

  test('computeSequence: result is independent of input order', () {
    final oldestFirst = [
      (diveId: 'a', startTime: 100, userNumber: 716),
      (diveId: 'b', startTime: 200, userNumber: null),
      (diveId: 'c', startTime: 300, userNumber: null),
    ];
    final newestFirst = oldestFirst.reversed.toList();
    expect(computeSequence(newestFirst), computeSequence(oldestFirst));
    expect(computeSequence(newestFirst), {'a': 716, 'b': 717, 'c': 718});
  });

  test('computeSequence: equal start times break ties by diveId', () {
    final dives = [
      (diveId: 'b', startTime: 100, userNumber: null),
      (diveId: 'a', startTime: 100, userNumber: null),
    ];
    final s = computeSequence(dives);
    expect(s['a'], 1);
    expect(s['b'], 2);
    expect(computeSequence(dives.reversed.toList()), s);
  });
}
