import 'package:flutter/material.dart';

import '../../theme/tokens.dart';

/// A compact text field for the right-hand side of a settings row: a fixed
/// width, a mono value and an optional unit suffix. The value is read from
/// [initialValue] once; edits go out through [onChanged].
class SettingTextField extends StatelessWidget {
  const SettingTextField({
    super.key,
    required this.initialValue,
    required this.onChanged,
    this.suffix,
    this.width = 96,
    this.keyboardType,
    this.textAlign = TextAlign.end,
  });

  final String initialValue;
  final ValueChanged<String> onChanged;
  final String? suffix;
  final double width;
  final TextInputType? keyboardType;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final border = OutlineInputBorder(
      borderRadius: Radii.chipBr,
      borderSide: BorderSide(color: palette.surfaceBezel),
    );
    return SizedBox(
      width: width,
      child: TextFormField(
        initialValue: initialValue,
        keyboardType: keyboardType,
        textAlign: textAlign,
        style: AppTypography.readoutSm.copyWith(color: palette.textPrimary),
        onChanged: onChanged,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: palette.surfaceCard,
          suffixText: suffix,
          suffixStyle: AppTypography.caption.copyWith(
              color: palette.textMuted, fontSize: 12),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: Spacing.sm, vertical: Spacing.md),
          border: border,
          enabledBorder: border,
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: palette.accentPrimary),
          ),
        ),
      ),
    );
  }
}

const decimalKeyboard = TextInputType.numberWithOptions(decimal: true);
