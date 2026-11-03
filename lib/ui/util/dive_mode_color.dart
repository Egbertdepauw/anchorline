import 'package:flutter/material.dart';
import 'package:subsurface_core/shearwater/parser/constants.dart';
import '../theme/data_colors.dart';

Color diveModeColor(int diveModeValue) {
  final mode = DiveMode.fromValue(diveModeValue);
  return switch (mode) {
    DiveMode.cc || DiveMode.cc2 => DataColors.modeClosedCircuit,
    DiveMode.ocTec || DiveMode.ocRec || DiveMode.avelo =>
      DataColors.modeOpenCircuit,
    DiveMode.sc => DataColors.modeSemiClosed,
    DiveMode.gauge || DiveMode.ppo2 => DataColors.modeGauge,
    DiveMode.freedive => DataColors.modeFreedive,
  };
}

String diveModeLabel(int diveModeValue) {
  final mode = DiveMode.fromValue(diveModeValue);
  return switch (mode) {
    DiveMode.cc || DiveMode.cc2 => 'CC',
    DiveMode.ocTec || DiveMode.ocRec || DiveMode.avelo => 'OC',
    DiveMode.sc => 'SC',
    DiveMode.gauge || DiveMode.ppo2 => 'GA',
    DiveMode.freedive => 'FD',
  };
}
