import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/widgets.dart' show BuildContext;

import 'analyzer_transport.dart';
import 'android_usb_transport.dart';
import 'demo_transport.dart';
import 'desktop_serial_transport.dart';
import 'serial_port_selection.dart';
import '../../ui/widgets/serial_port_picker_dialog.dart';

/// A transport the diver can pick on the analyzer screen.
class AnalyzerTransportOption {
  const AnalyzerTransportOption({
    required this.label,
    required this.create,
    this.note,
    this.choose,
    this.isDemo = false,
  });

  final String label;

  /// True for the built-in simulator. Its readings are made up, so the
  /// screen offers no way to save them to the gas analysis log.
  final bool isDemo;

  /// One short line shown under the source picker while this option is
  /// selected, or null.
  final String? note;

  /// Builds a fresh transport for one session. The controller owns and
  /// disposes it.
  final AnalyzerTransport Function() create;

  /// Optional interactive variant of [create] (e.g. a port picker), used
  /// by the Connect button when set. Returns null when the diver cancels.
  final Future<AnalyzerTransport?> Function(BuildContext context)? choose;
}

/// Port picked in the last desktop USB session, preselected next time.
String? _lastSerialPort;

/// Desktop USB serial (#108). Only offered on macOS/Windows/Linux, so
/// mobile and web never touch the dart:ffi serial code.
bool get _hasDesktopSerial =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.linux);

/// Whether the SOLO bridge can be used here: Bluetooth LE on iOS, Android
/// and macOS. Windows and Linux have no bridge in v1.
bool get analyzerBridgeAvailable =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.macOS);

/// The transports available on this platform, in picker order (the first is
/// selected by default):
///
///  * iOS: Bridge, Demo.
///  * Android: USB (Android), Bridge, Demo.
///  * macOS: USB, Bridge, Demo.
///  * Windows and Linux: USB, Demo.
///
/// [bridge] is the Bridge source; it is left out where
/// [analyzerBridgeAvailable] is false or when null.
List<AnalyzerTransportOption> defaultAnalyzerTransportOptions({
  AnalyzerTransportOption? bridge,
}) => [
      if (_hasDesktopSerial)
        AnalyzerTransportOption(
          label: 'USB',
          create: () => DesktopSerialTransport(
            portPath: _lastSerialPort ??
                preselectSerialPort(listDesktopSerialPorts()) ??
                '',
          ),
          choose: (context) async {
            final port = await showSerialPortPicker(
              context,
              listPorts: listDesktopSerialPorts,
              previous: _lastSerialPort,
            );
            if (port == null) return null;
            _lastSerialPort = port;
            return DesktopSerialTransport(portPath: port);
          },
        ),
      if (!kIsWeb && Platform.isAndroid)
        AnalyzerTransportOption(
          label: 'USB (Android)',
          create: () => AndroidUsbTransport(),
          note: 'The phone powers the analyzer over the USB OTG cable.',
        ),
      if (bridge != null && analyzerBridgeAvailable) bridge,
      AnalyzerTransportOption(
        label: 'Demo',
        isDemo: true,
        create: () => DemoAnalyzerTransport(),
      ),
    ];
