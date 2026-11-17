/// Which GATT service and characteristics a libdivecomputer download talks
/// to, and how data is paced, per dive computer family.
///
/// The service list and the characteristics to skip are facts about what
/// dive computers expose over Bluetooth LE, as documented by Subsurface's
/// `core/qt-ble.cpp` (see NOTICE.md); this is Anchorline's own
/// implementation of them.
///
/// Pure Dart. The choosing itself (which service on a real device) is in
/// `ble_central_libdc_link.dart`, because it needs the discovered GATT.
library;

import 'package:libdivecomputer/libdivecomputer.dart';

/// How the device paces the data it sends.
enum LibdcFlowControl {
  /// The link just receives.
  none,

  /// Hardware (HW) OSTC computers behind a Telit or u-blox serial bridge:
  /// the link hands out credits, and the device sends one packet per credit.
  telitCredits,
}

/// The GATT facts for one family.
class LibdcBleProfile {
  const LibdcBleProfile({
    required this.preferredServices,
    required this.ignoreForRead,
    required this.ignoreForWrite,
    required this.flowControl,
  });

  /// Known serial services, highest priority first. Lower case, 128-bit.
  final List<String> preferredServices;

  /// Characteristics never subscribed to or read from.
  final List<String> ignoreForRead;

  /// Characteristics never written to.
  final List<String> ignoreForWrite;

  final LibdcFlowControl flowControl;
}

/// The known serial services in priority order (HW Telit and u-blox, Mares,
/// Suunto, Pelagic twice, Scubapro, Divesoft, Cressi before Nordic UART,
/// Halcyon, Seac).
const List<String> kLibdcKnownServices = [
  '0000fefb-0000-1000-8000-00805f9b34fb',
  '2456e1b9-26e2-8f83-e744-f34f01e9d701',
  '544e326b-5b72-c6b0-1c46-41c1bc448118',
  '98ae7120-e62e-11e3-badd-0002a5d5c51b',
  'cb3c4555-d670-4670-bc20-b61dbc851e9a',
  'ca7b0001-f785-4c38-b599-c7c5fbadb034',
  'fdcdeaaa-295d-470e-bf15-04217b7aa0a0',
  '0000fcef-0000-1000-8000-00805f9b34fb',
  '6e400001-b5a3-f393-e0a9-e50e24dc10b8',
  '6e400001-b5a3-f393-e0a9-e50e24dcca9e',
  '00000001-8c3b-4f2c-a59e-8c08224f3253',
  '84968ffe-d26d-478a-b953-5010bcf58bca',
];

/// Firmware-upgrade services, never used.
const List<String> kLibdcUpgradeServices = [
  '00001530-1212-efde-1523-785feabcd123',
  '9e5d1e47-5c13-43a0-8635-82ad38a1386f',
];

const List<String> _kIgnoreRead = [
  '00000101-8c3b-4f2c-a59e-8c08224f3253', // Halcyon
  ..._kMcLean,
];

const List<String> _kIgnoreWrite = [
  '00000201-8c3b-4f2c-a59e-8c08224f3253', // Halcyon
  ..._kMcLean,
];

const List<String> _kMcLean = [
  '49535343-6daa-4d02-abf6-19569aca69fe',
  '49535343-aca3-481c-91ec-d85e28a60318',
  '49535343-026e-3a9b-954c-97daef17e26e',
  '49535343-4c8a-39b3-2f49-511cff073b7e',
];

/// The profile for [d]'s family. Families with nothing special, and
/// families this build doesn't know, get the generic profile: the known
/// services in priority order and no flow control. Never throws.
LibdcBleProfile libdcProfileFor(LibdcDescriptor d) {
  final flow = switch (d.family) {
    dc_family_t.DC_FAMILY_HW_OSTC3 => LibdcFlowControl.telitCredits,
    _ => LibdcFlowControl.none,
  };
  return LibdcBleProfile(
    preferredServices: kLibdcKnownServices,
    ignoreForRead: _kIgnoreRead,
    ignoreForWrite: _kIgnoreWrite,
    flowControl: flow,
  );
}
