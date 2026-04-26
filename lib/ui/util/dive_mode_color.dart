import 'package:flutter/material.dart';
import '../../shearwater/parser/constants.dart';

const _ccColor = Color(0xFF4FC3F7);
const _ocColor = Color(0xFFFF9800);
const _scColor = Color(0xFFAB47BC);
const _gaugeColor = Color(0xFF78909C);
const _freediveColor = Color(0xFF26A69A);

Color diveModeColor(int diveModeValue) {
  final mode = DiveMode.fromValue(diveModeValue);
  return switch (mode) {
    DiveMode.cc || DiveMode.cc2 => _ccColor,
    DiveMode.ocTec || DiveMode.ocRec || DiveMode.avelo => _ocColor,
    DiveMode.sc => _scColor,
    DiveMode.gauge || DiveMode.ppo2 => _gaugeColor,
    DiveMode.freedive => _freediveColor,
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
