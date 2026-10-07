import 'dart:async';

import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/settings_screen.dart';
import 'package:ccrlogger/ui/widgets/theme_picker.dart';
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

User _user(String id, String email) => User(
      id: id,
      appMetadata: const {},
      userMetadata: const {},
      aud: 'authenticated',
      email: email,
      createdAt: DateTime.now().toIso8601String(),
    );

Future<({SettingsNotifier settings, AuthService auth, _FakeAuthClient client})>
    _build({required bool signedIn}) async {
  SharedPreferences.setMockInitialValues({});
  final settings = SettingsNotifier();
  await settings.load();
  final client = _FakeAuthClient();
  if (signedIn) {
    final u = _user('uid', 'me@example.test');
    client.user = u;
    client.session = Session(
      accessToken: 'token',
      tokenType: 'bearer',
      user: u,
    );
  }
  final auth = AuthService(client: client);
  return (settings: settings, auth: auth, client: client);
}

Future<void> _pump(WidgetTester tester, SettingsNotifier s, AuthService a) {
  return tester.pumpWidget(MaterialApp(
    home: SettingsScreen(notifier: s, authService: a),
  ));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shows sign-in tile when signed out', (tester) async {
    final h = await _build(signedIn: false);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await _pump(tester, h.settings, h.auth);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Sign in to enable cloud sync'), findsOneWidget);
    expect(find.text('Sign out'), findsNothing);
  });

  testWidgets('tapping the tile opens the auth modal', (tester) async {
    final h = await _build(signedIn: false);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await _pump(tester, h.settings, h.auth);
    await tester.tap(find.text('Sign in to enable cloud sync'));
    await tester.pumpAndSettle();
    expect(find.text('Cloud sync sign-in'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });

  testWidgets('shows email + sign out when signed in', (tester) async {
    final h = await _build(signedIn: true);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await _pump(tester, h.settings, h.auth);
    expect(find.text('me@example.test'), findsOneWidget);
    expect(find.text('Last synced: never'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
    expect(find.text('Sign in to enable cloud sync'), findsNothing);
  });

  testWidgets('shows the Appearance section when showThemePicker is true',
      (tester) async {
    final h = await _build(signedIn: false);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          notifier: h.settings, authService: h.auth, showThemePicker: true),
    ));
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.byType(ThemePicker), findsOneWidget);
  });

  testWidgets('hides the Appearance section when showThemePicker is false',
      (tester) async {
    final h = await _build(signedIn: false);
    addTearDown(() {
      h.auth.dispose();
      h.client.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
          notifier: h.settings, authService: h.auth, showThemePicker: false),
    ));
    expect(find.text('Appearance'), findsNothing);
    expect(find.byType(ThemePicker), findsNothing);
  });
}
