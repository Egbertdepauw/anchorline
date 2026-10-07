import 'package:flutter/material.dart';

/// 8 px coloured circle. Used for cell status, sync state, dive type.
/// The colour is supplied by the caller — typically one of
/// SafetyColors.success / warning / danger /
/// info or a cell colour.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.color, this.size = 8});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
