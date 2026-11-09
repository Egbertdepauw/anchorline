import 'package:ccrlogger/analyzer/bridge/bridge_link_ble.dart'
    show FoundBridge;
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/widgets/analyzer/bridge_transport_option.dart';
import 'package:ccrlogger/ui/widgets/analyzer_bridge_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_bridge_link.dart';

const _found = FoundBridge(id: 'X', name: 'Anchorline Bridge 1A2B');

Future<SettingsNotifier> _settings({bool paired = false}) async {
  SharedPreferences.setMockInitialValues({
    if (paired) 'analyzer_bridge_id': 'X',
    if (paired) 'analyzer_bridge_name': 'Anchorline Bridge 1A2B',
  });
  final s = SettingsNotifier();
  await s.load();
  return s;
}

Widget _host(SettingsNotifier s, {Future<FoundBridge?> Function(BuildContext)? find}) =>
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: AnalyzerBridgeSettingsSection(settings: s, findBridge: find),
        ),
      ),
    );

Finder _key(String k) => find.byKey(ValueKey(k));

void main() {
  testWidgets('says "No bridge set up" and offers Find bridge only',
      (tester) async {
    final s = await _settings();
    await tester.pumpWidget(_host(s));
    expect(find.text('No bridge set up'), findsOneWidget);
    expect(find.text('Find bridge'), findsOneWidget);
    expect(_key('analyzer-bridge-forget'), findsNothing);
    expect(
      find.text('Off: the SOLO runs on its own battery. On: the bridge '
          'supplies 5 V, which also charges the SOLO.'),
      findsOneWidget,
    );
  });

  testWidgets('Find bridge stores the bridge picked and shows its name',
      (tester) async {
    final s = await _settings();
    await tester.pumpWidget(_host(s, find: (_) async => _found));
    await tester.tap(_key('analyzer-bridge-find'));
    await tester.pumpAndSettle();
    expect(s.analyzerBridgeId, 'X');
    expect(s.analyzerBridgeName, 'Anchorline Bridge 1A2B');
    expect(find.text('Anchorline Bridge 1A2B'), findsOneWidget);
    expect(_key('analyzer-bridge-forget'), findsOneWidget);
  });

  testWidgets('a cancelled find changes nothing', (tester) async {
    final s = await _settings();
    await tester.pumpWidget(_host(s, find: (_) async => null));
    await tester.tap(_key('analyzer-bridge-find'));
    await tester.pumpAndSettle();
    expect(s.analyzerBridgeId, isNull);
  });

  testWidgets('Forget bridge clears it', (tester) async {
    final s = await _settings(paired: true);
    await tester.pumpWidget(_host(s));
    expect(find.text('Anchorline Bridge 1A2B'), findsOneWidget);
    await tester.tap(_key('analyzer-bridge-forget'));
    await tester.pumpAndSettle();
    expect(s.analyzerBridgeId, isNull);
    expect(find.text('No bridge set up'), findsOneWidget);
  });

  testWidgets('the switch turns the 5 V setting on', (tester) async {
    final s = await _settings();
    await tester.pumpWidget(_host(s));
    expect(s.analyzerBridgeVbus, isFalse);
    await tester.tap(_key('analyzer-bridge-vbus'));
    await tester.pumpAndSettle();
    expect(s.analyzerBridgeVbus, isTrue);
  });

  group('the Bridge source', () {
    testWidgets('pairs the bridge it finds when none is set up',
        (tester) async {
      final s = await _settings();
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));
      final option = bridgeTransportOption(
        s,
        linkFactory: (_) => FakeBridgeLink(),
        findBridge: (_) async => _found,
      );
      expect(option.label, 'Bridge');
      final transport = await option.choose!(context);
      expect(transport, isNotNull);
      expect(s.analyzerBridgeId, 'X');
      await transport!.dispose();
    });

    testWidgets('does not connect when the find is cancelled',
        (tester) async {
      final s = await _settings();
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));
      final option = bridgeTransportOption(
        s,
        linkFactory: (_) => FakeBridgeLink(),
        findBridge: (_) async => null,
      );
      expect(await option.choose!(context), isNull);
      expect(s.analyzerBridgeId, isNull);
    });

    testWidgets('uses the paired bridge without asking', (tester) async {
      final s = await _settings(paired: true);
      late BuildContext context;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          context = c;
          return const SizedBox();
        }),
      ));
      String? linkId;
      final option = bridgeTransportOption(
        s,
        linkFactory: (id) {
          linkId = id;
          return FakeBridgeLink();
        },
        findBridge: (_) async => fail('must not ask'),
      );
      final transport = await option.choose!(context);
      expect(linkId, 'X');
      await transport!.dispose();
    });
  });
}
