#ifndef RUNNER_BLE_CENTRAL_CHANNEL_H_
#define RUNNER_BLE_CENTRAL_CHANNEL_H_

#include <flutter/binary_messenger.h>

#include <memory>

// The app's Bluetooth LE central on Windows, for the SOLO bridge and the
// Phomemo label printer: a method channel "nl.despaankamer.ccrlogger/ble"
// and an event channel "nl.despaankamer.ccrlogger/ble/events" over WinRT
// (Windows.Devices.Bluetooth). The Dart side is
// lib/ble/windows_ble_central.dart, which documents the protocol.
//
// flutter_blue_plus 1.x has no Windows support and 2.x is not open source,
// so the runner carries this instead of a plugin, like the Android USB
// serial channel (UsbSerialChannel.kt).
//
// Construct and destroy on the platform thread. The WinRT headers stay in
// the .cpp, which is compiled as C++20 with exceptions on (see
// runner/CMakeLists.txt); this header is safe for the runner's C++17 code.
class BleCentralChannel {
 public:
  explicit BleCentralChannel(flutter::BinaryMessenger* messenger);
  ~BleCentralChannel();

  BleCentralChannel(const BleCentralChannel&) = delete;
  BleCentralChannel& operator=(const BleCentralChannel&) = delete;

  class Impl;

 private:
  std::shared_ptr<Impl> impl_;
};

#endif  // RUNNER_BLE_CENTRAL_CHANNEL_H_
