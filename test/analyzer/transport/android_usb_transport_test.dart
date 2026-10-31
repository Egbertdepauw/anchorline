import 'dart:async';
import 'dart:convert';

import 'package:ccrlogger/analyzer/transport/analyzer_transport.dart';
import 'package:ccrlogger/analyzer/transport/android_usb_transport.dart';
import 'package:ccrlogger/analyzer/transport/usb_device_selection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Scriptable stand-in for the native USB channel.
class FakeUsbSerialPlatform implements UsbSerialPlatform {
  FakeUsbSerialPlatform({
    this.devices = const [],
    this.grant = true,
    this.openError,
  });

  List<UsbDeviceInfo> devices;
  bool grant;
  PlatformException? openError;

  final StreamController<UsbSerialEvent> controller =
      StreamController.broadcast(sync: true);
  final List<String> permissionRequests = [];
  final List<(String, int)> opened = [];
  int closeCalls = 0;

  @override
  Future<List<UsbDeviceInfo>> listDevices() async => devices;

  @override
  Future<bool> requestPermission(String deviceName) async {
    permissionRequests.add(deviceName);
    return grant;
  }

  @override
  Future<void> open(String deviceName, {required int baudRate}) async {
    final e = openError;
    if (e != null) throw e;
    opened.add((deviceName, baudRate));
  }

  @override
  Future<void> close() async => closeCalls++;

  @override
  Stream<UsbSerialEvent> get events => controller.stream;

  void send(String s) =>
      controller.add(UsbSerialData(Uint8List.fromList(utf8.encode(s))));
}

void main() {
  const solo = UsbDeviceInfo(
    deviceName: '/dev/bus/usb/001/004',
    vendorId: 0x1234,
    productId: 0x0001,
    interfaceClasses: [kUsbClassCdcComm, kUsbClassCdcData],
  );

  test('opens the CDC device at 115200 after asking for permission',
      () async {
    final p = FakeUsbSerialPlatform(devices: [solo]);
    final t = AndroidUsbTransport(platform: p);
    final statuses = <AnalyzerConnectionStatus>[];
    t.statusChanges.listen(statuses.add);

    await t.connect();
    await Future<void>.delayed(Duration.zero); // deliver status events

    expect(t.status, AnalyzerConnectionStatus.connected);
    expect(p.permissionRequests, [solo.deviceName]);
    expect(p.opened, [(solo.deviceName, 115200)]);
    expect(t.device, same(solo));
    expect(statuses, [
      AnalyzerConnectionStatus.connecting,
      AnalyzerConnectionStatus.connected,
    ]);
    await t.dispose();
  });

  test('skips the permission dialog when access is already granted',
      () async {
    const granted = UsbDeviceInfo(
      deviceName: '/dev/bus/usb/001/009',
      vendorId: 1,
      productId: 2,
      interfaceClasses: [kUsbClassCdcData],
      hasPermission: true,
    );
    final p = FakeUsbSerialPlatform(devices: [granted]);
    final t = AndroidUsbTransport(platform: p);
    await t.connect();
    expect(p.permissionRequests, isEmpty);
    expect(t.status, AnalyzerConnectionStatus.connected);
    await t.dispose();
  });

  test('emits complete lines from chunked data', () async {
    final p = FakeUsbSerialPlatform(devices: [solo]);
    final t = AndroidUsbTransport(platform: p);
    final lines = <String>[];
    t.lines.listen(lines.add);
    await t.connect();

    p.send('He 45.1 O2 18');
    p.send('.2 % Ti 21.4 ~C\r\nHe 45');
    p.send('.0 O2 18.3 %\r\n');
    await Future<void>.delayed(Duration.zero);

    expect(lines, ['He 45.1 O2 18.2 % Ti 21.4 ~C', 'He 45.0 O2 18.3 %']);
    await t.dispose();
  });

  test('no CDC device: error with a cable hint, nothing opened', () async {
    final p = FakeUsbSerialPlatform(devices: const [
      UsbDeviceInfo(
          deviceName: 'kbd', vendorId: 1, productId: 1, interfaceClasses: [3]),
    ]);
    final t = AndroidUsbTransport(platform: p);
    await t.connect();
    expect(t.status, AnalyzerConnectionStatus.error);
    expect(t.errorMessage, contains('OTG'));
    expect(p.opened, isEmpty);
    await t.dispose();
  });

  test('permission denied: error, nothing opened', () async {
    final p = FakeUsbSerialPlatform(devices: [solo], grant: false);
    final t = AndroidUsbTransport(platform: p);
    await t.connect();
    expect(t.status, AnalyzerConnectionStatus.error);
    expect(t.errorMessage, contains('denied'));
    expect(p.opened, isEmpty);
    await t.dispose();
  });

  test('open failure surfaces the platform message', () async {
    final p = FakeUsbSerialPlatform(
      devices: [solo],
      openError: PlatformException(
          code: 'CLAIM_FAILED', message: 'Could not claim USB interface 0.'),
    );
    final t = AndroidUsbTransport(platform: p);
    await t.connect();
    expect(t.status, AnalyzerConnectionStatus.error);
    expect(t.errorMessage, contains('Could not claim USB interface 0.'));
    await t.dispose();
  });

  test('unplugging the analyzer ends the session with an error', () async {
    final p = FakeUsbSerialPlatform(devices: [solo]);
    final t = AndroidUsbTransport(platform: p);
    final lines = <String>[];
    t.lines.listen(lines.add);
    await t.connect();

    p.controller.add(const UsbSerialDetached('/dev/bus/usb/001/099'));
    await Future<void>.delayed(Duration.zero);
    expect(t.status, AnalyzerConnectionStatus.connected,
        reason: 'another device went away');

    p.controller.add(UsbSerialDetached(solo.deviceName));
    await Future<void>.delayed(Duration.zero);
    expect(t.status, AnalyzerConnectionStatus.error);
    expect(t.errorMessage, 'The analyzer was unplugged.');
    expect(p.closeCalls, 1);

    p.send('late\n');
    await Future<void>.delayed(Duration.zero);
    expect(lines, isEmpty, reason: 'no lines after detach');
    await t.dispose();
  });

  test('disconnect closes the port and can reconnect', () async {
    final p = FakeUsbSerialPlatform(devices: [solo]);
    final t = AndroidUsbTransport(platform: p);
    final lines = <String>[];
    t.lines.listen(lines.add);
    await t.connect();
    p.send('half');
    await t.disconnect();
    expect(t.status, AnalyzerConnectionStatus.disconnected);
    expect(p.closeCalls, 1);
    expect(t.errorMessage, isNull);

    await t.connect();
    p.send('fresh\n');
    await Future<void>.delayed(Duration.zero);
    expect(lines, ['fresh'], reason: 'partial line dropped on reconnect');
    await t.dispose();
    expect(p.closeCalls, 2);
  });
}
