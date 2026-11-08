import 'dart:async';

import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:ccrlogger/sync/cloud/account_deleter.dart';
import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart';
import 'package:ccrlogger/sync/cloud/cloud_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeSession implements SessionSource {
  _FakeSession(this.calls);
  final List<String> calls;
  Object? refreshError;

  @override
  Session? get currentSession => null;

  @override
  Future<void> refreshSession() async {
    calls.add('refresh');
    final e = refreshError;
    if (e != null) throw e;
  }
}

class _FakeBackend implements AccountDeletionBackend {
  _FakeBackend(this.calls);
  final List<String> calls;
  List<String> serverKeys = const ['a'];
  Object? listError;
  Object? rpcError;
  Completer<void>? rpcGate;

  @override
  Future<List<String>> listStorageKeys() async {
    calls.add('serverKeys');
    final e = listError;
    if (e != null) throw e;
    return serverKeys;
  }

  @override
  Future<void> deleteAccount() async {
    calls.add('rpc');
    await rpcGate?.future;
    final e = rpcError;
    if (e != null) throw e;
  }
}

class _FakeSync implements SyncPause {
  _FakeSync(this.calls);
  final List<String> calls;
  @override
  Future<void> pause() async => calls.add('pause');
  @override
  Future<void> resume() async => calls.add('resume');
}

class _Harness {
  _Harness() {
    session = _FakeSession(calls);
    backend = _FakeBackend(calls);
    sync = _FakeSync(calls);
  }

  final calls = <String>[];
  late final _FakeSession session;
  late final _FakeBackend backend;
  late final _FakeSync sync;
  List<String> localKeys = const ['a', 'b'];
  Future<void> Function(String key)? onDelete;
  Object? signOutError;
  Object? localKeysError;
  Object? wipeError;

  AccountDeleter build() => AccountDeleter(
        session: session,
        backend: backend,
        sync: sync,
        localStorageKeys: () async {
          calls.add('localKeys');
          final e = localKeysError;
          if (e != null) throw e;
          return localKeys;
        },
        deleteObject: (key) async {
          calls.add('delete:$key');
          await onDelete?.call(key);
        },
        signOut: () async {
          calls.add('signOut');
          final e = signOutError;
          if (e != null) throw e;
        },
        wipeLocal: () async {
          calls.add('wipe');
          final e = wipeError;
          if (e != null) throw e;
        },
      );
}

AccountDeletionFailed _failed(AccountDeletionResult r) {
  expect(r, isA<AccountDeletionFailed>());
  return r as AccountDeletionFailed;
}

void main() {
  test('happy path runs the steps in order', () async {
    final h = _Harness();
    final result = await h.build().deleteAccount();
    expect(result, isA<AccountDeleted>());
    expect(h.calls, [
      'refresh',
      'pause',
      'serverKeys',
      'localKeys',
      'delete:a',
      'delete:b',
      'rpc',
      'signOut',
      'wipe',
      'resume',
    ]);
  });

  test('offline: refresh failure stops before pausing', () async {
    final h = _Harness()..session.refreshError = Exception('no network');
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.offline);
    expect(f.failedAttachments, 0);
    expect(h.calls, ['refresh']);
  });

  test('an attachment failure is retried once', () async {
    final h = _Harness();
    var aFails = 1;
    h.onDelete = (key) async {
      if (key == 'a' && aFails-- > 0) throw Exception('blip');
    };
    final result = await h.build().deleteAccount();
    expect(result, isA<AccountDeleted>());
    expect(h.calls.where((c) => c == 'delete:a'), hasLength(2));
  });

  test('a persistent attachment failure stops before the rpc', () async {
    final h = _Harness();
    h.onDelete = (key) async {
      if (key == 'b') throw const SignerAuthException('x');
    };
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.attachments);
    expect(f.failedAttachments, 1);
    expect(f.message, isNotEmpty);
    expect(h.calls.where((c) => c == 'delete:b'), hasLength(2));
    expect(h.calls, isNot(contains('rpc')));
    expect(h.calls, isNot(contains('wipe')));
    expect(h.calls.last, 'resume');
  });

  test('a session gone mid-sweep is an attachments failure', () async {
    final h = _Harness();
    h.onDelete = (_) async => throw const SignerNoSessionException();
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.attachments);
    expect(f.failedAttachments, 2);
    expect(h.calls.last, 'resume');
  });

  test('an rpc failure resumes sync and does not wipe', () async {
    final h = _Harness()..backend.rpcError = Exception('boom');
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.account);
    expect(f.failedAttachments, 0);
    expect(h.calls, isNot(contains('signOut')));
    expect(h.calls, isNot(contains('wipe')));
    expect(h.calls.last, 'resume');
  });

  test('a sign-out error does not stop the wipe', () async {
    final h = _Harness()..signOutError = Exception('403');
    final result = await h.build().deleteAccount();
    expect(result, isA<AccountDeleted>());
    expect(h.calls, contains('wipe'));
  });

  test('a wipe failure reports localWipe after signing out', () async {
    final h = _Harness()..wipeError = Exception('disk');
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.localWipe);
    expect(h.calls.indexOf('signOut'), lessThan(h.calls.indexOf('wipe')));
    expect(h.calls.last, 'resume');
  });

  test('a second call while running returns the same future', () async {
    final h = _Harness()..backend.rpcGate = Completer<void>();
    final d = h.build();
    final f1 = d.deleteAccount();
    final f2 = d.deleteAccount();
    expect(identical(f1, f2), isTrue);
    await pumpEventQueue();
    h.backend.rpcGate!.complete();
    await f1;
    expect(h.calls.where((c) => c == 'rpc'), hasLength(1));
  });

  test('progress reports each step', () async {
    final h = _Harness();
    final seen = <AccountDeletionProgress>[];
    await h.build().deleteAccount(onProgress: seen.add);
    final steps = <AccountDeletionStep>[];
    for (final p in seen) {
      if (steps.isEmpty || steps.last != p.step) steps.add(p.step);
    }
    expect(steps, [
      AccountDeletionStep.checking,
      AccountDeletionStep.removingAttachments,
      AccountDeletionStep.deletingAccount,
      AccountDeletionStep.clearingDevice,
    ]);
    final removing = seen
        .where((p) => p.step == AccountDeletionStep.removingAttachments)
        .toList();
    expect(removing.map((p) => p.done), [0, 1, 2]);
    expect(removing.every((p) => p.total == 2), isTrue);
  });

  test('a throwing onProgress does not break the flow', () async {
    final h = _Harness();
    final result = await h
        .build()
        .deleteAccount(onProgress: (_) => throw StateError('ui gone'));
    expect(result, isA<AccountDeleted>());
    expect(h.calls.sublist(h.calls.length - 4),
        ['rpc', 'signOut', 'wipe', 'resume']);
  });

  test('a server key-listing failure stops before any delete', () async {
    final h = _Harness()..backend.listError = Exception('list');
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.attachments);
    expect(f.failedAttachments, 0);
    expect(h.calls.where((c) => c.startsWith('delete:')), isEmpty);
    expect(h.calls, isNot(contains('rpc')));
    expect(h.calls, isNot(contains('wipe')));
    expect(h.calls.last, 'resume');
  });

  test('a local key-listing failure stops before any delete', () async {
    final h = _Harness()..localKeysError = Exception('local');
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.attachments);
    expect(f.failedAttachments, 0);
    expect(h.calls.where((c) => c.startsWith('delete:')), isEmpty);
    expect(h.calls, isNot(contains('rpc')));
    expect(h.calls, isNot(contains('wipe')));
    expect(h.calls.last, 'resume');
  });

  group('SupabaseAccountDeletionBackend.fetchAllPages', () {
    test('pages past 1000 rows and stops on a short page', () async {
      final ranges = <(int, int)>[];
      final sizes = [1000, 1000, 3];
      final keys = await SupabaseAccountDeletionBackend.fetchAllPages(
        (from, to) async {
          ranges.add((from, to));
          final n = sizes[ranges.length - 1];
          return List.generate(n, (i) => 'k${from + i}');
        },
      );
      expect(keys, hasLength(2003));
      expect(ranges, [(0, 999), (1000, 1999), (2000, 2999)]);
    });

    test('an empty first page returns nothing', () async {
      final keys = await SupabaseAccountDeletionBackend.fetchAllPages(
        (from, to) async => <String>[],
      );
      expect(keys, isEmpty);
    });
  });
}
