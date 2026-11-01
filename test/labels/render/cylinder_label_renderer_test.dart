import 'dart:io';

import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:ccrlogger/labels/render/cylinder_label_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _when = DateTime(2026, 10, 31, 18, 5);

/// Everything printed must stay inside this (the 12-dot safe margin).
final _safeArea = Rect.fromLTRB(
  kLabelSafeMarginDots.toDouble(),
  kLabelSafeMarginDots.toDouble(),
  (kLabelWidthDots - kLabelSafeMarginDots).toDouble(),
  (kLabelHeightDots - kLabelSafeMarginDots).toDouble(),
);

CylinderLabel _label(
  double o2,
  double he, {
  int? desiredO2,
  int? desiredHe,
  GasRole role = GasRole.bailout,
  String? by,
  DateTime? when,
}) =>
    CylinderLabel.fromAnalysis(
      GasAnalysis(
        id: 'a1',
        analysedBy: by,
        analysedAt: when ?? _when,
        o2Percent: o2,
        hePercent: he,
        stable: true,
        targetO2Percent: desiredO2,
        targetHePercent: desiredHe,
        gasRole: role,
      ),
      use14ForDeeperMixes: false,
    );

final _tx2135 = _label(20.6, 33.8, desiredO2: 21, desiredHe: 35, by: 'EdP');
final _ean50 = _label(50.1, 0, desiredO2: 50, desiredHe: 0);
final _o2 = _label(99.6, 0, desiredO2: 100, desiredHe: 0);
final _tx1170 = _label(11.4, 70.2, desiredO2: 11, desiredHe: 70);
final _tx2135Diluent = _label(
  20.6,
  33.8,
  desiredO2: 21,
  desiredHe: 35,
  role: GasRole.diluent,
  by: 'EdP',
);
final _longInitials = _label(
  20.6,
  33.8,
  desiredO2: 21,
  desiredHe: 35,
  by: 'Egbert de Pauw',
);

/// A wide date with a descender (`28 May 26`) on the label with the most
/// small text: the footer and diluent line must still fit the margin.
final _mayDiluent = _label(
  20.6,
  33.8,
  desiredO2: 21,
  desiredHe: 35,
  role: GasRole.diluent,
  by: 'EdP',
  when: DateTime(2026, 5, 28),
);

/// Whether [inner] lies entirely within [outer] (edges may touch).
bool _within(Rect inner, Rect outer) =>
    inner.left >= outer.left &&
    inner.top >= outer.top &&
    inner.right <= outer.right &&
    inner.bottom <= outer.bottom;

/// How many pixels of [r] (rounded to whole dots) are black, or white when
/// [black] is false.
int _count(LabelBitmap b, Rect r, {bool black = true}) {
  var n = 0;
  for (var y = r.top.round(); y < r.bottom.round(); y++) {
    for (var x = r.left.round(); x < r.right.round(); x++) {
      if (b.isBlack(x, y) == black) n++;
    }
  }
  return n;
}

int _area(Rect r) =>
    (r.right.round() - r.left.round()) * (r.bottom.round() - r.top.round());

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    final loader = FontLoader('Inter')
      ..addFont(rootBundle.load('fonts/Inter-VariableFont.ttf'));
    await loader.load();
  });

  final samples = <String, CylinderLabel>{
    'Tx21/35 bailout': _tx2135,
    'EAN50 bailout': _ean50,
    'O2 bailout': _o2,
    'Tx11/70 bailout (130 m)': _tx1170,
    'Tx21/35 diluent': _tx2135Diluent,
    'long initials': _longInitials,
    'diluent dated 28 May 26': _mayDiluent,
  };

  for (final sample in samples.entries) {
    group(sample.key, () {
      late CylinderLabelRender r;
      setUpAll(() async {
        r = await renderCylinderLabelWithLayout(sample.value);
      });

      test('is 384 x 240 dots', () {
        expect(r.bitmap.width, 384);
        expect(r.bitmap.height, 240);
      });

      test('has no black pixel within 12 dots of an edge', () {
        final outside = <String>[];
        for (var y = 0; y < r.bitmap.height; y++) {
          for (var x = 0; x < r.bitmap.width; x++) {
            final inside = x >= 12 && x < 372 && y >= 12 && y < 228;
            if (!inside && r.bitmap.isBlack(x, y)) outside.add('($x, $y)');
          }
        }
        expect(outside, isEmpty);
      });

      test('lays every element out inside the safe area', () {
        expect(_within(r.bar, _safeArea), isTrue, reason: 'bar ${r.bar}');
        expect(_within(r.mixName, _safeArea), isTrue,
            reason: 'mixName ${r.mixName}');
        expect(_within(r.headline, _safeArea), isTrue,
            reason: 'headline ${r.headline}');
        final initials = r.initials;
        if (initials != null) {
          expect(_within(initials, _safeArea), isTrue,
              reason: 'initials $initials');
        }
        final tag = r.tag;
        if (tag != null) {
          expect(_within(tag, _safeArea), isTrue, reason: 'tag $tag');
        }
      });

      test('draws a mostly black bar', () {
        expect(_count(r.bitmap, r.bar),
            greaterThanOrEqualTo(0.6 * _area(r.bar)));
      });

      test('draws the headline', () {
        expect(_count(r.bitmap, r.headline), greaterThan(0));
      });

      if (sample.value.kind == CylinderLabelKind.diluent) {
        test('puts an outlined DIL tag in the bar, left of the mix name', () {
          final tag = r.tag;
          expect(tag, isNotNull);
          expect(_within(tag!, r.bar), isTrue,
              reason: 'tag $tag, bar ${r.bar}');
          expect(tag.right, lessThanOrEqualTo(r.mixName.left));
          expect(_count(r.bitmap, tag, black: false), greaterThan(0));
        });
      } else {
        test('has no tag', () {
          expect(r.tag, isNull);
        });
      }
    });
  }

  test('fits the 130 m headline (Tx11/70 at 11.4 %) inside the margin',
      () async {
    expect(_tx1170.headlineText, '130');
    final r = await renderCylinderLabelWithLayout(_tx1170);
    expect(r.headline.right, lessThanOrEqualTo(372));
  });

  test('renderCylinderLabel returns the bitmap of the layout render',
      () async {
    final r = await renderCylinderLabelWithLayout(_tx2135);
    final bitmap = await renderCylinderLabel(_tx2135);
    expect(bitmap.width, r.bitmap.width);
    expect(bitmap.height, r.bitmap.height);
    expect(bitmap.bits, r.bitmap.bits);
  });

  group('a long "analysed by" (Review Focus 5)', () {
    test('keeps the whole mix name and fits the initials after it', () async {
      final long = await renderCylinderLabelWithLayout(_longInitials);
      final none = await renderCylinderLabelWithLayout(
        _label(20.6, 33.8, desiredO2: 21, desiredHe: 35),
      );
      expect(none.initials, isNull);
      expect(long.mixName, none.mixName);
      final initials = long.initials;
      expect(initials, isNotNull);
      expect(initials!.left, greaterThanOrEqualTo(long.mixName.right));
      expect(initials.right, lessThanOrEqualTo(372));
    });
  });

  // Font rasterization differs between macOS and the Ubuntu CI runners, so
  // the goldens are only compared on macOS. Regenerate them there with
  // `flutter test --update-goldens test/labels/render`.
  group('goldens', () {
    final goldens = <String, CylinderLabel>{
      'tx2135_bailout': _tx2135,
      'ean50_bailout': _ean50,
      'o2_bailout': _o2,
      'tx1170_130m': _tx1170,
      'tx2135_diluent': _tx2135Diluent,
      'long_initials': _longInitials,
    };
    for (final g in goldens.entries) {
      test(g.key, () async {
        await expectLater(
          await renderCylinderLabelImage(g.value),
          matchesGoldenFile('goldens/${g.key}.png'),
        );
      }, skip: !Platform.isMacOS);
    }
  });
}
