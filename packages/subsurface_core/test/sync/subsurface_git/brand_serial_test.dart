import 'package:subsurface_core/sync/subsurface_git/brand_serial.dart';
import 'package:subsurface_core/sync/subsurface_git/subsurface_model.dart';
import 'package:test/test.dart';

void main() {
  int serial(int stored,
          {String? vendor = 'Divesoft',
          int parserVersion = kSubsurfaceImportedParserVersion,
          int? family}) =>
      brandSerialOf(
          storedSerial: stored,
          vendor: vendor,
          parserVersion: parserVersion,
          dcFamily: family);

  test('a non-Shearwater Subsurface copy undoes the hex reading', () {
    // Subsurface wrote "1234567"; the legacy reader stored it as hex.
    expect(serial(0x1234567), 1234567);
  });

  test('a stored value that is not a hex reading of digits is a mismatch', () {
    // 0xABC has no decimal-digit form; it stays as stored.
    expect(serial(0xABC), 0xABC);
  });

  test('a Shearwater or vendorless copy is unchanged', () {
    expect(serial(0xB89641E4, vendor: 'Shearwater'), 0xB89641E4);
    expect(serial(0x1234567, vendor: null), 0x1234567);
  });

  test('a "Perdix 2" copy (vendor Perdix, product 2) keeps its stored serial',
      () {
    expect(
        brandSerialOf(
            storedSerial: 0xB89641E4,
            vendor: 'Perdix',
            product: '2',
            parserVersion: kSubsurfaceImportedParserVersion,
            dcFamily: null),
        0xB89641E4);
    expect(isShearwaterByNames('Perdix', '2', null), isTrue);
    expect(isShearwaterByNames('Divesoft', 'Liberty', null), isFalse);
  });

  test('a download (version >= 0) is unchanged', () {
    expect(serial(0x1234567, parserVersion: 1), 0x1234567);
    expect(serial(0x1234567, parserVersion: 0), 0x1234567);
  });

  test('a libdivecomputer dive (family set) is unchanged', () {
    expect(serial(1234567, family: 23 << 16), 1234567);
    expect(serial(0x1234567, family: 23 << 16), 0x1234567);
  });
}
