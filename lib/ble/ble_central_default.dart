/// Picks this platform's [BleCentral].
library;

import 'package:flutter/foundation.dart';

import 'ble_central.dart';
import 'fbp_ble_central.dart';
import 'windows_ble_central.dart';

/// Whether this platform has a BLE central for the bridge and the label
/// printer: Android, iOS, macOS, Windows and Linux. Not the web.
bool get bleCentralAvailable =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.android ||
      TargetPlatform.iOS ||
      TargetPlatform.macOS ||
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        true,
      TargetPlatform.fuchsia => false,
    };

BleCentral? _central;

/// The app's one central: the WinRT channel on Windows, `flutter_blue_plus`
/// elsewhere.
BleCentral defaultBleCentral() => _central ??=
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows
        ? WindowsBleCentral()
        : FbpBleCentral();
