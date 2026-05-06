import 'dart:typed_data';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/data/models/annotation.dart' as dom;
import 'package:ccrlogger/ui/util/dive_search.dart';
import 'package:flutter_test/flutter_test.dart';

Dive _makeDive({
  int diveNumber = 718,
  int startTime = 1776591525,
}) {
  return Dive(
    id: 'test-dive-id',
    dcSerial: 123,
    dcDiveNumber: diveNumber,
    startTime: startTime,
    endTime: startTime + 3600,
    utcOffsetMinutes: null,
    durationSeconds: 3600,
    maxDepthMm: 28400,
    diveMode: 0,
    decoModel: 0,
    gfLow: 35,
    gfHigh: 75,
    atmosphericPressureMbar: 1013,
    waterDensity: 1025,
    logVersion: 14,
    dcModel: 3,
    dcFirmware: null,
    sampleIntervalMs: 10000,
    gasMixesJson: '[{"o2":21,"he":35,"dil":true}]',
    rawBlob: Uint8List(0),
    parserVersion: 1,
    importedAt: 1776591525,
  );
}

dom.DiveAnnotation _makeAnnotation({
  String? siteName,
  String? notes,
  List<String> buddies = const [],
  List<String> tags = const [],
}) {
  final now = DateTime.now();
  return dom.DiveAnnotation(
    diveId: 'test-dive-id',
    siteName: siteName,
    notes: notes,
    buddies: buddies,
    tags: tags,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('diveMatchesQuery', () {
    test('empty query matches everything', () {
      final dive = _makeDive();
      expect(diveMatchesQuery(dive, null, ''), isTrue);
      expect(diveMatchesQuery(dive, null, '   '), isTrue);
    });

    test('matches site name', () {
      final dive = _makeDive();
      final ann = _makeAnnotation(siteName: 'Deep Blue Hole');
      expect(diveMatchesQuery(dive, ann, 'deep blue'), isTrue);
      expect(diveMatchesQuery(dive, ann, 'hole'), isTrue);
    });

    test('matches buddy substring', () {
      final dive = _makeDive();
      final ann = _makeAnnotation(buddies: ['Alice Adams', 'Bob']);
      expect(diveMatchesQuery(dive, ann, 'alice'), isTrue);
      expect(diveMatchesQuery(dive, ann, 'adams'), isTrue);
    });

    test('matches dive number with hash', () {
      final dive = _makeDive(diveNumber: 718);
      expect(diveMatchesQuery(dive, null, '#718'), isTrue);
      expect(diveMatchesQuery(dive, null, '718'), isTrue);
    });

    test('matches tag', () {
      final dive = _makeDive();
      final ann = _makeAnnotation(tags: ['viz-low', 'cold']);
      expect(diveMatchesQuery(dive, ann, 'viz-low'), isTrue);
      expect(diveMatchesQuery(dive, ann, 'cold'), isTrue);
    });

    test('matches notes', () {
      final dive = _makeDive();
      final ann = _makeAnnotation(notes: 'Strong current at 30m');
      expect(diveMatchesQuery(dive, ann, 'current'), isTrue);
    });

    test('case-insensitive', () {
      final dive = _makeDive();
      final ann = _makeAnnotation(siteName: 'Zelandia');
      expect(diveMatchesQuery(dive, ann, 'ZELANDIA'), isTrue);
      expect(diveMatchesQuery(dive, ann, 'zElAnDiA'), isTrue);
    });

    test('trims whitespace', () {
      final dive = _makeDive();
      final ann = _makeAnnotation(siteName: 'Wreck');
      expect(diveMatchesQuery(dive, ann, '  wreck  '), isTrue);
    });

    test('non-match returns false', () {
      final dive = _makeDive(diveNumber: 1);
      final ann = _makeAnnotation(siteName: 'Foo', buddies: ['Bar']);
      expect(diveMatchesQuery(dive, ann, 'completely-unrelated'), isFalse);
    });

    test('no annotation still matches dive number', () {
      final dive = _makeDive(diveNumber: 42);
      expect(diveMatchesQuery(dive, null, '42'), isTrue);
      expect(diveMatchesQuery(dive, null, 'nope'), isFalse);
    });
  });
}
