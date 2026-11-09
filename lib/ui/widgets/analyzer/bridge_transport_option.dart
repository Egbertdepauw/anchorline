/// The "Bridge" source on the analyzer screen: the SOLO through its ESP32
/// Bluetooth bridge.
library;

import 'package:flutter/widgets.dart' show BuildContext;

import '../../../analyzer/bridge/bridge_link.dart';
import '../../../analyzer/bridge/bridge_link_fbp.dart';
import '../../../analyzer/transport/analyzer_transport_options.dart';
import '../../../analyzer/transport/ble_bridge_transport.dart';
import '../../notifiers/settings_notifier.dart';
import '../analyzer_bridge_settings_section.dart';

/// The "Bridge" source. Offered on iOS, Android and macOS (see
/// `defaultAnalyzerTransportOptions`). When no bridge is paired, its picker
/// opens the find dialog first and pairs the one picked.
///
/// The transport reads Log on OK and the 5 V switch from [settings] at each
/// (re)connect.
AnalyzerTransportOption bridgeTransportOption(
  SettingsNotifier settings, {
  BridgeLink Function(String remoteId)? linkFactory,
  Future<FoundBridge?> Function(BuildContext context)? findBridge,
}) {
  BleBridgeTransport build(String id) => BleBridgeTransport(
        link: (linkFactory ?? (id) => FbpBridgeLink(remoteId: id))(id),
        recording: () => settings.analyzerLogOnOk,
        vbusOn: () => settings.analyzerBridgeVbus,
      );
  return AnalyzerTransportOption(
    label: 'Bridge',
    create: () => build(settings.analyzerBridgeId ?? ''),
    choose: (context) async {
      if (settings.analyzerBridgeId == null) {
        final picked = await (findBridge ?? showFindBridgeDialog)(context);
        if (picked == null) return null;
        await settings.setAnalyzerBridge(id: picked.id, name: picked.name);
      }
      return build(settings.analyzerBridgeId!);
    },
  );
}
