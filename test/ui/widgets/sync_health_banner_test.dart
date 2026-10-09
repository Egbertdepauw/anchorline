import 'package:ccrlogger/sync/cloud/sync_health_service.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:ccrlogger/ui/widgets/sync_health_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeClient implements SyncHealthClient {
  final List<SyncHealthSlot> slots;
  _FakeClient(this.slots);

  @override
  Future<List<SyncHealthSlot>> fetch() async => slots;
}

Future<void> _pump(WidgetTester tester, int retainedMb) async {
  final service = SyncHealthService(_FakeClient([
    SyncHealthSlot(
      slotName: 'powersync_test',
      active: true,
      walStatus: 'reserved',
      retainedMb: retainedMb,
    ),
  ]));
  addTearDown(service.dispose);
  await service.refresh();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SyncHealthBanner(service: service)),
  ));
}

Material _bannerMaterial(WidgetTester tester) => tester.widget<Material>(
      find
          .descendant(
            of: find.byType(SyncHealthBanner),
            matching: find.byType(Material),
          )
          .first,
    );

void main() {
  testWidgets('critical state uses the critical alert surface',
      (tester) async {
    await _pump(tester, 800);
    expect(_bannerMaterial(tester).color, SafetyColors.alertCriticalSurface);
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(icon.color, SafetyColors.onAlert);
  });

  testWidgets('warning state uses the warning alert surface', (tester) async {
    await _pump(tester, 300);
    expect(_bannerMaterial(tester).color, SafetyColors.alertWarningSurface);
    final icon = tester.widget<Icon>(find.byIcon(Icons.warning_amber));
    expect(icon.color, SafetyColors.onAlert);
  });
}
