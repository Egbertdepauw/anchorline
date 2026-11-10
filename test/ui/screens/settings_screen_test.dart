import 'dart:async';

import 'package:ccrlogger/data/db/database.dart';
import 'package:ccrlogger/sync/cloud/account_deleter.dart';
import 'package:ccrlogger/sync/cloud/auth_service.dart';
import 'package:ccrlogger/sync/cloud/ccrlogger_backend_connector.dart';
import 'package:ccrlogger/sync/cloud/cloud_sync_coordinator.dart';
import 'package:ccrlogger/ui/components/value_stepper.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/settings_screen.dart';
import 'package:ccrlogger/ui/widgets/theme_picker.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:powersync/powersync.dart' hide Column;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../_helpers/powersync_test_helper.dart';

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

  /// When set, sign-up answers as Supabase does with Confirm email on.
  bool confirmEmail = false;
  AuthResponse Function()? verifyResponder;
  Object? resendError;
  final verifyCalls = <({String email, String code})>[];
  final resendCalls = <String>[];

  @override
  Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async =>
      confirmEmail ? AuthResponse(user: _user('new', email)) : AuthResponse();

  @override
  Future<AuthResponse> verifyEmailCode({
    required String email,
    required String code,
  }) async {
    verifyCalls.add((email: email, code: code));
    final r = verifyResponder!();
    if (r.session != null) {
      session = r.session;
      user = r.user;
    }
    return r;
  }

  @override
  Future<void> resendEmailCode({required String email}) async {
    resendCalls.add(email);
    final e = resendError;
    if (e != null) throw e;
  }

  final setPasswordCalls = <String>[];

  @override
  Future<void> setPassword(String password) async =>
      setPasswordCalls.add(password);

  @override
  Future<void> signOut() async {
    user = null;
    session = null;
  }

  /// Flips to signed out and tells listeners, like a real sign-out.
  void emitSignedOut() {
    user = null;
    session = null;
    _ctrl.add(const AuthState(AuthChangeEvent.signedOut, null));
  }

  void dispose() => _ctrl.close();
}

class _DeleteFakeSession implements SessionSource {
  @override
  Session? get currentSession => Session(
        accessToken: 'token',
        tokenType: 'bearer',
        user: _user('uid', 'me@example.test'),
      );
  @override
  Future<void> refreshSession() async {}
}

class _DeleteFakeBackend implements AccountDeletionBackend {
  @override
  Future<List<String>> listStorageKeys() async => const [];
  @override
  Future<void> deleteAccount() async {}
  @override
  Future<bool> accountExists() async => true;
}

class _DeleteFakeSync implements SyncPause {
  @override
  Future<void> pause() async {}
  @override
  Future<void> resume() async {}
}

AccountDeleter _fakeDeleter({Future<void> Function()? onSignOut}) =>
    AccountDeleter(
      session: _DeleteFakeSession(),
      backend: _DeleteFakeBackend(),
      sync: _DeleteFakeSync(),
      localStorageKeys: () async => const [],
      deleteObject: (_) async {},
      signOut: () async => onSignOut?.call(),
      wipeLocal: () async {},
    );

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

Future<void> _pump(
  WidgetTester tester,
  SettingsNotifier s,
  AuthService? a, {
  VoidCallback? onHome,
  bool showThemePicker = true,
  AppDatabase? db,
  PowerSyncDatabase? psDb,
  AccountDeleter? accountDeleter,
}) {
  return tester.pumpWidget(MaterialApp(
    home: SettingsScreen(
      notifier: s,
      authService: a,
      onHome: onHome ?? () {},
      showThemePicker: showThemePicker,
      db: db,
      powerSyncDb: psDb,
      accountDeleter: accountDeleter,
    ),
  ));
}

Future<void> _tab(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(ValueKey('settings-tab-$name')));
  await tester.pumpAndSettle();
}

Finder _k(String key) => find.byKey(ValueKey(key));

Future<SettingsNotifier> _plain([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final s = SettingsNotifier();
  await s.load();
  return s;
}

/// A reloaded notifier on the same mock prefs: what the next launch sees.
Future<SettingsNotifier> _reload() async {
  final s = SettingsNotifier();
  await s.load();
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('tabs', () {
    testWidgets('five tabs, labels only, General first', (tester) async {
      final s = await _plain();
      await _pump(tester, s, null);
      for (final label in ['General', 'Planning', 'Gas', 'Sync', 'About']) {
        final tab = _k('settings-tab-${label.toLowerCase()}');
        expect(tab, findsOneWidget);
        expect(find.descendant(of: tab, matching: find.text(label)),
            findsOneWidget);
        expect(find.descendant(of: tab, matching: find.byType(Icon)),
            findsNothing);
      }
      expect(find.text('YOU'), findsOneWidget);
    });

    testWidgets('the anchor calls onHome', (tester) async {
      final s = await _plain();
      var home = 0;
      await _pump(tester, s, null, onHome: () => home++);
      await tester.tap(_k('tab-top-bar-home'));
      expect(home, 1);
    });

    testWidgets('renders every tab in every theme without exceptions',
        (tester) async {
      final s = await _plain();
      for (final theme in AppThemes.all) {
        await tester.pumpWidget(MaterialApp(
          key: ValueKey(theme.id),
          theme: theme.themeData,
          home: SettingsScreen(notifier: s, onHome: () {}),
        ));
        for (final t in ['general', 'planning', 'gas', 'sync', 'about']) {
          await _tab(tester, t);
          expect(tester.takeException(), isNull, reason: '${theme.id} $t');
        }
      }
    });

    testWidgets('no overflow on a small phone with large text',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = await _plain();
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.3)),
          child: child!,
        ),
        home: SettingsScreen(notifier: s, onHome: () {}),
      ));
      for (final t in ['general', 'planning', 'gas', 'sync', 'about']) {
        await _tab(tester, t);
        expect(tester.takeException(), isNull, reason: t);
      }
    });
  });

  group('General', () {
    testWidgets('shows the Theme group when showThemePicker is true',
        (tester) async {
      final s = await _plain();
      await _pump(tester, s, null);
      expect(find.text('THEME'), findsOneWidget);
      expect(find.byType(ThemePicker), findsOneWidget);
    });

    testWidgets('hides the Theme group when showThemePicker is false',
        (tester) async {
      final s = await _plain();
      await _pump(tester, s, null, showThemePicker: false);
      expect(find.text('THEME'), findsNothing);
      expect(find.byType(ThemePicker), findsNothing);
    });

    testWidgets('picking a theme tile applies it', (tester) async {
      final s = await _plain();
      await _pump(tester, s, null);
      await tester.tap(_k('theme-hackerman'));
      await tester.pumpAndSettle();
      expect(s.themeId, 'hackerman');
    });

    testWidgets('Your initials persist', (tester) async {
      final s = await _plain();
      await _pump(tester, s, null);
      await tester.enterText(_k('settings-your-initials'), 'EdP');
      await tester.pumpAndSettle();
      expect(s.yourInitials, 'EdP');
      expect((await _reload()).yourInitials, 'EdP');
    });

    testWidgets('Colour by ascent speed toggles', (tester) async {
      final s = await _plain();
      final before = s.useSpeedColoredGraph;
      await _pump(tester, s, null);
      await tester.tap(_k('settings-speed-graph'));
      await tester.pumpAndSettle();
      expect(s.useSpeedColoredGraph, !before);
    });

    testWidgets('Count O₂ as narcotic in END toggles, helper has no agencies',
        (tester) async {
      final s = await _plain();
      final before = s.endCountsOxygen;
      await _pump(tester, s, null);
      expect(find.text('Off: only N₂ counts'), findsOneWidget);
      expect(find.textContaining('GUE'), findsNothing);
      expect(find.textContaining('TDI'), findsNothing);
      await tester.tap(_k('settings-end-counts-o2'));
      await tester.pumpAndSettle();
      expect(s.endCountsOxygen, !before);
    });

    testWidgets('Watermark stepper moves in whole percent', (tester) async {
      final s = await _plain({'watermark_opacity': 0.08});
      await _pump(tester, s, null);
      expect(tester.widget<Text>(_k('settings-watermark-value')).data, '8');
      await tester.tap(_k('settings-watermark-inc'));
      await tester.pumpAndSettle();
      expect(s.watermarkOpacity, closeTo(0.09, 1e-9));
      await tester.pumpAndSettle();
      await tester.tap(_k('settings-watermark-dec'));
      await tester.pumpAndSettle();
      await tester.tap(_k('settings-watermark-dec'));
      await tester.pumpAndSettle();
      expect(s.watermarkOpacity, closeTo(0.07, 1e-9));
    });
  });

  group('Planning', () {
    testWidgets('the four steppers change their settings', (tester) async {
      final s = await _plain();
      final sacB = s.bailoutSacBottom;
      final sacD = s.bailoutSacDeco;
      final fast = s.bailoutAscentRateFast;
      final slow = s.bailoutAscentRateSlow;
      await _pump(tester, s, null);
      await _tab(tester, 'planning');
      await tester.tap(_k('settings-sac-bottom-inc'));
      await tester.tap(_k('settings-sac-deco-dec'));
      await tester.tap(_k('settings-ascent-fast-dec'));
      await tester.tap(_k('settings-ascent-slow-inc'));
      await tester.pumpAndSettle();
      expect(s.bailoutSacBottom, sacB + 1);
      expect(s.bailoutSacDeco, sacD - 1);
      expect(s.bailoutAscentRateFast, fast - 1);
      expect(s.bailoutAscentRateSlow, slow + 1);
    });

    testWidgets('steppers stop at their limits', (tester) async {
      final s = await _plain({
        'bailout_sac_bottom': 60,
        'bailout_sac_deco': 10,
        'bailout_ascent_fast': 30,
        'bailout_ascent_slow': 3,
        'watermark_opacity': 0.20,
      });
      await _pump(tester, s, null);
      bool enabled(String key) =>
          tester.widget<IconButton>(_k(key)).onPressed != null;
      expect(enabled('settings-watermark-inc'), isFalse);
      expect(enabled('settings-watermark-dec'), isTrue);
      await _tab(tester, 'planning');
      expect(enabled('settings-sac-bottom-inc'), isFalse);
      expect(enabled('settings-sac-deco-dec'), isFalse);
      expect(enabled('settings-ascent-fast-inc'), isFalse);
      expect(enabled('settings-ascent-slow-dec'), isFalse);
      expect(find.byType(ValueStepper), findsNWidgets(4));
    });

    testWidgets('the bailout kit switches toggle', (tester) async {
      final s = await _plain();
      await _pump(tester, s, null);
      await _tab(tester, 'planning');
      await tester.tap(_k('settings-gue-diluent'));
      await tester.tap(_k('settings-tank-68'));
      await tester.tap(_k('settings-tank-12'));
      await tester.pumpAndSettle();
      expect(s.gueDiluentConfig, isTrue);
      expect(s.tank68L300Available, isTrue);
      expect(s.tank12L300Available, isTrue);
    });
  });

  group('Gas', () {
    Future<SettingsNotifier> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final s = await _plain();
      await _pump(tester, s, null);
      await _tab(tester, 'gas');
      return s;
    }

    testWidgets('prices, top-off fee, top-off mix and temps are editable',
        (tester) async {
      final s = await open(tester);
      await tester.enterText(_k('settings-blend-o2-cost'), '0.02');
      await tester.enterText(_k('settings-blend-he-cost'), '0.07');
      await tester.enterText(_k('settings-blend-air-fee'), '6.5');
      await tester.enterText(_k('settings-blend-topoff-o2'), '32');
      await tester.enterText(_k('settings-blend-topoff-he'), '10');
      await tester.enterText(_k('settings-blend-fill-temp'), '22');
      await tester.enterText(_k('settings-blend-settled-temp'), '15');
      await tester.pumpAndSettle();
      expect(s.blendOxygenCostPerLitre, 0.02);
      expect(s.blendHeliumCostPerLitre, 0.07);
      expect(s.blendAirFlatFee, 6.5);
      expect(s.blendTopoffOxygenPercent, 32);
      expect(s.blendTopoffHeliumPercent, 10);
      expect(s.blendFillTempC, 22);
      expect(s.blendSettledTempC, 15);
    });

    testWidgets('fill order and real-gas maths change', (tester) async {
      final s = await open(tester);
      await tester.tap(_k('settings-blend-sequence'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('O₂ → He → top-off').last);
      await tester.pumpAndSettle();
      expect(s.blendFillSequence, 'o2ThenHeThenTopoff');
      final before = s.blendUseRealGas;
      await tester.tap(_k('settings-blend-real-gas'));
      await tester.pumpAndSettle();
      expect(s.blendUseRealGas, !before);
    });

    testWidgets('MOD chips: remove 1.6, add 1.25, the last chip has no remove',
        (tester) async {
      final s = await open(tester);
      expect(_k('settings-mod-ppo2-1.1'), findsOneWidget);
      expect(_k('settings-mod-ppo2-1.6-remove'), findsOneWidget);

      await tester.tap(_k('settings-mod-ppo2-1.6-remove'));
      await tester.pumpAndSettle();
      expect(s.analyzerModPpo2s, [1.1, 1.4]);
      expect(_k('settings-mod-ppo2-1.6'), findsNothing);

      await tester.tap(_k('settings-mod-ppo2-add'));
      await tester.pumpAndSettle();
      await tester.enterText(_k('settings-mod-ppo2-input'), '1.25');
      await tester.tap(_k('settings-mod-ppo2-add-confirm'));
      await tester.pumpAndSettle();
      expect(s.analyzerModPpo2s, [1.1, 1.25, 1.4]);
      expect(_k('settings-mod-ppo2-1.25'), findsOneWidget);
      expect((await _reload()).analyzerModPpo2s, [1.1, 1.25, 1.4]);

      await tester.tap(_k('settings-mod-ppo2-1.1-remove'));
      await tester.tap(_k('settings-mod-ppo2-1.25-remove'));
      await tester.pumpAndSettle();
      expect(s.analyzerModPpo2s, [1.4]);
      expect(_k('settings-mod-ppo2-1.4'), findsOneWidget);
      expect(_k('settings-mod-ppo2-1.4-remove'), findsNothing);
    });

    testWidgets('the chip remove target is at least 44 x 44', (tester) async {
      await open(tester);
      for (final p in ['1.1', '1.4', '1.6']) {
        final size = tester.getSize(_k('settings-mod-ppo2-$p-remove'));
        expect(size.width, greaterThanOrEqualTo(44), reason: p);
        expect(size.height, greaterThanOrEqualTo(44), reason: p);
      }
    });

    testWidgets('the add dialog accepts 0.2 to 2.0 only and rounds to two decimals',
        (tester) async {
      final s = await open(tester);
      Future<void> add(String text) async {
        await tester.tap(_k('settings-mod-ppo2-add'));
        await tester.pumpAndSettle();
        await tester.enterText(_k('settings-mod-ppo2-input'), text);
        await tester.tap(_k('settings-mod-ppo2-add-confirm'));
        await tester.pumpAndSettle();
      }

      await add('2.5');
      expect(find.textContaining('from 0.2 to 2.0'), findsOneWidget);
      expect(s.analyzerModPpo2s, [1.1, 1.4, 1.6]);
      await tester.enterText(_k('settings-mod-ppo2-input'), '0.1');
      await tester.tap(_k('settings-mod-ppo2-add-confirm'));
      await tester.pumpAndSettle();
      expect(s.analyzerModPpo2s, [1.1, 1.4, 1.6]);
      await tester.enterText(_k('settings-mod-ppo2-input'), '1.234');
      await tester.tap(_k('settings-mod-ppo2-add-confirm'));
      await tester.pumpAndSettle();
      expect(s.analyzerModPpo2s, [1.1, 1.23, 1.4, 1.6]);

      await add('0.2');
      await add('2');
      expect(s.analyzerModPpo2s, [0.2, 1.1, 1.23, 1.4, 1.6, 2.0]);
    });

    testWidgets('Fill pressure starts at persists, default 230',
        (tester) async {
      final s = await open(tester);
      expect(s.analyzerFillPressureStartBar, 230);
      await tester.enterText(_k('settings-fill-pressure-start'), '200');
      await tester.pumpAndSettle();
      expect(s.analyzerFillPressureStartBar, 200);
      expect((await _reload()).analyzerFillPressureStartBar, 200);
    });
  });

  group('Sync', () {
    testWidgets('shows sign-in row when signed out', (tester) async {
      final h = await _build(signedIn: false);
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
      });
      await _pump(tester, h.settings, h.auth);
      await _tab(tester, 'sync');
      expect(find.text('ANCHORLINE ACCOUNT'), findsOneWidget);
      expect(find.text('Sign in to enable cloud sync'), findsOneWidget);
      expect(find.text('Sign out'), findsNothing);
    });

    testWidgets('tapping the row opens the auth modal', (tester) async {
      final h = await _build(signedIn: false);
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
      });
      await _pump(tester, h.settings, h.auth);
      await _tab(tester, 'sync');
      await tester.tap(find.text('Sign in to enable cloud sync'));
      await tester.pumpAndSettle();
      expect(find.text('Cloud sync sign-in'), findsOneWidget);
      expect(find.text('Email'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
    });

    group('email confirmation code', () {
      Future<void> createAccount(WidgetTester tester, String email) async {
        await tester.tap(find.text('Sign in to enable cloud sync'));
        await tester.pumpAndSettle();
        await tester.enterText(find.widgetWithText(TextField, 'Email'), email);
        await tester.enterText(
            find.widgetWithText(TextField, 'Password'), 'secret-pw');
        await tester.tap(find.text('Create account'));
        await tester.pumpAndSettle();
      }

      testWidgets('Create account asks for the code, and the code signs in',
          (tester) async {
        final h = await _build(signedIn: false);
        addTearDown(() {
          h.auth.dispose();
          h.client.dispose();
        });
        h.client.confirmEmail = true;
        final u = _user('new', 'new@example.test');
        h.client.verifyResponder = () => AuthResponse(
            session: Session(accessToken: 't', tokenType: 'bearer', user: u),
            user: u);
        await _pump(tester, h.settings, h.auth);
        await _tab(tester, 'sync');
        await createAccount(tester, 'new@example.test');

        expect(find.text('Confirm your email'), findsOneWidget);
        expect(find.textContaining('new@example.test'), findsOneWidget);

        await tester.enterText(
            find.byKey(const ValueKey('auth-code-field')), '123456');
        await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
        await tester.pumpAndSettle();

        expect(h.client.verifyCalls.single,
            (email: 'new@example.test', code: '123456'));
        expect(h.client.setPasswordCalls, ['secret-pw']);
        expect(find.text('Confirm your email'), findsNothing);
        expect(find.text('Signed in as new@example.test'), findsOneWidget);
        expect(h.auth.isSignedIn, isTrue);
      });

      testWidgets('a wrong code keeps the code step and says why',
          (tester) async {
        final h = await _build(signedIn: false);
        addTearDown(() {
          h.auth.dispose();
          h.client.dispose();
        });
        h.client.confirmEmail = true;
        h.client.verifyResponder = () => throw const AuthException(
            'Token has expired or is invalid',
            code: 'otp_expired');
        await _pump(tester, h.settings, h.auth);
        await _tab(tester, 'sync');
        await createAccount(tester, 'new@example.test');

        await tester.enterText(
            find.byKey(const ValueKey('auth-code-field')), '000000');
        await tester.tap(find.widgetWithText(FilledButton, 'Verify'));
        await tester.pumpAndSettle();

        expect(find.text('Confirm your email'), findsOneWidget);
        expect(find.textContaining('wrong or has expired'), findsOneWidget);
        expect(h.auth.isSignedIn, isFalse);
      });

      testWidgets('Resend code sends a new code, or shows why it could not',
          (tester) async {
        final h = await _build(signedIn: false);
        addTearDown(() {
          h.auth.dispose();
          h.client.dispose();
        });
        h.client.confirmEmail = true;
        await _pump(tester, h.settings, h.auth);
        await _tab(tester, 'sync');
        await createAccount(tester, 'new@example.test');

        await tester.tap(find.text('Resend code'));
        await tester.pumpAndSettle();
        expect(h.client.resendCalls, ['new@example.test']);
        expect(find.text('New code sent to new@example.test.'), findsOneWidget);

        h.client.resendError = const AuthException(
            'For security purposes, you can only request this after 42 '
            'seconds.',
            code: 'over_email_send_rate_limit');
        await tester.tap(find.text('Resend code'));
        await tester.pumpAndSettle();
        expect(find.textContaining('after 42'), findsOneWidget);
        expect(find.text('New code sent to new@example.test.'), findsNothing);
      });

      testWidgets('Back returns to the sign-in form', (tester) async {
        final h = await _build(signedIn: false);
        addTearDown(() {
          h.auth.dispose();
          h.client.dispose();
        });
        h.client.confirmEmail = true;
        await _pump(tester, h.settings, h.auth);
        await _tab(tester, 'sync');
        await createAccount(tester, 'new@example.test');

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();
        expect(find.text('Cloud sync sign-in'), findsOneWidget);
        expect(find.text('Create account'), findsOneWidget);
      });
    });

    testWidgets('shows email + sign out when signed in', (tester) async {
      final h = await _build(signedIn: true);
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
      });
      await _pump(tester, h.settings, h.auth);
      await _tab(tester, 'sync');
      expect(find.text('me@example.test'), findsOneWidget);
      expect(find.text('Last synced: never'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Sign out'), findsOneWidget);
      expect(find.text('Sign in to enable cloud sync'), findsNothing);
    });

    testWidgets('Repair rows without databases: Reset is hidden, the others say so',
        (tester) async {
      final s = await _plain();
      await _pump(tester, s, null);
      await _tab(tester, 'sync');
      expect(find.text('Re-assign dives to this account'), findsOneWidget);
      expect(find.text('Push stuck uploads'), findsOneWidget);
      expect(_k('settings-repair-reset'), findsNothing);
      await tester.tap(_k('settings-repair-reassign'));
      await tester.pump();
      expect(find.text('PowerSync is not available on this build.'),
          findsOneWidget);
    });

    testWidgets('Delete account row shows only when signed in',
        (tester) async {
      final h = await _build(signedIn: true);
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
      });
      await _pump(tester, h.settings, h.auth, accountDeleter: _fakeDeleter());
      await _tab(tester, 'sync');
      expect(_k('settings-account-delete'), findsOneWidget);
      expect(find.text('Deletes your account and all its data'),
          findsOneWidget);
      final title = tester.widget<Text>(find.text('Delete account'));
      expect(title.style!.color, SafetyColors.danger);
    });

    testWidgets('Delete account row is absent when signed out',
        (tester) async {
      final h = await _build(signedIn: false);
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
      });
      await _pump(tester, h.settings, h.auth, accountDeleter: _fakeDeleter());
      await _tab(tester, 'sync');
      expect(_k('settings-account-delete'), findsNothing);
    });

    testWidgets('Delete account row is absent without an accountDeleter',
        (tester) async {
      final h = await _build(signedIn: true);
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
      });
      await _pump(tester, h.settings, h.auth);
      await _tab(tester, 'sync');
      expect(_k('settings-account-delete'), findsNothing);
    });

    testWidgets('success dialog survives the sign-out rebuild',
        (tester) async {
      final h = await _build(signedIn: true);
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
      });
      await _pump(tester, h.settings, h.auth,
          accountDeleter: _fakeDeleter(onSignOut: () async {
        h.client.emitSignedOut();
      }));
      await _tab(tester, 'sync');
      await tester.tap(_k('settings-account-delete'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Delete account'));
      await tester.pumpAndSettle();
      expect(_k('settings-account-delete'), findsNothing);
      expect(find.text('Account deleted'), findsOneWidget);
    });

    testWidgets("Repair rows open today's dialogs", (tester) async {
      final h = await _build(signedIn: true);
      late PowerSyncDatabase psDb;
      final db = AppDatabase(NativeDatabase.memory());
      await tester.runAsync(() async {
        psDb = await openPowerSyncForTest();
      });
      addTearDown(() {
        h.auth.dispose();
        h.client.dispose();
        return db.close();
      });
      await _pump(tester, h.settings, h.auth, db: db, psDb: psDb);
      await _tab(tester, 'sync');

      expect(find.text('Reset local data'), findsOneWidget);
      // Danger styling: the title is not in the normal text colour.
      final resetTitle = tester.widget<Text>(find.text('Reset local data'));
      expect(resetTitle.style!.color, SafetyColors.danger);

      await tester.tap(_k('settings-repair-reassign'));
      await tester.pumpAndSettle();
      expect(find.text('Force-stamp owner_id?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.tap(_k('settings-repair-reset'));
      await tester.pumpAndSettle();
      expect(find.text('Reset data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      // The empty-queue check reads the real database, so it runs in real time.
      await tester.runAsync(() async {
        await tester.tap(_k('settings-repair-push'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      expect(find.text('Queue is empty — nothing to drain.'), findsOneWidget);
    });
  });

  group('About', () {
    testWidgets('keeps the version, the BLE log action and the logo',
        (tester) async {
      final s = await _plain();
      await _pump(tester, s, null);
      await _tab(tester, 'about');
      // Tests do not pass BUILD_CHANNEL, so this is the local-build label.
      expect(_k('about-dev-build'), findsOneWidget);
      expect(find.text('Share Bluetooth debug log'), findsOneWidget);
      expect(_k('about-share-ble-log'), findsOneWidget);
      expect(_k('about-logo'), findsOneWidget);
    });
  });
}
