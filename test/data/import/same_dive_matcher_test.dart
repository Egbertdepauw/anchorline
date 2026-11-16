import 'package:ccrlogger/data/import/same_dive_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

StoredDiveKey _key({
  String id = 'copy',
  String? vendor,
  int serial = 1234567,
  int startTime = 1000000,
  int parserVersion = -1,
  int? family,
}) =>
    StoredDiveKey(
      id: id,
      dcVendor: vendor,
      dcSerial: serial,
      startTime: startTime,
      parserVersion: parserVersion,
      dcFamily: family,
    );

List<StoredDiveKey> _find(
  Iterable<StoredDiveKey> stored, {
  String vendor = 'Shearwater',
  int serial = 1234567,
  int start = 1000000,
  String excludeId = 'incoming',
}) =>
    findSameDive(
      vendor: vendor,
      serial: serial,
      startTimeSeconds: start,
      excludeId: excludeId,
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
    expect(effectiveVendor(null, 1), isNull);
    expect(effectiveVendor('Shearwater', 1), 'Shearwater');
    // A row from another brand does not match a Shearwater download.
    expect(_find([_key(vendor: 'Suunto', parserVersion: 3)]), isEmpty);
    expect(
        _find([_key(vendor: 'Shearwater', parserVersion: 1)]), hasLength(1));
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
      'start_time': 100,
      'parser_version': 2,
      'dc_family': 7,
    });
    expect(k.id, 'x');
    expect(k.dcVendor, 'Shearwater');
    expect(k.dcSerial, 5);
    expect(k.startTime, 100);
    expect(k.parserVersion, 2);
    expect(k.dcFamily, 7);
    final n = StoredDiveKey.fromRow({
      'id': 'y',
      'dc_vendor': null,
      'dc_serial': 5,
      'start_time': 100,
      'parser_version': -1,
      'dc_family': null,
    });
    expect(n.dcVendor, isNull);
    expect(n.dcFamily, isNull);
  });
}
