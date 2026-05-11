import 'package:ccrlogger/sync/cloud/sync_health_service.dart';
import 'package:flutter_test/flutter_test.dart';

SyncHealthSlot _slot({
  String walStatus = 'reserved',
  int retainedMb = 0,
  bool active = true,
}) =>
    SyncHealthSlot(
      slotName: 'powersync_test',
      active: active,
      walStatus: walStatus,
      retainedMb: retainedMb,
    );

void main() {
  group('classifySeverity', () {
    test('returns ok for a healthy active slot with low retention', () {
      expect(classifySeverity(_slot()), SyncHealthSeverity.ok);
      expect(classifySeverity(_slot(retainedMb: 50)), SyncHealthSeverity.ok);
      expect(classifySeverity(_slot(retainedMb: 255)), SyncHealthSeverity.ok);
    });

    test('warns at 256 MB retention', () {
      expect(classifySeverity(_slot(retainedMb: 256)),
          SyncHealthSeverity.warn);
      expect(classifySeverity(_slot(retainedMb: 500)),
          SyncHealthSeverity.warn);
    });

    test('escalates to critical at 768 MB retention', () {
      expect(classifySeverity(_slot(retainedMb: 768)),
          SyncHealthSeverity.critical);
      expect(classifySeverity(_slot(retainedMb: 1024)),
          SyncHealthSeverity.critical);
    });

    test('any "lost" slot is critical regardless of retention', () {
      expect(classifySeverity(_slot(walStatus: 'lost')),
          SyncHealthSeverity.critical);
      expect(classifySeverity(_slot(walStatus: 'lost', retainedMb: 0)),
          SyncHealthSeverity.critical);
    });
  });

  group('SyncHealthService', () {
    test('polls on start, exposes snapshot, classifies worst slot', () async {
      final fake = _FakeClient([
        _slot(retainedMb: 10),
        _slot(retainedMb: 300), // warn
        _slot(retainedMb: 5),
      ]);
      final svc = SyncHealthService(fake);
      final completer = Future.delayed(Duration.zero);
      svc.start();
      await completer;
      await Future<void>.delayed(Duration.zero);

      final snap = svc.snapshot!;
      expect(snap.slots.length, 3);
      expect(snap.severity, SyncHealthSeverity.warn);
      expect(snap.worst?.retainedMb, 300);
      expect(snap.shouldShowBanner, isTrue);
      svc.dispose();
    });

    test('degraded snapshot when RPC throws — banner stays hidden', () async {
      final svc = SyncHealthService(_FakeClient.throwing());
      svc.start();
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final snap = svc.snapshot!;
      expect(snap.degraded, isTrue);
      expect(snap.shouldShowBanner, isFalse);
      svc.dispose();
    });
  });
}

class _FakeClient implements SyncHealthClient {
  final List<SyncHealthSlot>? _result;
  final bool _shouldThrow;

  _FakeClient(this._result) : _shouldThrow = false;
  _FakeClient.throwing()
      : _result = null,
        _shouldThrow = true;

  @override
  Future<List<SyncHealthSlot>> fetch() async {
    if (_shouldThrow) throw StateError('boom');
    return _result!;
  }
}
