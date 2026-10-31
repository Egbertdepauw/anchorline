/// Which serial ports to offer for the gas analyzer, and which to
/// preselect.
///
/// The Divesoft SOLO is a native USB CDC-ACM device (not FTDI), so it shows
/// up as `/dev/cu.usbmodem*` on macOS (`/dev/cu.usbmodem2101` on the unit we
/// tested; the number changes with the USB port), `/dev/ttyACM*` on Linux
/// and a `COMn` port on Windows.
///
/// Pure Dart, no I/O: the lists come from `listDesktopSerialPorts`, these
/// functions only filter and rank them. The SOLO's VID/PID are in
/// `solo_usb_ids.dart`; desktop preselection still goes by device name.
library;

export 'solo_usb_ids.dart';

/// Whether [path] is a serial device worth offering in the port picker.
///
/// macOS: only the `cu.*` callout devices (opening `tty.*` waits for
/// carrier), minus the always-present Bluetooth and debug consoles.
/// Linux: USB serial (`ttyACM*`, `ttyUSB*`). Windows: `COMn`.
bool isCandidateSerialPort(String path) {
  if (_windowsCom.hasMatch(path)) return true;
  final name = path.split('/').last;
  if (path.startsWith('/dev/cu.')) {
    return name != 'cu.Bluetooth-Incoming-Port' && name != 'cu.debug-console';
  }
  if (path.startsWith('/dev/')) {
    return name.startsWith('ttyACM') || name.startsWith('ttyUSB');
  }
  return false;
}

/// Whether [path] looks like a native USB CDC-ACM port, i.e. most likely
/// the analyzer.
bool isLikelyAnalyzerPort(String path) {
  final name = path.split('/').last;
  return name.startsWith('cu.usbmodem') ||
      name.startsWith('tty.usbmodem') ||
      name.startsWith('ttyACM');
}

/// Filters [paths] to candidate ports, sorted with likely-analyzer ports
/// first, then by name (COM ports numerically, so COM10 follows COM9).
List<String> rankSerialPorts(Iterable<String> paths) {
  final ports = paths.where(isCandidateSerialPort).toSet().toList();
  ports.sort((a, b) {
    final la = isLikelyAnalyzerPort(a), lb = isLikelyAnalyzerPort(b);
    if (la != lb) return la ? -1 : 1;
    final ca = _windowsCom.firstMatch(a), cb = _windowsCom.firstMatch(b);
    if (ca != null && cb != null) {
      return int.parse(ca.group(1)!).compareTo(int.parse(cb.group(1)!));
    }
    return a.compareTo(b);
  });
  return ports;
}

/// The port to preselect in the picker: [previous] if it is still present
/// (the diver picked it last time), else the first likely-analyzer port,
/// else the only port if there is exactly one, else null.
///
/// On Windows every port is a `COMn`, so with several ports and no
/// [previous] nothing is preselected until the VID/PID is known (#104).
String? preselectSerialPort(List<String> ports, {String? previous}) {
  if (previous != null && ports.contains(previous)) return previous;
  for (final p in ports) {
    if (isLikelyAnalyzerPort(p)) return p;
  }
  return ports.length == 1 ? ports.single : null;
}

final RegExp _windowsCom = RegExp(r'^COM(\d+)$', caseSensitive: false);
