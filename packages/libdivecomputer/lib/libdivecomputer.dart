/// Vendored libdivecomputer, built by a native assets hook, and the Dart side
/// of Anchorline's access to dive computers from other manufacturers.
library;

export 'src/bindings.g.dart' show dc_family_t;
export 'src/descriptors.dart' show LibdcDescriptor, Libdc;
export 'src/download/ble_link.dart' show LibdcBleLink;
