import 'package:ccrlogger/data/db/open_blends_dao.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/widgets/open_blends_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../_helpers/fake_open_blends_dao.dart';

final _now = DateTime(2026, 11, 13, 12);

OpenBlend _blend(String id, Duration age, {GasRole role = GasRole.bailout}) =>
    OpenBlend(
      id: id,
      target: const DesiredMix(18, 45),
      targetPressureBar: 230,
      residual: const DesiredMix(21, 0),
      residualPressureBar: 0,
      topoff: const DesiredMix(21, 0),
      waterCapacityL: 12,
      role: role,
      blendedBy: null,
      blendedAt: _now.subtract(age),
    );

Color _dot(WidgetTester tester, String id) {
  final box = tester.widget<Container>(find.byKey(ValueKey('settle-dot-$id')));
  return (box.decoration! as BoxDecoration).color!;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<FakeOpenBlendsDao> pump(
      WidgetTester tester, List<OpenBlend> blends) async {
    final settings = SettingsNotifier();
    await settings.load();
    final dao = FakeOpenBlendsDao(blends: blends);
    await tester.pumpWidget(MaterialApp(
      theme: AppThemes.all.first.themeData,
      home: Scaffold(
        body: SingleChildScrollView(
          child: OpenBlendsSection(
              dao: dao, settings: settings, now: () => _now),
        ),
      ),
    ));
    await tester.pump();
    return dao;
  }

  testWidgets('rows colour by settle time', (tester) async {
    await pump(tester, [
      _blend('a', const Duration(minutes: 10)),
      _blend('b', const Duration(minutes: 40)),
      _blend('c', const Duration(minutes: 70)),
    ]);
    expect(_dot(tester, 'a'), SafetyColors.danger);
    expect(_dot(tester, 'b'), SafetyColors.warning);
    expect(_dot(tester, 'c'), SafetyColors.success);
    expect(find.text('Not yet analysed (3)'), findsOneWidget);
    expect(find.text('10 min'), findsOneWidget);
    expect(find.text('1 h 10 min'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a blend from the future shows just now', (tester) async {
    await pump(tester, [_blend('f', const Duration(minutes: -30))]);
    expect(find.text('just now'), findsOneWidget);
    expect(_dot(tester, 'f'), SafetyColors.danger);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a row shows mix, role and target pressure', (tester) async {
    await pump(tester, [_blend('a', const Duration(minutes: 5),
        role: GasRole.diluent)]);
    expect(find.text('Tx18/45'), findsOneWidget);
    expect(find.textContaining('Diluent'), findsOneWidget);
    expect(find.textContaining('230 bar'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Dismiss removes the row', (tester) async {
    final dao = await pump(tester, [
      _blend('a', const Duration(minutes: 10)),
      _blend('b', const Duration(minutes: 40)),
    ]);
    await tester.tap(find.byKey(const ValueKey('open-blend-menu-a')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(dao.dismissed, ['a']);
    expect(find.byKey(const ValueKey('settle-dot-a')), findsNothing);
    expect(find.text('Not yet analysed (1)'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('nothing shows when there are no open blends', (tester) async {
    await pump(tester, []);
    expect(find.textContaining('Not yet analysed'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
