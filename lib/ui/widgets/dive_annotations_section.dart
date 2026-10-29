import 'package:flutter/material.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/dive.dart';
import '../notifiers/dive_annotations_notifier.dart';
import '../notifiers/settings_notifier.dart';
import '../screens/map_picker_screen.dart';
import '../screens/sites_map_screen.dart';
import '../theme/safety_colors.dart';
import '../theme/tokens.dart';
import 'chip_input.dart';
import 'site_form_view.dart';
import 'site_map_view.dart';
import '../../analysis/gas_naming.dart';

class DiveAnnotationsSection extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;
  final List<DiveGasMix> gasMixes;
  final Map<int, int> activeSecondsByMix;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;

  /// When false, the gas-mix → cylinder mapping block is omitted from
  /// this section (Phase 3: that block lives on the Equipment tab via
  /// [DiveCylindersSection] instead). Default true so existing solo
  /// callers (cell_detail_screen, tests) render unchanged.
  final bool showGasMixes;
  final SettingsNotifier settingsNotifier;

  const DiveAnnotationsSection({
    super.key,
    required this.notifier,
    required this.gasMixes,
    required this.activeSecondsByMix,
    required this.annotationsDao,
    required this.equipmentDao,
    required this.settingsNotifier,
    this.showGasMixes = true,
  });

  @override
  State<DiveAnnotationsSection> createState() =>
      _DiveAnnotationsSectionState();
}

class _DiveAnnotationsSectionState extends State<DiveAnnotationsSection> {
  DiveAnnotationsNotifier get _n => widget.notifier;
  final _notes = TextEditingController();
  final _divemaster = TextEditingController();

  List<String> _buddyOptions = const [];
  List<String> _tagOptions = const [];
  List<Cylinder> _cylinders = const [];
  bool _controllersHydrated = false;

  @override
  void initState() {
    super.initState();
    _n.addListener(_onNotifierChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _buddyOptions = await widget.annotationsDao.distinctBuddies();
    _tagOptions = await widget.annotationsDao.distinctTags();
    _cylinders = await widget.equipmentDao.listCylinders();
    if (!mounted) return;
    _maybeHydrateControllers();
    setState(() {});
  }

  void _maybeHydrateControllers() {
    if (_controllersHydrated || !_n.loaded) return;
    _notes.text = _n.notes ?? '';
    _divemaster.text = _n.divemaster ?? '';
    _controllersHydrated = true;
  }

  void _onNotifierChanged() {
    _maybeHydrateControllers();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _n.removeListener(_onNotifierChanged);
    _notes.dispose();
    _divemaster.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap(BuildContext ctx) async {
    final result = await Navigator.of(ctx).push<({double lat, double lon})>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLat: _n.siteLatitude,
          initialLon: _n.siteLongitude,
        ),
      ),
    );
    if (result == null) return;
    _n.setLatLon(result.lat, result.lon);
  }

  @override
  Widget build(BuildContext context) {
    if (!_n.loaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Builder(builder: (context) {
            final lat = _n.siteLatitude;
            final lon = _n.siteLongitude;
            final hasCoords = lat != null && lon != null;
            if (!hasCoords) {
              return SiteFormView(
                notifier: _n,
                annotationsDao: widget.annotationsDao,
                onPickOnMap: () => _pickOnMap(context),
              );
            }
            return DefaultTabController(
              length: 2,
              initialIndex: 1, // default to Map
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const TabBar(
                    tabs: [
                      Tab(text: 'Form'),
                      Tab(text: 'Map'),
                    ],
                    isScrollable: false,
                  ),
                  SizedBox(
                    height: 280,
                    child: TabBarView(
                      children: [
                        SingleChildScrollView(
                          child: SiteFormView(
                            notifier: _n,
                            annotationsDao: widget.annotationsDao,
                            onPickOnMap: () => _pickOnMap(context),
                          ),
                        ),
                        SiteMapView(
                          lat: lat,
                          lon: lon,
                          siteName: _n.siteName,
                          settingsNotifier: widget.settingsNotifier,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SitesMapScreen(
                                dao: widget.annotationsDao,
                                currentLat: lat,
                                currentLon: lon,
                                settingsNotifier: widget.settingsNotifier,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 16),

          Text('Divemaster', style: Theme.of(context).textTheme.titleSmall),
          TextField(
            controller: _divemaster,
            decoration: const InputDecoration(hintText: 'Divemaster name'),
            onChanged: (v) =>
                _n.setDivemaster(v.trim().isEmpty ? null : v.trim()),
          ),
          const SizedBox(height: 16),

          Text('Buddies', style: Theme.of(context).textTheme.titleSmall),
          ChipInput(
            values: _n.buddies,
            autocompleteOptions: _buddyOptions,
            onChanged: _n.setBuddies,
            // Cool blue — identity / people taxonomy.
            accentColor: SafetyColors.info,
          ),

          const SizedBox(height: 16),

          Text('Tags', style: Theme.of(context).textTheme.titleSmall),
          ChipInput(
            values: _n.tags,
            autocompleteOptions: _tagOptions,
            onChanged: _n.setTags,
            // Warm sodium-vapor amber — active classification / labels.
            accentColor: context.palette.accentPrimary,
          ),

          const SizedBox(height: 16),

          Text('Notes', style: Theme.of(context).textTheme.titleSmall),
          TextField(
            controller: _notes,
            maxLines: 4,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            onChanged: (v) => _n.setNotes(v.trim().isEmpty ? null : v.trim()),
          ),

          const SizedBox(height: 16),

          if (widget.showGasMixes && widget.gasMixes.isNotEmpty) ...[
            Text('Gas mixes',
                style: Theme.of(context).textTheme.titleSmall),
            for (var i = 0; i < widget.gasMixes.length; i++)
              GasMixRow(
                index: i,
                mix: widget.gasMixes[i],
                activeSeconds: widget.activeSecondsByMix[i] ?? 0,
                cylinders: _cylinders,
                selectedCylinderId: _n.cylinderByMix[i],
                onChanged: (cylinderId) =>
                    _n.setCylinderForMix(i, cylinderId),
              ),
          ],
        ],
      ),
    );
  }
}

class GasMixRow extends StatelessWidget {
  final int index;
  final DiveGasMix mix;
  final int activeSeconds;
  final List<Cylinder> cylinders;
  final String? selectedCylinderId;
  final void Function(String? cylinderId) onChanged;

  const GasMixRow({
    super.key,
    required this.index,
    required this.mix,
    required this.activeSeconds,
    required this.cylinders,
    required this.selectedCylinderId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mixLabel = gasMixName(mix.oxygenPercent, mix.heliumPercent);
    final mins = activeSeconds ~/ 60;
    // Coerce a missing-cylinder id to null for display only — handles the
    // case where a cylinder mapped to this dive was later soft-deleted from
    // the cylinders list. Underlying mapping stays in the DB until re-saved.
    final knownIds = cylinders.map((c) => c.id).toSet();
    final displayValue =
        (selectedCylinderId != null && knownIds.contains(selectedCylinderId))
            ? selectedCylinderId
            : null;

    String labelFor(String? id) {
      if (id == null) return '—';
      final c = cylinders.firstWhere(
        (c) => c.id == id,
        orElse: () => cylinders.first,
      );
      return '${c.label} (${c.role})';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  mixLabel,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  'Mix ${index + 1} · ~${mins}m active',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          PopupMenuButton<String?>(
            initialValue: displayValue,
            tooltip: 'Pick cylinder',
            onSelected: onChanged,
            itemBuilder: (context) => [
              const PopupMenuItem<String?>(value: null, child: Text('—')),
              for (final c in cylinders)
                PopupMenuItem<String?>(
                  value: c.id,
                  child: Text('${c.label} (${c.role})'),
                ),
            ],
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labelFor(displayValue),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_drop_down,
                      size: 18,
                      color: Theme.of(context).colorScheme.primary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
