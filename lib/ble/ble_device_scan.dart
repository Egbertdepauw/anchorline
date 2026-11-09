/// A "Find …" scan over a [BleCentral]: the devices that match, as a
/// growing, sorted list.
///
/// Pure Dart. The bridge scan (`scanForBridges`) and the label printer
/// scan (`PhomemoBleScanner`) are both this with their own filter.
library;

import 'dart:async';

import 'ble_central.dart';

/// A device a [BleDeviceScan] found.
class BleFoundDevice {
  const BleFoundDevice({required this.id, required this.name});

  final String id;
  final String name;
}

/// One scan run. Listen to [stream] to start it; cancel the subscription or
/// call [end] to stop it.
///
/// [stream] emits the matches so far, sorted by name, each time the list
/// changes, and closes when the scan ends. When Bluetooth isn't on within
/// [adapterTimeout], or the scan can't start, it emits one error made by
/// [error] (from 'Bluetooth is off', 'Bluetooth LE is not available' or
/// 'Bluetooth scan failed') and closes.
class BleDeviceScan {
  BleDeviceScan({
    required BleCentral central,
    required String? Function(BleScanResult r) match,
    required Object Function(String message) error,
    this.withServices = const [],
    this.timeout = const Duration(seconds: 10),
    this.adapterTimeout = const Duration(seconds: 10),
    this.unnamed,
    this.caseInsensitiveSort = false,
  })  : _central = central,
        _match = match,
        _error = error {
    _out = StreamController<List<BleFoundDevice>>(
      onListen: () => unawaited(_start()),
      onCancel: end,
    );
  }

  final BleCentral _central;

  /// The name to list a result under, or null when it isn't one of ours.
  final String? Function(BleScanResult r) _match;
  final Object Function(String message) _error;

  final List<String> withServices;
  final Duration timeout;
  final Duration adapterTimeout;

  /// The name [match] gives a device that advertised none. A real name,
  /// once seen, is kept when a later packet has none.
  final String? unnamed;

  final bool caseInsensitiveSort;

  late final StreamController<List<BleFoundDevice>> _out;
  final Map<String, BleFoundDevice> _found = {};
  StreamSubscription<BleScanResult>? _results;
  Timer? _timer;
  bool _ended = false;

  Stream<List<BleFoundDevice>> get stream => _out.stream;

  Future<void> _start() async {
    if (_ended) return;
    final state = await waitForAdapterOn(_central, adapterTimeout);
    final problem = bleAdapterProblem(state);
    if (problem != null) {
      _fail(problem);
      return;
    }
    if (_ended) return;
    _timer = Timer(timeout, end);
    _results = _central
        .scan(withServices: withServices, timeout: timeout)
        .listen(
          _onResult,
          onError: (Object _) => _fail('Bluetooth scan failed'),
          onDone: end,
        );
  }

  void _onResult(BleScanResult r) {
    if (_ended) return;
    final name = _match(r);
    if (name == null) return;
    final known = _found[r.id];
    if (known != null && (known.name == name || name == unnamed)) return;
    _found[r.id] = BleFoundDevice(id: r.id, name: name);
    _out.add(_sorted());
  }

  List<BleFoundDevice> _sorted() {
    String key(BleFoundDevice d) =>
        caseInsensitiveSort ? d.name.toLowerCase() : d.name;
    return _found.values.toList()
      ..sort((a, b) {
        final byName = key(a).compareTo(key(b));
        return byName != 0 ? byName : a.id.compareTo(b.id);
      });
  }

  void _fail(String message) {
    if (_ended) return;
    _out.addError(_error(message));
    end();
  }

  /// Ends this run: cancels the platform scan subscription and the timer
  /// and closes [stream]. The radio scan stops with the subscription.
  void end() {
    if (_ended) return;
    _ended = true;
    _timer?.cancel();
    _timer = null;
    unawaited(_results?.cancel());
    _results = null;
    unawaited(_out.close());
  }
}
