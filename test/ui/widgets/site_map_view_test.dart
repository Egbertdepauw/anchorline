import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/widgets/map_layer_toggle.dart';
import 'package:ccrlogger/ui/widgets/map_tile_sources.dart';
import 'package:ccrlogger/ui/widgets/site_map_view.dart';
import 'package:ccrlogger/ui/widgets/site_mini_map.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SiteMapView shows coords label and is tappable',
      (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SiteMapView(
          lat: 52.2366,
          lon: 4.9570,
          siteName: 'Vinkeveen — de Dierentuin',
          onTap: () => taps++,
        ),
      ),
    ));

    expect(find.text('Vinkeveen — de Dierentuin'), findsOneWidget);
    expect(find.textContaining('52.2366'), findsOneWidget);
    expect(find.textContaining('4.9570'), findsOneWidget);

    // Verify the widget is actually rendered and test framework is working
    expect(find.byType(SiteMapView), findsOneWidget);
    // Two InkWells: one in the overlay strip, one inside MapLayerToggle.
    expect(find.byType(InkWell), findsWidgets);

    // Tap via the coords text — uniquely identifies the overlay InkWell.
    await tester.tap(find.textContaining('52.2366'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('SiteMapView shows the layer-toggle button', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SiteMapView(
          lat: 52.2366,
          lon: 4.9570,
          siteName: 'Vinkeveen',
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));
    expect(find.byType(MapLayerToggle), findsOneWidget);
    // Default style is normal — toggle shows the satellite-alt icon
    expect(find.byIcon(Icons.satellite_alt), findsOneWidget);
  });

  testWidgets('tapping the layer toggle swaps the TileLayer URL',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(
        body: SiteMapView(
          lat: 52.2366,
          lon: 4.9570,
        ),
      ),
    ));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // Verify TileLayer is using OSM url initially
    final beforeSiteMiniMap =
        tester.widget<SiteMiniMap>(find.byType(SiteMiniMap));
    expect(beforeSiteMiniMap.tileUrl, osmTileUrl);

    await tester.tap(find.byType(MapLayerToggle));
    await tester.pump();

    final afterSiteMiniMap =
        tester.widget<SiteMiniMap>(find.byType(SiteMiniMap));
    expect(afterSiteMiniMap.tileUrl, esriSatelliteTileUrl);
  });
}
