import 'package:ccrlogger/devices/libdc/libdc_ble_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:libdivecomputer/libdivecomputer.dart';

LibdcDescriptor _desc(int family) => LibdcDescriptor(
  vendor: 'Test',
  product: 'Test',
  family: family,
  model: 1,
  transports: 0,
);

void main() {
  test('HW OSTC3 gets Telit credits; other families get none', () {
    expect(
      libdcProfileFor(_desc(dc_family_t.DC_FAMILY_HW_OSTC3)).flowControl,
      LibdcFlowControl.telitCredits,
    );
    expect(
      libdcProfileFor(_desc(dc_family_t.DC_FAMILY_MARES_ICONHD)).flowControl,
      LibdcFlowControl.none,
    );
  });

  test('an unknown or unlisted family gets the generic profile, no throw', () {
    for (final family in [0, 0x7fffffff, -1]) {
      final p = libdcProfileFor(_desc(family));
      expect(p.flowControl, LibdcFlowControl.none);
      expect(p.preferredServices, kLibdcKnownServices);
    }
  });

  test('known services keep the priority order, Cressi before Nordic', () {
    final s = kLibdcKnownServices;
    expect(s.first, '0000fefb-0000-1000-8000-00805f9b34fb');
    expect(
      s.indexOf('6e400001-b5a3-f393-e0a9-e50e24dc10b8'),
      lessThan(s.indexOf('6e400001-b5a3-f393-e0a9-e50e24dcca9e')),
    );
    expect(s.last, '84968ffe-d26d-478a-b953-5010bcf58bca');
    expect(s, hasLength(12));
  });

  test('the ignore lists carry the Halcyon and McLean characteristics', () {
    final p = libdcProfileFor(_desc(0));
    expect(p.ignoreForRead, contains('00000101-8c3b-4f2c-a59e-8c08224f3253'));
    expect(p.ignoreForWrite, contains('00000201-8c3b-4f2c-a59e-8c08224f3253'));
    for (final u in [
      '49535343-6daa-4d02-abf6-19569aca69fe',
      '49535343-aca3-481c-91ec-d85e28a60318',
      '49535343-026e-3a9b-954c-97daef17e26e',
      '49535343-4c8a-39b3-2f49-511cff073b7e',
    ]) {
      expect(p.ignoreForRead, contains(u));
      expect(p.ignoreForWrite, contains(u));
    }
  });
}
