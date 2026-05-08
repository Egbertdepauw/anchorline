/// Phase-3 Equipment-tab freeform fields: suit, undersuit, weight
/// system, DPV, camera. Each field is a single-string autocomplete
/// backed by [DiveAnnotationsDao.distinctEquipmentValues] for
/// suggestions sourced from prior dives the same user logged.
///
/// Cylinders live in a sibling [DiveCylindersSection]; this widget is
/// purely the freeform-text block. Both share the same
/// [DiveAnnotationsNotifier], so editing here marks the annotation
/// dirty and the parent screen's AppBar Save button picks it up.
library;

import 'package:flutter/material.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../notifiers/dive_annotations_notifier.dart';
import 'weights_editor.dart';

class DiveEquipmentSection extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;
  final DiveAnnotationsDao annotationsDao;

  const DiveEquipmentSection({
    super.key,
    required this.notifier,
    required this.annotationsDao,
  });

  @override
  State<DiveEquipmentSection> createState() => _DiveEquipmentSectionState();
}

/// One row's worth of state — keeps the five fields uniform without
/// having to repeat five copies of controller + focus + options + setter
/// boilerplate in build().
class _Field {
  final String label;
  final String hint;
  final String column; // whitelisted DAO column name
  final void Function(String?) setter;
  final String? Function() getter;
  final TextEditingController controller = TextEditingController();
  final FocusNode focusNode = FocusNode();
  List<String> options = const [];

  _Field({
    required this.label,
    required this.hint,
    required this.column,
    required this.setter,
    required this.getter,
  });

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}

class _DiveEquipmentSectionState extends State<DiveEquipmentSection> {
  DiveAnnotationsNotifier get _n => widget.notifier;
  late final List<_Field> _fields;
  bool _hydrated = false;

  @override
  void initState() {
    super.initState();
    _fields = [
      _Field(
        label: 'Suit',
        hint: 'e.g. Santi BZ400, Mares Rover 7mm',
        column: 'suit',
        setter: _n.setSuit,
        getter: () => _n.suit,
      ),
      _Field(
        label: 'Undersuit',
        hint: 'e.g. Halo 250, Fourth Element Halo 3D',
        column: 'undersuit',
        setter: _n.setUndersuit,
        getter: () => _n.undersuit,
      ),
      _Field(
        label: 'DPV',
        hint: 'e.g. Suex XK1, Bonex RS',
        column: 'dpv',
        setter: _n.setDpv,
        getter: () => _n.dpv,
      ),
      _Field(
        label: 'Camera',
        hint: 'e.g. GoPro Hero 12, Insta360 X4',
        column: 'camera',
        setter: _n.setCamera,
        getter: () => _n.camera,
      ),
    ];
    _n.addListener(_onNotifierChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final results = await Future.wait(
      _fields.map((f) => widget.annotationsDao.distinctEquipmentValues(f.column)),
    );
    if (!mounted) return;
    for (var i = 0; i < _fields.length; i++) {
      _fields[i].options = results[i];
    }
    _maybeHydrate();
    setState(() {});
  }

  void _maybeHydrate() {
    if (_hydrated || !_n.loaded) return;
    for (final f in _fields) {
      f.controller.text = f.getter() ?? '';
    }
    _hydrated = true;
  }

  void _onNotifierChanged() {
    _maybeHydrate();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _n.removeListener(_onNotifierChanged);
    for (final f in _fields) {
      f.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'EQUIPMENT',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  letterSpacing: 1.2,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7),
                ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _fields.length; i++) ...[
            if (i > 0) const SizedBox(height: 16),
            _buildField(_fields[i]),
          ],
          const SizedBox(height: 24),
          WeightsEditor(
            weights: _n.weights,
            onChanged: _n.setWeights,
          ),
        ],
      ),
    );
  }

  Widget _buildField(_Field f) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(f.label, style: Theme.of(context).textTheme.titleSmall),
        RawAutocomplete<String>(
          textEditingController: f.controller,
          focusNode: f.focusNode,
          optionsBuilder: (tev) {
            // Empty input on focus → list every known value so the field
            // doubles as a discovery dropdown, mirroring the site-name
            // autocomplete in DiveAnnotationsSection.
            if (tev.text.isEmpty) return f.options;
            final q = tev.text.toLowerCase();
            return f.options.where((o) => o.toLowerCase().contains(q));
          },
          onSelected: (v) {
            f.controller.text = v;
            f.setter(v.trim().isEmpty ? null : v);
          },
          fieldViewBuilder: (context, controller, focusNode, _) {
            return TextField(
              controller: controller, // === f.controller
              focusNode: focusNode, // === f.focusNode
              decoration: InputDecoration(hintText: f.hint),
              onChanged: (v) =>
                  f.setter(v.trim().isEmpty ? null : v.trim()),
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxHeight: 200, maxWidth: 320),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: options.length,
                    itemBuilder: (context, index) {
                      final option = options.elementAt(index);
                      return InkWell(
                        onTap: () => onSelected(option),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Text(option),
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
