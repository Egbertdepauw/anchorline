/// USB identity of the Divesoft SOLO gas analyzer.
///
/// Recorded from a trimix SOLO on 2026-10-31 (#104) with
/// `system_profiler SPUSBHostDataType`: "Divesoft Serial Port Interface",
/// manufacturer Divesoft, USB CDC-ACM, 12 Mb/s, appearing on macOS as
/// `/dev/cu.usbmodem2101`.
///
/// Keep in sync with `android/app/src/main/res/xml/device_filter.xml`,
/// which needs the same values in decimal (42496 / 57874).
library;

/// USB vendor ID of the Divesoft SOLO (0xA600).
const int kSoloUsbVendorId = 0xA600;

/// USB product ID of the Divesoft SOLO (0xE212).
const int kSoloUsbProductId = 0xE212;
