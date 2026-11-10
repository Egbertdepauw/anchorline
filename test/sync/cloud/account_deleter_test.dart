import 'dart:async';
import 'dart:math';

import 'package:ccrlogger/sync/attachments/attachment_signer.dart';
import 'package:ccrlogger/sync/cloud/account_deleter.dart';
import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart';
import 'package:ccrlogger/sync/cloud/cloud_sync_coordinator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _uid = 'uid';
const _a = 'attachments/uid/a';
const _b = 'attachments/uid/b';

class _FakeSession implements SessionSource {
  _FakeSession(this.calls);
  final List<String> calls;
  Object? refreshError;

  /// The signed-in user's id; null means no session after the refresh.
  String? userId = _uid;

  @override
  Session? get currentSession {
    final id = userId;
    if (id == null) return null;
    return Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: User(
        id: id,
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-11-08T00:00:00Z',
      ),
    );
  }

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
  List<String> serverKeys = const [_a];
  Object? listError;
  Object? rpcError;
  Completer<void>? rpcGate;
  bool exists = true;
  Object? probeError;
  Completer<void>? probeGate;

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

  @override
  Future<bool> accountExists() async {
    calls.add('probe');
    await probeGate?.future;
    final e = probeError;
    if (e != null) throw e;
    return exists;
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
  List<String> localKeys = const [_a, _b];
  Future<void> Function(String key)? onDelete;
  Object? signOutError;
  Object? localKeysError;
  Object? wipeError;
  Duration rpcTimeout = const Duration(seconds: 60);
  Duration requestTimeout = const Duration(seconds: 30);

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
        rpcTimeout: rpcTimeout,
        requestTimeout: requestTimeout,
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
      'delete:$_a',
      'delete:$_b',
      'rpc',
      'signOut',
      'wipe',
      'resume',
    ]);
  });

  test('the default timeouts are 60 s for the rpc and 30 s per request', () {
    final d = AccountDeleter(
      session: _FakeSession([]),
      backend: _FakeBackend([]),
      sync: _FakeSync([]),
      localStorageKeys: () async => const [],
      deleteObject: (_) async {},
      signOut: () async {},
      wipeLocal: () async {},
    );
    expect(d.rpcTimeout, const Duration(seconds: 60));
    expect(d.requestTimeout, const Duration(seconds: 30));
  });

  test('offline: refresh failure stops before pausing', () async {
    final h = _Harness()..session.refreshError = Exception('no network');
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.offline);
    expect(f.failedAttachments, 0);
    expect(h.calls, ['refresh']);
  });

  test('a retryable auth fetch error on refresh is offline', () async {
    final h = _Harness()
      ..session.refreshError =
          AuthRetryableFetchException(message: 'SocketException');
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.offline);
    expect(h.calls, ['refresh']);
  });

  test('a rejected refresh is sessionEnded and stops before pausing',
      () async {
    final h = _Harness()
      ..session.refreshError = AuthApiException(
        'Invalid Refresh Token: Refresh Token Not Found',
        statusCode: '400',
        code: 'refresh_token_not_found',
      );
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.sessionEnded);
    expect(f.message, 'Invalid Refresh Token: Refresh Token Not Found');
    expect(h.calls, ['refresh']);
  });

  test('no user after the refresh is sessionEnded', () async {
    final h = _Harness()..session.userId = null;
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.sessionEnded);
    expect(h.calls, ['refresh']);
  });

  test("keys outside this user's prefix are skipped", () async {
    final h = _Harness()
      ..backend.serverKeys = const ['attachments/other/x']
      ..localKeys = const [
        'attachments/uid/a',
        'attachments/other/b',
        'attachments/uid2/c',
      ];
    final seen = <AccountDeletionProgress>[];
    final result = await h.build().deleteAccount(onProgress: seen.add);
    expect(result, isA<AccountDeleted>());
    expect(h.calls.where((c) => c.startsWith('delete:')),
        ['delete:attachments/uid/a']);
    expect(
        seen
            .where((p) => p.step == AccountDeletionStep.removingAttachments)
            .every((p) => p.total == 1),
        isTrue);
  });

  test('an attachment failure is retried once', () async {
    final h = _Harness();
    var aFails = 1;
    h.onDelete = (key) async {
      if (key == _a && aFails-- > 0) throw Exception('blip');
    };
    final result = await h.build().deleteAccount();
    expect(result, isA<AccountDeleted>());
    expect(h.calls.where((c) => c == 'delete:$_a'), hasLength(2));
  });

  test('a timed-out attachment delete is retried once', () async {
    final h = _Harness()..requestTimeout = const Duration(milliseconds: 10);
    var aHangs = 1;
    h.onDelete = (key) async {
      if (key == _a && aHangs-- > 0) await Completer<void>().future;
    };
    final result = await h.build().deleteAccount();
    expect(result, isA<AccountDeleted>());
    expect(h.calls.where((c) => c == 'delete:$_a'), hasLength(2));
  });

  test('an attachment delete that always times out fails the sweep',
      () async {
    final h = _Harness()..requestTimeout = const Duration(milliseconds: 10);
    h.onDelete = (key) async {
      if (key == _b) await Completer<void>().future;
    };
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.attachments);
    expect(f.failedAttachments, 1);
    expect(h.calls.where((c) => c == 'delete:$_b'), hasLength(2));
    expect(h.calls, isNot(contains('rpc')));
    expect(h.calls.last, 'resume');
  });

  test('a persistent attachment failure stops before the rpc', () async {
    final h = _Harness();
    h.onDelete = (key) async {
      if (key == _b) throw const SignerAuthException('x');
    };
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.attachments);
    expect(f.failedAttachments, 1);
    expect(f.message, isNotEmpty);
    expect(h.calls.where((c) => c == 'delete:$_b'), hasLength(2));
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
    expect(h.calls.sublist(h.calls.length - 3), ['rpc', 'probe', 'resume']);
    expect(h.calls, isNot(contains('signOut')));
    expect(h.calls, isNot(contains('wipe')));
  });

  test('an rpc failure with the account gone finishes the flow', () async {
    final h = _Harness()
      ..backend.rpcError = Exception('connection reset')
      ..backend.exists = false;
    final result = await h.build().deleteAccount();
    expect(result, isA<AccountDeleted>());
    expect(h.calls.sublist(h.calls.length - 5),
        ['rpc', 'probe', 'signOut', 'wipe', 'resume']);
  });

  test('an rpc failure with a failing probe is an account failure',
      () async {
    final h = _Harness()
      ..backend.rpcError = Exception('connection reset')
      ..backend.probeError = AuthRetryableFetchException();
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.account);
    expect(f.message, 'Exception: connection reset');
    expect(h.calls, contains('probe'));
    expect(h.calls, isNot(contains('wipe')));
    expect(h.calls.last, 'resume');
  });

  test('a probe that times out is an account failure', () async {
    final h = _Harness()
      ..requestTimeout = const Duration(milliseconds: 10)
      ..backend.rpcError = Exception('connection reset')
      ..backend.exists = false
      ..backend.probeGate = Completer<void>();
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.account);
    expect(h.calls, isNot(contains('wipe')));
    expect(h.calls.last, 'resume');
  });

  test('an rpc timeout goes to the probe', () async {
    final h = _Harness()
      ..rpcTimeout = const Duration(milliseconds: 10)
      ..backend.rpcGate = Completer<void>()
      ..backend.exists = false;
    final result = await h.build().deleteAccount();
    expect(result, isA<AccountDeleted>());
    expect(h.calls.sublist(h.calls.length - 5),
        ['rpc', 'probe', 'signOut', 'wipe', 'resume']);
  });

  test('an rpc timeout with the account still there is an account failure',
      () async {
    final h = _Harness()
      ..rpcTimeout = const Duration(milliseconds: 10)
      ..backend.rpcGate = Completer<void>();
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.account);
    expect(f.message, contains('TimeoutException'));
    expect(h.calls, isNot(contains('wipe')));
  });

  test('a PostgrestException failure reports its message only', () async {
    final h = _Harness()
      ..backend.rpcError = const PostgrestException(
        message: 'permission denied for function delete_my_account',
        code: '42501',
      );
    final f = _failed(await h.build().deleteAccount());
    expect(f.stage, AccountDeletionStage.account);
    expect(f.message, 'permission denied for function delete_my_account');
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

  group('SupabaseAccountDeletionBackend.isUserGone', () {
    test('user_not_found means gone', () {
      expect(
        SupabaseAccountDeletionBackend.isUserGone(AuthApiException(
          'User from sub claim in JWT does not exist',
          statusCode: '403',
          code: 'user_not_found',
        )),
        isTrue,
      );
    });

    test('other auth errors do not', () {
      expect(
        SupabaseAccountDeletionBackend.isUserGone(AuthApiException(
          'Session from session_id claim in JWT does not exist',
          statusCode: '403',
          code: 'session_not_found',
        )),
        isFalse,
      );
      expect(
        SupabaseAccountDeletionBackend.isUserGone(
            AuthRetryableFetchException()),
        isFalse,
      );
      expect(
        SupabaseAccountDeletionBackend.isUserGone(
            AuthSessionMissingException()),
        isFalse,
      );
    });
  });

  group('SupabaseAccountDeletionBackend.fetchAllPages', () {
    test('pages past 1000 rows and stops on an empty page', () async {
      final ranges = <(int, int)>[];
      final sizes = [1000, 1000, 3, 0];
      final keys = await SupabaseAccountDeletionBackend.fetchAllPages(
        (from, to) async {
          ranges.add((from, to));
          final n = sizes[ranges.length - 1];
          return List.generate(n, (i) => 'k${from + i}');
        },
      );
      expect(keys, hasLength(2003));
      expect(keys.toSet(), hasLength(2003));
      expect(ranges, [(0, 999), (1000, 1999), (2000, 2999), (2003, 3002)]);
    });

    test('a server cap below pageSize still fetches every key', () async {
      final all = List.generate(1203, (i) => 'k$i');
      final ranges = <(int, int)>[];
      final keys = await SupabaseAccountDeletionBackend.fetchAllPages(
        (from, to) async {
          ranges.add((from, to));
          // The server returns at most 500 rows whatever range is asked.
          final end = [to + 1, from + 500, all.length].reduce(min);
          return from >= end ? <String>[] : all.sublist(from, end);
        },
      );
      expect(keys, all);
      expect(ranges, [(0, 999), (500, 1499), (1000, 1999), (1203, 2202)]);
    });

    test('an empty first page returns nothing', () async {
      final keys = await SupabaseAccountDeletionBackend.fetchAllPages(
        (from, to) async => <String>[],
      );
      expect(keys, isEmpty);
    });
  });
}
