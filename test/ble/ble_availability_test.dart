import 'package:ccrlogger/analyzer/transport/analyzer_transport_options.dart';
import 'package:ccrlogger/ble/ble_central_default.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    test('the bridge and the label printer are available on ${platform.name}',
        () {
      debugDefaultTargetPlatformOverride = platform;
      expect(bleCentralAvailable, isTrue);
      expect(analyzerBridgeAvailable, isTrue);
    });
  }

  test('not on Fuchsia', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(bleCentralAvailable, isFalse);
    expect(analyzerBridgeAvailable, isFalse);
  });

  test('the Bridge source is offered on Windows and Linux', () {
    final bridge = AnalyzerTransportOption(
      label: 'Bridge',
      create: () => throw UnimplementedError(),
    );
    for (final platform in [TargetPlatform.windows, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      final labels = [
        for (final o in defaultAnalyzerTransportOptions(bridge: bridge))
          o.label,
      ];
      expect(labels, contains('Bridge'), reason: platform.name);
    }
  });
}
