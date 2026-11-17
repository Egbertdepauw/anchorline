import 'package:ccrlogger/data/import/same_dive_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

StoredDiveKey _key({
  String id = 'copy',
  String? vendor,
  int serial = 1234567,
  int diveNumber = 1,
  int startTime = 1000000,
  int parserVersion = -1,
  int? family,
  String? fingerprint,
}) =>
    StoredDiveKey(
      id: id,
      dcVendor: vendor,
      dcSerial: serial,
      dcDiveNumber: diveNumber,
      startTime: startTime,
      parserVersion: parserVersion,
      dcFamily: family,
      dcFingerprint: fingerprint,
    );

List<StoredDiveKey> _find(
  Iterable<StoredDiveKey> stored, {
  String vendor = 'Shearwater',
  int serial = 1234567,
  int start = 1000000,
  String excludeId = 'incoming',
  int? diveNumber,
  String? fingerprint,
}) =>
    findSameDive(
      vendor: vendor,
      serial: serial,
      startTimeSeconds: start,
      excludeId: excludeId,
      diveNumber: diveNumber,
      fingerprint: fingerprint,
      stored: stored,
    );

void main() {
  test('a copy 59 s apart with the same hex serial matches', () {
    expect(_find([_key(startTime: 1000059)]), hasLength(1));
  });

  test('61 s apart does not match', () {
    expect(_find([_key(startTime: 1000061)]), isEmpty);
  });

  test('a pre-phase-1 copy (NULL vendor) matches any brand', () {
    expect(_find([_key()], vendor: 'Suunto'), hasLength(1));
  });

  test('a download with NULL vendor counts as Shearwater', () {
    expect(effectiveVendor(null, 1), 'Shearwater');
    expect(effectiveVendor(null, -1), isNull);
    expect(effectiveVendor('Suunto', 1), 'Suunto');
    // A stored NULL-vendor download is Shearwater, not "any brand".
    expect(_find([_key(parserVersion: 1)], vendor: 'Suunto'), isEmpty);
    expect(_find([_key(parserVersion: 1)]), hasLength(1));
    // A NULL-vendor copy is "any brand".
    expect(_find([_key(parserVersion: -1)], vendor: 'Suunto'), hasLength(1));
  });

  test('the window at exactly 60 s matches', () {
    expect(_find([_key(startTime: 1000060)]), hasLength(1));
    expect(_find([_key(startTime: 999940)]), hasLength(1));
  });

  test('a second dive 30 s after a stored download is not matched', () {
    final stored = _key(parserVersion: 1, diveNumber: 5, startTime: 1000000);
    expect(_find([stored], start: 1000030, diveNumber: 6), isEmpty);
  });

  test('a refreshed copy (parser_version 1, same number) is matched', () {
    final stored = _key(parserVersion: 1, diveNumber: 5);
    expect(_find([stored], diveNumber: 5), hasLength(1));
  });

  test('a stored copy is matched whatever the dive number', () {
    final stored = _key(parserVersion: -1, diveNumber: 99);
    expect(_find([stored], diveNumber: 5), hasLength(1));
  });

  test('with diveNumber null a stored download in the window matches', () {
    final stored = _key(parserVersion: 1, diveNumber: 5);
    expect(_find([stored], diveNumber: null), hasLength(1));
  });

  test('a non-Shearwater copy stored with the old hex reading matches', () {
    final stored = _key(serial: 0x1234567);
    expect(_find([stored], vendor: 'Suunto', serial: 1234567), hasLength(1));
    // Shearwater has no hex reading.
    expect(_find([stored], serial: 1234567), isEmpty);
  });

  test('the incoming id itself is excluded', () {
    expect(_find([_key(id: 'incoming')]), isEmpty);
  });

  test('two copies in the window both come back', () {
    final r = _find([
      _key(id: 'a', startTime: 999980),
      _key(id: 'b', startTime: 1000020),
      _key(id: 'c', startTime: 2000000),
    ]);
    expect(r.map((k) => k.id), unorderedEquals(['a', 'b']));
  });

  test('StoredDiveKey.fromRow reads the dives columns', () {
    final k = StoredDiveKey.fromRow({
      'id': 'x',
      'dc_vendor': 'Shearwater',
      'dc_serial': 5,
      'dc_dive_number': 9,
      'start_time': 100,
      'parser_version': 2,
      'dc_family': 7,
    });
    expect(k.id, 'x');
    expect(k.dcVendor, 'Shearwater');
    expect(k.dcSerial, 5);
    expect(k.dcDiveNumber, 9);
    expect(k.startTime, 100);
    expect(k.parserVersion, 2);
    expect(k.dcFamily, 7);
    final n = StoredDiveKey.fromRow({
      'id': 'y',
      'dc_vendor': null,
      'dc_serial': 5,
      'dc_dive_number': 3,
      'start_time': 100,
      'parser_version': -1,
      'dc_family': null,
    });
    expect(n.dcVendor, isNull);
    expect(n.dcFamily, isNull);
  });

  group('fingerprint', () {
    test('a stored download with another fingerprint is not matched', () {
      final stored = _key(
          vendor: 'Suunto',
          parserVersion: 1,
          diveNumber: 0,
          family: 3,
          startTime: 1000000,
          fingerprint: 'aa11');
      expect(
          _find([stored],
              vendor: 'Suunto',
              start: 1000030,
              diveNumber: 0,
              fingerprint: 'bb22'),
          isEmpty);
    });

    test('a stored download with the same fingerprint is matched', () {
      final stored = _key(
          vendor: 'Suunto',
          parserVersion: 1,
          diveNumber: 0,
          family: 3,
          fingerprint: 'aa11');
      expect(
          _find([stored], vendor: 'Suunto', diveNumber: 0, fingerprint: 'aa11'),
          hasLength(1));
    });

    test('a stored row without a fingerprint keeps the old rule', () {
      // A Subsurface copy and a Shearwater download.
      expect(
          _find([_key(vendor: 'Suunto')],
              vendor: 'Suunto', fingerprint: 'aa11'),
          hasLength(1));
      expect(
          _find([_key(parserVersion: 1, diveNumber: 5)],
              diveNumber: 5, fingerprint: 'aa11'),
          hasLength(1));
    });

    test('an incoming dive without a fingerprint ignores a stored one', () {
      final stored = _key(parserVersion: 1, diveNumber: 5, fingerprint: 'aa11');
      expect(_find([stored], diveNumber: 5), hasLength(1));
    });

    test('the other rules still apply with an equal fingerprint', () {
      final stored = _key(
          parserVersion: 1,
          diveNumber: 0,
          startTime: 1000061,
          fingerprint: 'aa11');
      expect(_find([stored], diveNumber: 0, fingerprint: 'aa11'), isEmpty);
    });
  });
}
