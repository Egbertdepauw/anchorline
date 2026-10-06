import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('safety colours keep their established values', () {
    expect(SafetyColors.success, const Color(0xFF4ADE80));
    expect(SafetyColors.warning, const Color(0xFFF39C12));
    expect(SafetyColors.danger, const Color(0xFFE74C3C));
    expect(SafetyColors.info, const Color(0xFF60A5FA));
    expect(SafetyColors.gfWithinLimits, const Color(0xFF4ADE80));
    expect(SafetyColors.gfOverHigh, const Color(0xFFF59E0B));
    expect(SafetyColors.gfOverLimit, const Color(0xFFDC2626));
  });

  test('all lists every safety colour by name', () {
    expect(SafetyColors.all.keys, [
      'success',
      'warning',
      'danger',
      'info',
      'gfWithinLimits',
      'gfOverHigh',
      'gfOverLimit',
    ]);
    expect(SafetyColors.all['danger'], SafetyColors.danger);
  });
}
