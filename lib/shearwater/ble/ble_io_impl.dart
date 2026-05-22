/// Real BLE I/O implementation using flutter_blue_plus.
///
/// Bridges the abstract [BleIo] interface to a real BLE device.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'protocol.dart';

/// Shearwater BLE service and characteristic UUIDs.
///
/// Shearwater uses a custom BLE service with write and notify characteristics.
const String shearwaterServiceUuid = 'fe25c237-0ece-443c-b0aa-e02033e7029d';
const String shearwaterWriteCharUuid = '27b7570b-359e-45a3-91bb-cf7e70049bd2';
const String shearwaterNotifyCharUuid = '27b7570b-359e-45a3-91bb-cf7e70049bd2';

/// Real BLE I/O backed by a connected [BluetoothDevice].
///
/// Call [connect] to discover services and characteristics, then use
/// [writeBytes] and [readFrames] for the protocol layer.
class FlutterBluePlusBleIo implements BleIo {
  final BluetoothDevice device;
  BluetoothCharacteristic? _writeChar;
  BluetoothCharacteristic? _notifyChar;
  StreamSubscription<List<int>>? _notifySub;

  // Explicit frame queue. The notify subscription is the only producer and
  // is set up once at connect; readFrames is the only consumer. Using a
  // queue (instead of a Stream) avoids two pitfalls: single-subscription
  // streams can't be re-listened to after a cancel, and broadcast streams
  // drop events delivered while no listener is attached — and the Petrel
  // can start responding before our last withoutResponse write returns,
  // which is exactly when there is no listener.
  final _frames = <Uint8List>[];
  Completer<void>? _frameSignal;

  FlutterBluePlusBleIo(this.device);

  /// Discover services, find Shearwater characteristics, enable notifications.
  Future<void> connect() async {
    await device.connect(timeout: const Duration(seconds: 10));

    // Android defaults are catastrophic for bulk transfer:
    //   MTU=23 → 20-byte ATT payload (iOS auto-negotiates ~185 B)
    //   connection interval ~50 ms (iOS ~15 ms)
    // At those defaults a single dive blob from a Petrel takes ~7 minutes.
    // iOS handles both for us; on Android we have to ask. MTU is done now
    // (must be negotiated before any data exchange); connection-priority
    // and PHY are deferred until after notifications are enabled — some
    // Android stacks ignore those requests issued before the link is fully
    // provisioned, and the Shearwater iOS/Android app appears to time its
    // request the same way (we get ~30 ms inter-notification gaps from
    // their sessions in HCI snoops, vs ~177 ms here on the same hardware).
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final mtu = await device.requestMtu(247);
        debugPrint('BLE Android: negotiated MTU=${mtu}B');
      } catch (e) {
        debugPrint('BLE Android: requestMtu failed: $e');
      }
    }

    final services = await device.discoverServices();

    BluetoothService? swService;
    for (final s in services) {
      if (s.uuid.toString().toLowerCase() ==
          shearwaterServiceUuid.toLowerCase()) {
        swService = s;
        break;
      }
    }
    if (swService == null) {
      throw ProtocolException('Shearwater BLE service not found');
    }

    for (final c in swService.characteristics) {
      final uuid = c.uuid.toString().toLowerCase();
      if (uuid == shearwaterWriteCharUuid.toLowerCase()) {
        _writeChar = c;
      }
      if (uuid == shearwaterNotifyCharUuid.toLowerCase()) {
        _notifyChar = c;
      }
    }
    if (_writeChar == null || _notifyChar == null) {
      throw ProtocolException('Shearwater BLE characteristics not found');
    }

    await _notifyChar!.setNotifyValue(true);

    // Now that the link is fully provisioned (services discovered, notify
    // descriptor written), ask for a faster connection interval and
    // BLE 5.0 PHY 2M. Doing this earlier — directly after device.connect()
    // — is what most Flutter/Android examples show, but in practice many
    // Android stacks silently ignore the requests until the GATT link has
    // produced traffic in both directions. Shearwater's own app achieves
    // ~30 ms notification cadence which is only possible at a ~15-30 ms
    // connection interval, so the request clearly *can* succeed on this
    // Petrel firmware — it's a timing question, not a capability one.
    // Negotiate link-layer parameters now that notifications are live.
    // PHY is set once and never re-asserted — every setPreferredPhy()
    // call triggers an LL_PHY_REQ on the air even if we're already at the
    // target PHY, and repeating that during a download destabilises the
    // link (observed: app loses connection mid-dive when PHY refresh
    // fires every few seconds). Connection priority is a separate concern
    // and IS safe to re-issue; see requestHighPerformanceLink below.
    await _setPhy2M();
    await _requestHighPriority();

    int? rssi;
    try {
      rssi = await device.readRssi();
    } catch (_) {
      // readRssi can fail on iOS if not connected long enough; ignore.
    }
    debugPrint('BLE connected. MTU=${device.mtuNow}B, '
        'RSSI=${rssi ?? 'n/a'} dBm, '
        'platform=${defaultTargetPlatform.name}');
    _notifySub = _notifyChar!.onValueReceived.listen((data) {
      _frames.add(Uint8List.fromList(data));
      final waiter = _frameSignal;
      if (waiter != null && !waiter.isCompleted) {
        _frameSignal = null;
        waiter.complete();
      }
    });
  }

  /// Set PHY 2M once. Idempotent in *intent* but NOT idempotent on the
  /// wire — every setPreferredPhy() call triggers an LL_PHY_REQ even if
  /// the link is already at 2M. Calling this repeatedly destabilises the
  /// link, so it must only fire from [connect].
  Future<void> _setPhy2M() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    // PHY 2M doubles the radio bit rate on BLE 5.0 capable peripherals.
    // Petrel 3 supports it; older Petrels (1/2/Perdix) silently fall back
    // to 1M. Bumping PHY also tends to make the link layer accept tighter
    // connection intervals, which is the real prize — the firmware-side
    // pacing we're fighting compounds with the connection interval.
    try {
      await device.setPreferredPhy(
        txPhy: Phy.le2m.mask,
        rxPhy: Phy.le2m.mask,
        option: PhyCoding.noPreferred,
      );
      debugPrint('BLE Android: requested PHY 2M');
    } catch (e) {
      debugPrint('BLE Android: setPreferredPhy failed: $e');
    }
  }

  /// Ask the controller to bump the link to a tight (~15-30 ms) connection
  /// interval. Safe to re-issue periodically; the stack rate-limits and
  /// dedupes internally. Each call still produces an LL_CONNECTION_PARAM_REQ
  /// on the air if it actually changes anything, so don't spam it.
  Future<void> _requestHighPriority() async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await device.requestConnectionPriority(
        connectionPriorityRequest: ConnectionPriority.high,
      );
      debugPrint('BLE Android: requested connection priority HIGH');
    } catch (e) {
      debugPrint('BLE Android: requestConnectionPriority failed: $e');
    }
  }

  /// Public re-trigger for the transport to keep the connection in
  /// high-priority mode during a long download. Android's
  /// `requestConnectionPriority(HIGH)` is not sticky — it expires after
  /// 5–10 s, and the link reverts to the balanced (~177 ms) interval.
  /// PHY is NOT re-asserted here; see [_setPhy2M] for why.
  Future<void> requestHighPerformanceLink() => _requestHighPriority();

  /// Disconnect and clean up.
  Future<void> disconnect() async {
    await _notifySub?.cancel();
    final waiter = _frameSignal;
    _frameSignal = null;
    if (waiter != null && !waiter.isCompleted) {
      waiter.completeError(StateError('Disconnected'));
    }
    await device.disconnect();
  }

  @override
  Future<void> writeBytes(Uint8List data) async {
    if (_writeChar == null) {
      throw StateError('Not connected');
    }
    await _writeChar!.write(data.toList(), withoutResponse: true);
  }

  @override
  void drainPendingFrames() {
    final dropped = _frames.length;
    if (dropped > 0) {
      debugPrint('BLE drainPendingFrames: dropped $dropped stale frame(s)');
      _frames.clear();
    }
    // Don't touch _frameSignal — if a reader is currently blocked on it,
    // that's its own contract; the drain happens between downloads, not
    // during one.
  }

  @override
  Future<List<Uint8List>> readFrames() async {
    if (_notifyChar == null) {
      throw StateError('Not connected');
    }

    final out = <Uint8List>[];
    while (true) {
      while (_frames.isEmpty) {
        _frameSignal = Completer<void>();
        await _frameSignal!.future;
      }
      final frame = _frames.removeAt(0);
      out.add(frame);
      if (frame.isNotEmpty && frame.last == 0xC0) break;
    }
    return out;
  }
}
