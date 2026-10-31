/// Picking the gas analyzer out of the attached USB devices (Android OTG).
///
/// Pure Dart so the choice is unit-testable without hardware.
library;

/// USB vendor ID of the Divesoft SOLO, once known.
///
/// TODO(#104): record the SOLO VID/PID (`system_profiler SPUSBDataType`
/// on macOS) and fill these in, together with
/// `android/app/src/main/res/xml/device_filter.xml`. Until then the first
/// CDC serial device is used.
const int? kSoloUsbVendorId = null;

/// USB product ID of the Divesoft SOLO, once known. See [kSoloUsbVendorId].
const int? kSoloUsbProductId = null;

/// USB class code for CDC Communications (the CDC-ACM control interface).
const int kUsbClassCdcComm = 0x02;

/// USB class code for CDC Data (the CDC-ACM data interface).
const int kUsbClassCdcData = 0x0A;

/// One attached USB device, as reported by the Android USB host API.
class UsbDeviceInfo {
  const UsbDeviceInfo({
    required this.deviceName,
    required this.vendorId,
    required this.productId,
    this.deviceClass = 0,
    this.interfaceClasses = const [],
    this.productName,
    this.manufacturerName,
    this.hasPermission = false,
  });

  /// Decodes one entry of the platform channel's `listDevices` result.
  factory UsbDeviceInfo.fromMap(Map<Object?, Object?> map) => UsbDeviceInfo(
        deviceName: map['deviceName'] as String,
        vendorId: map['vendorId'] as int? ?? 0,
        productId: map['productId'] as int? ?? 0,
        deviceClass: map['deviceClass'] as int? ?? 0,
        interfaceClasses: [
          for (final c in (map['interfaceClasses'] as List?) ?? const [])
            c as int,
        ],
        productName: map['productName'] as String?,
        manufacturerName: map['manufacturerName'] as String?,
        hasPermission: map['hasPermission'] as bool? ?? false,
      );

  /// Android's device path (`/dev/bus/usb/001/002`); the handle for
  /// permission and open calls.
  final String deviceName;
  final int vendorId;
  final int productId;
  final int deviceClass;
  final List<int> interfaceClasses;
  final String? productName;
  final String? manufacturerName;
  final bool hasPermission;

  /// True for a CDC-ACM serial device: CDC device class, or a CDC
  /// communications / data interface (composite devices report class 0 or
  /// 0xEF at device level and put the CDC classes on the interfaces).
  bool get isCdcSerial =>
      deviceClass == kUsbClassCdcComm ||
      interfaceClasses.contains(kUsbClassCdcComm) ||
      interfaceClasses.contains(kUsbClassCdcData);

  /// "Divesoft SOLO" or "USB device 1234:5678".
  String get displayName {
    final parts = [manufacturerName, productName]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty);
    if (parts.isNotEmpty) return parts.join(' ');
    String hex(int v) => v.toRadixString(16).padLeft(4, '0');
    return 'USB device ${hex(vendorId)}:${hex(productId)}';
  }
}

/// Picks the device to open as the analyzer, or null when none fits.
///
/// An exact [vendorId]/[productId] match wins. Otherwise the first CDC
/// serial device is used, so the transport works before #104 records the
/// SOLO IDs. Non-CDC devices (keyboards, flash drives, FTDI adapters) are
/// never picked.
UsbDeviceInfo? selectAnalyzerDevice(
  List<UsbDeviceInfo> devices, {
  int? vendorId = kSoloUsbVendorId,
  int? productId = kSoloUsbProductId,
}) {
  if (vendorId != null) {
    for (final d in devices) {
      if (d.vendorId == vendorId &&
          (productId == null || d.productId == productId)) {
        return d;
      }
    }
  }
  for (final d in devices) {
    if (d.isCdcSerial) return d;
  }
  return null;
}
