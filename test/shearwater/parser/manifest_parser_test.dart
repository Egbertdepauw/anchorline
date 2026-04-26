import 'dart:io';
import 'dart:typed_data';

import 'package:ccrlogger/shearwater/parser/manifest_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List loadManifest() {
  return File('test/fixtures/manifest.bin').readAsBytesSync();
}

void main() {
  late List<ManifestEntry> entries;

  setUpAll(() {
    final data = loadManifest();
    entries = ManifestParser.parse(data);
  });

  test('parses all valid records from the manifest', () {
    // Our trace has 230 valid dive records across 5 manifest pages
    expect(entries.where((e) => e.isValid).length, equals(230));
  });

  test('no deleted records in this manifest', () {
    expect(entries.where((e) => e.isDeleted).length, equals(0));
  });

  test('dive numbers are in decreasing order (most recent first)', () {
    final validEntries = entries.where((e) => e.isValid).toList();
    for (var i = 1; i < validEntries.length; i++) {
      expect(
        validEntries[i].diveNumber,
        lessThan(validEntries[i - 1].diveNumber),
        reason: 'Record $i should have a lower dive number than ${i - 1}',
      );
    }
  });

  test('first dive is #718 (most recent)', () {
    final first = entries.first;
    expect(first.isValid, isTrue);
    expect(first.diveNumber, equals(718));
  });

  test('last valid dive is #489', () {
    final last = entries.where((e) => e.isValid).last;
    expect(last.diveNumber, equals(489));
  });

  test('dive 718 has correct start timestamp', () {
    final dive718 = entries.firstWhere((e) => e.diveNumber == 718);
    // Fingerprint/start timestamp from offset 4: 0x69E4A356
    expect(dive718.startTimestamp, equals(0x69E4A356));
    // End timestamp from offset 8: 0x69E4B0B5
    expect(dive718.endTimestamp, equals(0x69E4B0B5));
  });

  test('dive 718 has correct address', () {
    final dive718 = entries.firstWhere((e) => e.diveNumber == 718);
    expect(dive718.address, equals(0x008A6AC0));
  });

  test('fingerprint is 4 bytes', () {
    for (final e in entries) {
      expect(e.fingerprint.length, equals(4));
    }
  });

  test('all addresses are non-zero for valid entries', () {
    for (final e in entries.where((e) => e.isValid)) {
      expect(e.address, greaterThan(0));
    }
  });

  test('start timestamps are all in reasonable range', () {
    // Dives from 2023-2026 → timestamps 1672531200 to 1798761600
    for (final e in entries.where((e) => e.isValid)) {
      expect(e.startTimestamp, greaterThan(1672531200)); // 2023-01-01
      expect(e.startTimestamp, lessThan(1798761600)); // 2027-01-01
    }
  });

  test('end timestamps are after start timestamps', () {
    for (final e in entries.where((e) => e.isValid)) {
      expect(e.endTimestamp, greaterThanOrEqualTo(e.startTimestamp),
          reason: 'Dive #${e.diveNumber}: end should be >= start');
    }
  });

  test('empty manifest returns empty list', () {
    final empty = ManifestParser.parse(Uint8List(0));
    expect(empty, isEmpty);
  });

  test('partial record (less than 32 bytes) is ignored', () {
    final short = Uint8List(16); // Less than one record
    final result = ManifestParser.parse(short);
    expect(result, isEmpty);
  });
}
