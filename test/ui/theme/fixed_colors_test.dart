import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/color_math.dart';
import 'package:ccrlogger/ui/theme/data_colors.dart';
import 'package:ccrlogger/ui/theme/media_colors.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Data colours known to fall short of 3:1 on a theme's card.
/// Keys are `themeId/name`. Each is an existing colour whose value
/// stage 2 must not change; the entry records the shortfall so no new
/// one can slip in. Filled in from the first run of this test (Step 4).
const _knownCardShortfalls = <String>{
  'retro82/gf99', // 2.89
  'catppuccin/gf99', // 2.34
  'miasma/gf99', // 2.60
};

void main() {
  test('data colours keep their established values', () {
    expect(DataColors.modeClosedCircuit, const Color(0xFF4FC3F7));
    expect(DataColors.modeOpenCircuit, const Color(0xFFFF9800));
    expect(DataColors.modeSemiClosed, const Color(0xFFAB47BC));
    expect(DataColors.modeGauge, const Color(0xFF78909C));
    expect(DataColors.modeFreedive, const Color(0xFF26A69A));
    expect(DataColors.waterTemp, const Color(0xFF4DD0E1));
    expect(DataColors.gf99, const Color(0xFF9333EA));
    expect(DataColors.ceiling, const Color(0xFFEAB308));
    expect(DataColors.speedCalm, const Color(0xFFE0E8EC));
    expect(DataColors.speedSlow, const Color(0xFFA8D957));
    expect(DataColors.speedModerate, const Color(0xFFE5C73F));
    expect(DataColors.speedFast, const Color(0xFFEC8A3D));
    expect(DataColors.speedExtreme, const Color(0xFFE65656));
    expect(DataColors.tanks, const [
      Color(0xFF80DEEA),
      Color(0xFFFFAB91),
      Color(0xFFCE93D8),
      Color(0xFFB0BEC5),
      Color(0xFFA5D6A7),
      Color(0xFFFFE082),
    ]);
    expect(DataColors.tissueRamp, const [
      (0.0, Color(0xFF1E3A8A)),
      (40.0, Color(0xFF3B82F6)),
      (70.0, Color(0xFF06B6D4)),
      (85.0, Color(0xFF22C55E)),
      (95.0, Color(0xFFFACC15)),
      (100.0, Color(0xFFF97316)),
      (115.0, Color(0xFFDC2626)),
    ]);
    expect(DataColors.mapPin, const Color(0xFFF44336));
    expect(DataColors.mapPinMuted, const Color(0xFF8B3A3A));
  });

  test('line colours for tanks are the tank palette', () {
    expect(DataColors.tanks.length, 6);
    for (var i = 0; i < 6; i++) {
      expect(DataColors.lineColors['tank$i'], DataColors.tanks[i],
          reason: 'tank$i');
    }
  });

  test('safety additions', () {
    expect(SafetyColors.bandSafe, SafetyColors.gfWithinLimits);
    expect(SafetyColors.bandCaution, SafetyColors.gfOverHigh);
    expect(SafetyColors.bandOver, SafetyColors.gfOverLimit);
    expect(SafetyColors.alertCriticalSurface, const Color(0xFFB71C1C));
    expect(SafetyColors.alertWarningSurface, const Color(0xFFE65100));
    expect(SafetyColors.onAlert, const Color(0xFFFFFFFF));
  });

  test('on-alert text is readable on every alert surface', () {
    for (final surface in [
      SafetyColors.alertCriticalSurface,
      SafetyColors.alertWarningSurface,
      SafetyColors.danger,
    ]) {
      expect(contrastRatio(SafetyColors.onAlert, surface),
          greaterThanOrEqualTo(3.0),
          reason: '$surface');
    }
  });

  test('media colours', () {
    expect(MediaColors.viewerBackground, const Color(0xFF000000));
    expect(MediaColors.viewerForeground, const Color(0xFFFFFFFF));
    expect(MediaColors.onScrim, const Color(0xFFFFFFFF));
    expect(MediaColors.scrim(0.35), const Color(0xFF000000).withValues(alpha: 0.35));
  });

  test('line-drawing data colours are readable on every theme card', () {
    final offenders = <String>[];
    for (final t in AppThemes.all) {
      DataColors.lineColors.forEach((name, color) {
        final ratio = contrastRatio(color, t.palette.surfaceCard);
        final key = '${t.id}/$name';
        if (_knownCardShortfalls.contains(key)) {
          expect(ratio, lessThan(3.0),
              reason: '$key no longer falls short: remove it from '
                  '_knownCardShortfalls');
        } else if (ratio < 3.0) {
          offenders.add('$key ${ratio.toStringAsFixed(2)}');
        }
      });
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('accent is readable as a label in every theme', () {
    for (final t in AppThemes.all) {
      for (final bg in [t.palette.surfaceBg, t.palette.surfaceCard]) {
        expect(contrastRatio(t.palette.accentPrimary, bg),
            greaterThanOrEqualTo(3.0),
            reason: '${t.id} accent');
      }
    }
  });
}
