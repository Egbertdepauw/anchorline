import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/widgets/map_layer_toggle.dart';
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows satellite-alt icon when current is Normal', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MapLayerToggle(
          current: MapLayerStyle.normal,
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.satellite_alt), findsOneWidget);
    expect(find.byIcon(Icons.layers_outlined), findsNothing);
  });

  testWidgets('shows layers icon when current is Satellite', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MapLayerToggle(
          current: MapLayerStyle.satellite,
          onChanged: (_) {},
        ),
      ),
    ));
    expect(find.byIcon(Icons.layers_outlined), findsOneWidget);
    expect(find.byIcon(Icons.satellite_alt), findsNothing);
  });

  testWidgets('tap fires onChanged with the opposite style', (tester) async {
    MapLayerStyle? received;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: MapLayerToggle(
          current: MapLayerStyle.normal,
          onChanged: (v) => received = v,
        ),
      ),
    ));
    await tester.tap(find.byType(MapLayerToggle));
    expect(received, MapLayerStyle.satellite);
  });
}
