import 'package:ccrlogger/ui/theme/app_themes.dart';
import 'package:ccrlogger/ui/theme/safety_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the error colour and what sits on it are the same in every theme', () {
    for (final t in AppThemes.all) {
      final scheme = t.themeData.colorScheme;
      expect(scheme.error, SafetyColors.danger, reason: t.id);
      expect(scheme.onError, SafetyColors.onAlert, reason: t.id);
    }
  });

  test('snackbar actions use the theme accent', () {
    for (final t in AppThemes.all) {
      expect(t.themeData.snackBarTheme.actionTextColor,
          t.palette.accentPrimary,
          reason: t.id);
    }
  });
}
