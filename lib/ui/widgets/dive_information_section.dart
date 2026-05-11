import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/db/database.dart';
import '../components/data_row.dart' as components;
import '../components/section_header.dart';
import '../notifiers/dive_annotations_notifier.dart';
import 'star_rating.dart';

/// "Information" tab body — structured conditions + environment, mirroring
/// the Subsurface Dive ▸ Information panel. Weights live on the Equipment
/// tab so this stays focused on conditions/temps.
class DiveInformationSection extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;

  /// The dive — used to surface read-only environment fields the
  /// Shearwater binary already gave us (water density, atmospheric
  /// pressure).
  final Dive dive;

  /// Sample-derived water-temp fallback shown as the field's hint when
  /// the annotation has no explicit value yet. Typically the average of
  /// the dive computer's per-sample temperature stream.
  final double? defaultWaterTempC;

  const DiveInformationSection({
    super.key,
    required this.notifier,
    required this.dive,
    this.defaultWaterTempC,
  });

  @override
  State<DiveInformationSection> createState() =>
      _DiveInformationSectionState();
}

class _DiveInformationSectionState extends State<DiveInformationSection> {
  DiveAnnotationsNotifier get _n => widget.notifier;

  final _airTemp = TextEditingController();
  final _waterTemp = TextEditingController();
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _n.addListener(_onChanged);
    _maybeHydrate();
  }

  void _onChanged() {
    _maybeHydrate();
    if (mounted) setState(() {});
  }

  void _maybeHydrate() {
    if (_hydrated || !_n.loaded) return;
    _airTemp.text = _formatTemp(_n.airTempC);
    _waterTemp.text = _formatTemp(_n.waterTempC);
    _hydrated = true;
  }

  static String _formatTemp(double? v) {
    if (v == null) return '';
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(1);
  }

  /// Parse a user-typed temperature, accepting either `.` or `,` as
  /// the decimal separator. Empty/invalid input → null.
  static double? _parseTemp(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed.replaceAll(',', '.'));
  }

  @override
  void dispose() {
    _n.removeListener(_onChanged);
    _airTemp.dispose();
    _waterTemp.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_n.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    final waterHint = widget.defaultWaterTempC == null
        ? null
        : '${_formatTemp(widget.defaultWaterTempC)} (avg)';
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader('Conditions'),
          _ratingRow('Visibility', _n.visibility, _n.setVisibility,
              subtitleLeft: 'Bad', subtitleRight: 'Good'),
          _ratingRow('Surface waves', _n.wavesize, _n.setWavesize,
              subtitleLeft: 'Large', subtitleRight: 'Small'),
          _ratingRow('Current', _n.current, _n.setCurrent,
              subtitleLeft: 'Strong', subtitleRight: 'Weak'),
          _ratingRow('Surge', _n.surge, _n.setSurge,
              subtitleLeft: 'Strong', subtitleRight: 'Weak'),
          _ratingRow('Chill', _n.chill, _n.setChill,
              subtitleLeft: 'Freezing', subtitleRight: 'Comfy'),
          const SizedBox(height: 16),
          SectionHeader('Environment'),
          Row(children: [
            Expanded(
              child: _tempField(
                label: 'Air temp (°C)',
                controller: _airTemp,
                onChanged: (raw) => _n.setAirTempC(_parseTemp(raw)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _tempField(
                label: 'Water temp (°C)',
                controller: _waterTemp,
                hintText: waterHint,
                onChanged: (raw) => _n.setWaterTempC(_parseTemp(raw)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          components.DataRow(
            label: 'Water type',
            value: '${_waterTypeLabel(widget.dive.waterDensity)}'
                ' — ${(widget.dive.waterDensity / 1000).toStringAsFixed(3)} g/L',
          ),
          components.DataRow(
            label: 'Atm. pressure',
            value: '${widget.dive.atmosphericPressureMbar} mbar',
          ),
        ],
      ),
    );
  }

  static String _waterTypeLabel(int densityKgM3) {
    if (densityKgM3 < 1010) return 'Fresh';
    if (densityKgM3 >= 1020) return 'Salt';
    return 'Brackish';
  }

  Widget _ratingRow(
    String label,
    int? value,
    void Function(int?) onChanged, {
    required String subtitleLeft,
    required String subtitleRight,
  }) {
    // StarRating renders 5 IconButtons with VisualDensity.compact. Each
    // occupies ~44 px, so the star block is ~220 px wide. The caption
    // row matches that width so the polarity labels align under the
    // first and last star.
    const starBlockWidth = 220.0;
    const captionStyle = TextStyle(fontSize: 11, color: Color(0xFF78909C));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox(
              width: 130,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 13, color: Color(0xFFB0BEC5))),
            ),
            StarRating(value: value, onChanged: onChanged),
          ]),
          Padding(
            padding: const EdgeInsets.only(left: 130, top: 1, bottom: 2),
            child: SizedBox(
              width: starBlockWidth,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(subtitleLeft, style: captionStyle),
                  Text(subtitleRight, style: captionStyle),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tempField({
    required String label,
    required TextEditingController controller,
    required void Function(String) onChanged,
    String? hintText,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
          decimal: true, signed: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d.,\-]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
      onChanged: onChanged,
    );
  }
}
