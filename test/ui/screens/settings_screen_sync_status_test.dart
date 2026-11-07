import 'dart:async';

import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:ccrlogger/sync/cloud/sync_status_source.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeAuthClient implements AuthClient {
  User? user;
  Session? session;
  final _ctrl = StreamController<AuthState>.broadcast();

  @override
  User? get currentUser => user;
  @override
  Session? get currentSession => session;
  @override
  Stream<AuthState> get onAuthStateChange => _ctrl.stream;

  @override
  Future<AuthResponse> signInWithPassword({
    required String email,
    required String password,
  }) async =>
      AuthResponse();

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async =>
      AuthResponse();

  @override
  Future<void> signOut() async {
    user = null;
    session = null;
  }

  void dispose() => _ctrl.close();
}

class _FakeSyncStatusSource implements SyncStatusSource {
  final _ctrl = StreamController<SyncStatusSnapshot>.broadcast();
  SyncStatusSnapshot _status;
  _FakeSyncStatusSource(this._status);

  @override
  SyncStatusSnapshot get currentStatus => _status;
  @override
  Stream<SyncStatusSnapshot> get statusStream => _ctrl.stream;

  void emit(SyncStatusSnapshot s) {
    _status = s;
    _ctrl.add(s);
  }

  void dispose() => _ctrl.close();
}

User _user(String id, String email) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: email,
      createdAt: DateTime.now().toIso8601String(),
    );

Future<({SettingsNotifier settings, AuthService auth, _FakeAuthClient client})>
    _buildSignedIn() async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsNotifier();
  await settings.load();
  final client = _FakeAuthClient();
  final u = _user('uid', 'me@example.test');
  client.user = u;
  client.session = Session(accessToken: 'token', tokenType: 'bearer', user: u);
  final auth = AuthService(client: client);
  return (settings: settings, auth: auth, client: client);
}

Future<void> _pump(
  WidgetTester tester,
  SettingsNotifier s,
  AuthService a,
  SyncStatusSource src,
) {
  return tester.pumpWidget(MaterialApp(
    home: SettingsScreen(
      notifier: s,
      authService: a,
      syncStatusSource: src,
      onHome: () {},
    ),
  )).then((_) async {
    await tester.tap(find.byKey(const ValueKey('settings-tab-sync')));
    await tester.pumpAndSettle();
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('renders Synced when connected and idle', (tester) async {
    final h = await _buildSignedIn();
    final src = _FakeSyncStatusSource(SyncStatusSnapshot(
      connected: true,
      lastSyncedAt: DateTime.now().subtract(const Duration(minutes: 5)),
    ));
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
      src.dispose();
    });

    await _pump(tester, h.settings, h.auth, src);
    expect(find.textContaining('🟢 Synced'), findsOneWidget);
    expect(find.textContaining('5 min ago'), findsOneWidget);
  });

  testWidgets('renders Syncing while uploading', (tester) async {
    final h = await _buildSignedIn();
    final src = _FakeSyncStatusSource(
      const SyncStatusSnapshot(connected: true, uploading: true),
    );
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
      src.dispose();
    });

    await _pump(tester, h.settings, h.auth, src);
    expect(find.textContaining('🟡 Syncing'), findsOneWidget);
  });

  testWidgets('renders Syncing while downloading', (tester) async {
    final h = await _buildSignedIn();
    final src = _FakeSyncStatusSource(
      const SyncStatusSnapshot(connected: true, downloading: true),
    );
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
      src.dispose();
    });

    await _pump(tester, h.settings, h.auth, src);
    expect(find.textContaining('🟡 Syncing'), findsOneWidget);
  });

  testWidgets('renders Offline when not connected', (tester) async {
    final h = await _buildSignedIn();
    final src = _FakeSyncStatusSource(const SyncStatusSnapshot());
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
      src.dispose();
    });

    await _pump(tester, h.settings, h.auth, src);
    expect(find.textContaining('🔴 Offline'), findsOneWidget);
  });

  testWidgets('reacts to status stream emissions', (tester) async {
    final h = await _buildSignedIn();
    final src = _FakeSyncStatusSource(const SyncStatusSnapshot());
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
      src.dispose();
    });

    await _pump(tester, h.settings, h.auth, src);
    expect(find.textContaining('🔴 Offline'), findsOneWidget);

    src.emit(const SyncStatusSnapshot(connected: true, uploading: true));
    await tester.pumpAndSettle();

    expect(find.textContaining('🟡 Syncing'), findsOneWidget);
  });
}
