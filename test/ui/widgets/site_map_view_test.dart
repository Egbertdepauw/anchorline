import 'package:ccrlogger/ui/theme/app_theme.dart';
import 'package:ccrlogger/ui/widgets/site_map_view.dart';
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
    expect(find.byType(InkWell), findsOneWidget);

    // Tap via the InkWell on the overlay strip
    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(taps, 1);
  });
}
