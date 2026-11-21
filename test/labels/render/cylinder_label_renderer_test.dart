import 'dart:io';

import 'package:ccrlogger/data/models/gas_analysis.dart';
import 'package:ccrlogger/label_printer/label_bitmap.dart';
import 'package:ccrlogger/labels/cylinder_label.dart';
import 'package:ccrlogger/labels/render/cylinder_label_renderer.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

final _when = DateTime(2026, 10, 31, 18, 5);

/// Everything printed must stay inside this (the 12-dot safe margin of the
/// label, which for the 40 mm label sits inside the centred 320 dots).
Rect _safeAreaOf(LabelSize size) => Rect.fromLTRB(
      (size.offsetDots + kLabelSafeMarginDots).toDouble(),
      kLabelSafeMarginDots.toDouble(),
      (size.offsetDots + size.widthDots - kLabelSafeMarginDots).toDouble(),
      (size.heightDots - kLabelSafeMarginDots).toDouble(),
    );

CylinderLabel _label(
  double o2,
  double he, {
  int? desiredO2,
  int? desiredHe,
  GasRole role = GasRole.bailout,
  String? by,
  DateTime? when,
  double ocWorkingPpo2 = 1.4,
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
      ocWorkingPpo2: ocWorkingPpo2,
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
final _tx2135Oc = _label(
  20.6,
  33.8,
  desiredO2: 21,
  desiredHe: 35,
  role: GasRole.backgas,
  by: 'EdP',
);
final _ean32Oc = _label(
  32.0,
  0,
  desiredO2: 32,
  desiredHe: 0,
  role: GasRole.backgas,
  ocWorkingPpo2: 1.3,
);

/// A 3-digit headline (130 m) with the wider `ppO2 1.4` caption.
final _tx1070Oc = _label(
  10.0,
  70.0,
  desiredO2: 10,
  desiredHe: 70,
  role: GasRole.backgas,
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
    'Tx21/35 OC': _tx2135Oc,
    'EAN32 OC at 1.3': _ean32Oc,
    'Tx10/70 OC (130 m)': _tx1070Oc,
  };

  for (final size in LabelSize.values) {
    for (final sample in samples.entries) {
      group('${sample.key} on ${size.displayName}', () {
        late CylinderLabelRender r;
        final safe = _safeAreaOf(size);
        setUpAll(() async {
          r = await renderCylinderLabelWithLayout(sample.value, size);
        });

        test('is 384 dots wide and as long as the size', () {
          expect(r.bitmap.width, 384);
          expect(r.bitmap.height, size.heightDots);
        });

        test('has no black pixel outside the label\'s safe margin', () {
          final outside = <String>[];
          for (var y = 0; y < r.bitmap.height; y++) {
            for (var x = 0; x < r.bitmap.width; x++) {
              final inside = x >= safe.left &&
                  x < safe.right &&
                  y >= safe.top &&
                  y < safe.bottom;
              if (!inside && r.bitmap.isBlack(x, y)) outside.add('($x, $y)');
            }
          }
          expect(outside, isEmpty);
        });

        test('lays every element out inside the safe area', () {
          expect(_within(r.bar, safe), isTrue, reason: 'bar ${r.bar}');
          expect(_within(r.mixName, safe), isTrue,
              reason: 'mixName ${r.mixName}');
          expect(_within(r.headline, safe), isTrue,
              reason: 'headline ${r.headline}');
          final initials = r.initials;
          if (initials != null) {
            expect(_within(initials, safe), isTrue,
                reason: 'initials $initials');
          }
          final tag = r.tag;
          if (tag != null) {
            expect(_within(tag, safe), isTrue, reason: 'tag $tag');
          }
        });

        test('draws a mostly black bar', () {
          expect(_count(r.bitmap, r.bar),
              greaterThanOrEqualTo(0.6 * _area(r.bar)));
        });

        test('draws the headline', () {
          expect(_count(r.bitmap, r.headline), greaterThan(0));
        });

        if (sample.value.kind != CylinderLabelKind.bailout) {
          test('puts an outlined tag in the bar, left of the mix name', () {
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
  }

  test('the 40 mm label is the 50 mm one centred: nothing in the outer 32 dots',
      () async {
    final r = await renderCylinderLabelWithLayout(_tx2135, LabelSize.mm40x30);
    for (var y = 0; y < r.bitmap.height; y++) {
      for (var x = 0; x < 32 + 12; x++) {
        expect(r.bitmap.isBlack(x, y), isFalse, reason: '($x, $y)');
        expect(r.bitmap.isBlack(383 - x, y), isFalse, reason: '(${383 - x}, $y)');
      }
    }
    // The bar spans the label's own safe width, centred in the bitmap.
    expect(r.bar.left, 44);
    expect(r.bar.right, 340);
  });

  group('rotated centre on 50 x 80', () {
    final safe = _safeAreaOf(LabelSize.mm50x80);
    final samples = {
      'bailout': _tx2135,
      'diluent': _tx2135Diluent,
      'oc': _tx2135Oc,
      'oc 3-digit': _tx1070Oc,
      'bailout 3-digit': _tx1170,
    };
    for (final s in samples.entries) {
      test('${s.key}: stays inside the safe area', () async {
        final r = await renderCylinderLabelWithLayout(
            s.value, LabelSize.mm50x80, true);
        expect(_within(r.headline, safe), isTrue, reason: '${r.headline}');
        expect(_count(r.bitmap, r.headline), greaterThan(0));
        // Taller than wide: the depth runs along the label.
        expect(r.headline.height, greaterThan(r.headline.width));
        for (var y = 0; y < r.bitmap.height; y++) {
          for (var x = 0; x < r.bitmap.width; x++) {
            final inside = x >= safe.left &&
                x < safe.right &&
                y >= safe.top &&
                y < safe.bottom;
            if (!inside) {
              expect(r.bitmap.isBlack(x, y), isFalse, reason: '($x, $y)');
            }
          }
        }
      });
    }

    test('the depth is bigger than upright', () async {
      final up = await renderCylinderLabelWithLayout(_tx2135, LabelSize.mm50x80);
      final turned = await renderCylinderLabelWithLayout(
          _tx2135, LabelSize.mm50x80, true);
      expect(turned.headline.height, greaterThan(up.headline.width));
    });

    test('has no effect on the other sizes', () async {
      for (final size in LabelSize.values) {
        if (size == LabelSize.mm50x80) continue;
        for (final l in [_tx2135, _tx2135Diluent, _tx2135Oc, _tx1070Oc]) {
          final off = await renderCylinderLabel(l, size);
          final on = await renderCylinderLabel(l, size, true);
          expect(on.bits, off.bits, reason: size.displayName);
        }
      }
    });
  });

  test('the initials show on every 40 x 30 and tall layout', () async {
    for (final size in [
      LabelSize.mm40x30,
      LabelSize.mm50x50,
      LabelSize.mm50x80,
    ]) {
      for (final l in [_tx2135, _tx2135Diluent, _tx2135Oc, _tx1070Oc]) {
        final r = await renderCylinderLabelWithLayout(l, size);
        expect(r.initials, isNotNull, reason: size.displayName);
      }
    }
  });

  test('a taller label gets a bigger headline depth', () async {
    Future<double> height(LabelSize size) async =>
        (await renderCylinderLabelWithLayout(_tx2135, size)).headline.height;
    final short = await height(LabelSize.mm50x30);
    final tall = await height(LabelSize.mm50x50);
    final taller = await height(LabelSize.mm50x80);
    expect(tall, greaterThan(short));
    expect(taller, greaterThan(tall));
  });

  test('50 x 30 is unchanged by the size parameter', () async {
    final implicit = await renderCylinderLabel(_tx2135);
    final explicit = await renderCylinderLabel(_tx2135, LabelSize.mm50x30);
    expect(implicit.bits, explicit.bits);
  });

  test('fits the 130 m headline (Tx11/70 at 11.4 %) inside the margin, at every size',
      () async {
    expect(_tx1170.headlineText, '130');
    for (final size in LabelSize.values) {
      final r = await renderCylinderLabelWithLayout(_tx1170, size);
      expect(r.headline.right, lessThanOrEqualTo(_safeAreaOf(size).right),
          reason: size.displayName);
    }
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
      }, skip: !_compareGoldens);
    }

    // The other sizes: bailout, diluent and OC at each. The 50 x 30 OC
    // label is `tx2135_oc`; the rest are named `<layout>_<size>`.
    test('tx2135_oc', () async {
      await expectLater(
        await renderCylinderLabelImage(_tx2135Oc),
        matchesGoldenFile('goldens/tx2135_oc.png'),
      );
    }, skip: !_compareGoldens);
    final layouts = <String, CylinderLabel>{
      'bailout': _tx2135,
      'diluent': _tx2135Diluent,
      'oc': _tx2135Oc,
      'oc_130m': _tx1070Oc,
    };
    for (final g in layouts.entries) {
      test('${g.key}_50x80_rotated', () async {
        await expectLater(
          await renderCylinderLabelImage(g.value, LabelSize.mm50x80, true),
          matchesGoldenFile('goldens/${g.key}_50x80_rotated.png'),
        );
      }, skip: !_compareGoldens);
    }
    for (final size in LabelSize.values) {
      if (size == LabelSize.mm50x30) continue;
      for (final g in layouts.entries) {
        test('${g.key}_${size.key}', () async {
          await expectLater(
            await renderCylinderLabelImage(g.value, size),
            matchesGoldenFile('goldens/${g.key}_${size.key}.png'),
          );
        }, skip: !_compareGoldens);
      }
    }
  });
}

/// Font rasterization differs between macOS and the Ubuntu CI runners, so
/// the goldens are only compared on macOS (or when `ANCHORLINE_GOLDENS` is
/// set, to look at a render on another platform).
final bool _compareGoldens =
    Platform.isMacOS || Platform.environment.containsKey('ANCHORLINE_GOLDENS');
