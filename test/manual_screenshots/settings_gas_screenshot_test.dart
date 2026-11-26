// Renders the user-manual screenshots of Settings -> Gas from a widget test,
// for when no iPhone simulator is at hand (Linux CI, a machine without a Mac).
//
// Skipped unless opted in, so a plain `flutter test` writes no files:
//
//   flutter test test/manual_screenshots \
//     --dart-define=MANUAL_SCREENSHOTS=true
//
// Writes docs/user/images/settings-gas-1.png (top of the tab) and
// settings-gas-2.png (Analyzer and the whole Label printer section), at
// 390 x 844 logical px, 2x, with the app's real fonts and default dark theme.
// The Label printer section is shown without a printer, so it reads
// "No printer set up". There is no status bar or bottom navigation.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ccrlogger/label_printer/label_printer.dart';
import 'package:ccrlogger/labels/label_print_service.dart';
import 'package:ccrlogger/ui/notifiers/settings_notifier.dart';
import 'package:ccrlogger/ui/screens/settings/gas_tab.dart';
import 'package:ccrlogger/ui/screens/settings_screen.dart';
import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/widgets/label_printer_settings_section.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _enabled = bool.fromEnvironment('MANUAL_SCREENSHOTS');
const _outDir = 'docs/user/images';

/// iPhone 14 / 15 logical size and top safe area.
const _size = Size(390, 844);
const _topInset = 47.0;
const _pixelRatio = 2.0;

class _NoScanner implements LabelPrinterScanner {
  @override
  Stream<List<FoundLabelPrinter>> scan({
    Duration timeout = const Duration(seconds: 10),
  }) => const Stream.empty();

  @override
  Future<void> stop() async {}
}

Future<void> _loadFonts() async {
  for (final (family, asset) in [
    ('Inter', 'fonts/Inter-VariableFont.ttf'),
    // Text without a font family (the tab labels) falls back to Roboto,
    // which flutter_test maps to boxes. On an iPhone it is the system font;
    // Inter is the nearest thing the app ships.
    ('Roboto', 'fonts/Inter-VariableFont.ttf'),
    ('JetBrainsMono', 'fonts/JetBrainsMono-VariableFont.ttf'),
  ]) {
    await (FontLoader(family)..addFont(rootBundle.load(asset))).load();
  }
  // The test asset bundle carries the Material icon font when
  // uses-material-design is on.
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

void main() {
  // Opt-in tool, not a check: skipped unless MANUAL_SCREENSHOTS is defined.
  testWidgets('Settings -> Gas manual screenshots', (tester) async {
    await _loadFonts();
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsNotifier();
    await settings.load();
    final labels = LabelPrintService(
      render: (label, size, rotate) => throw UnimplementedError(),
      printerFor: (id) => throw UnimplementedError(),
      scanner: _NoScanner(),
      printerId: () => null,
      use14ForDeeperMixes: () => settings.labelUse14ForDeeperMixes,
    );

    tester.view
      ..physicalSize = _size * _pixelRatio
      ..devicePixelRatio = _pixelRatio;
    addTearDown(tester.view.reset);

    final boundary = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppThemes.byId(null).themeData,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(padding: const EdgeInsets.only(top: _topInset)),
            child: child!,
          ),
          home: SettingsScreen(
            notifier: settings,
            onHome: () {},
            labelPrinting: labels,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('settings-tab-gas')));
    await tester.pumpAndSettle();

    Future<void> shoot(String name) => tester.runAsync(() async {
      final obj =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await obj.toImage(pixelRatio: _pixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$_outDir/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
    });

    await shoot('settings-gas-1.png');

    // The tab is a lazy list: scroll to its end so the Label printer section
    // is built.
    final list = find
        .descendant(
          of: find.byType(GasSettingsTab),
          matching: find.byType(Scrollable),
        )
        .first;
    await tester.drag(list, const Offset(0, -5000));
    await tester.pumpAndSettle();
    // Then back up until the Label printer section ends at the bottom edge,
    // so the Analyzer rows above it stay in view.
    await Scrollable.ensureVisible(
      tester.element(find.byType(LabelPrinterSettingsSection)),
      alignment: 1,
    );
    await tester.pumpAndSettle();
    await shoot('settings-gas-2.png');
    expect(tester.takeException(), isNull);
  }, skip: !_enabled);
}
