import 'package:flutter/material.dart';

import '../../shearwater/parser/constants.dart';
import '../util/dive_mode_color.dart';

class DiveFilterSelection {
  final int? mode;
  final Set<String> sites;
  final Set<String> buddies;
  final Set<String> tags;

  const DiveFilterSelection({
    this.mode,
    this.sites = const {},
    this.buddies = const {},
    this.tags = const {},
  });

  bool get isEmpty =>
      mode == null && sites.isEmpty && buddies.isEmpty && tags.isEmpty;

  DiveFilterSelection copyWith({
    int? mode,
    bool clearMode = false,
    Set<String>? sites,
    Set<String>? buddies,
    Set<String>? tags,
  }) =>
      DiveFilterSelection(
        mode: clearMode ? null : (mode ?? this.mode),
        sites: sites ?? this.sites,
        buddies: buddies ?? this.buddies,
        tags: tags ?? this.tags,
      );
}

/// Available facet values (gathered from the loaded list).
class DiveFilterFacets {
  final List<int> modes;
  final List<String> sites;
  final List<String> buddies;
  final List<String> tags;

  const DiveFilterFacets({
    this.modes = const [],
    this.sites = const [],
    this.buddies = const [],
    this.tags = const [],
  });
}

Future<DiveFilterSelection?> showDiveFilterSheet(
  BuildContext context, {
  required DiveFilterSelection initial,
  required DiveFilterFacets facets,
}) {
  return showModalBottomSheet<DiveFilterSelection>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _DiveFilterSheet(initial: initial, facets: facets),
  );
}

class _DiveFilterSheet extends StatefulWidget {
  final DiveFilterSelection initial;
  final DiveFilterFacets facets;
  const _DiveFilterSheet({required this.initial, required this.facets});

  @override
  State<_DiveFilterSheet> createState() => _DiveFilterSheetState();
}

class _DiveFilterSheetState extends State<_DiveFilterSheet> {
  late int? _mode = widget.initial.mode;
  late Set<String> _sites = {...widget.initial.sites};
  late Set<String> _buddies = {...widget.initial.buddies};
  late Set<String> _tags = {...widget.initial.tags};

  void _toggleSite(String v) {
    setState(() {
      if (_sites.contains(v)) {
        _sites.remove(v);
      } else {
        _sites.add(v);
      }
    });
  }

  void _toggleBuddy(String v) {
    setState(() {
      if (_buddies.contains(v)) {
        _buddies.remove(v);
      } else {
        _buddies.add(v);
      }
    });
  }

  void _toggleTag(String v) {
    setState(() {
      if (_tags.contains(v)) {
        _tags.remove(v);
      } else {
        _tags.add(v);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).dividerColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                _section('Dive mode', _modeChips()),
                _section('Site', _multiChips(widget.facets.sites, _sites, _toggleSite)),
                _section('Buddy',
                    _multiChips(widget.facets.buddies, _buddies, _toggleBuddy)),
                _section('Tag', _multiChips(widget.facets.tags, _tags, _toggleTag)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _mode = null;
                          _sites = {};
                          _buddies = {};
                          _tags = {};
                        });
                      },
                      child: const Text('Clear all'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        Navigator.of(context).pop(DiveFilterSelection(
                          mode: _mode,
                          sites: _sites,
                          buddies: _buddies,
                          tags: _tags,
                        ));
                      },
                      child: const Text('Apply'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(String title, Widget body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(title,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
          ),
          body,
        ],
      ),
    );
  }

  Widget _modeChips() {
    final modes = widget.facets.modes;
    return Wrap(
      spacing: 6, runSpacing: 6,
      children: [
        ChoiceChip(
          label: const Text('Any'),
          selected: _mode == null,
          onSelected: (_) => setState(() => _mode = null),
        ),
        for (final m in modes)
          ChoiceChip(
            label: Text(diveModeLabel(m)),
            selected: _mode == m,
            onSelected: (sel) => setState(() => _mode = sel ? m : null),
          ),
      ],
    );
  }

  Widget _multiChips(
      List<String> values, Set<String> selected, void Function(String) toggle) {
    if (values.isEmpty) {
      return Text('—',
          style: TextStyle(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.4)));
    }
    return Wrap(
      spacing: 6, runSpacing: 6,
      children: [
        for (final v in values)
          FilterChip(
            label: Text(v),
            selected: selected.contains(v),
            onSelected: (_) => toggle(v),
          ),
      ],
    );
  }
}

/// All distinct dive modes present in the loaded list, in DiveMode order.
List<int> distinctModesIn(Iterable<int> modeValues) {
  final present = modeValues.toSet();
  final ordered = <int>[];
  for (final m in DiveMode.values) {
    if (present.contains(m.value)) ordered.add(m.value);
  }
  return ordered;
}
