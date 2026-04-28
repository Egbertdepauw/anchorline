import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/db/database.dart';
import '../../data/db/dive_annotations_dao.dart';
import '../../data/db/equipment_dao.dart';
import '../../data/models/dive.dart';
import '../notifiers/dive_annotations_notifier.dart';
import '../screens/map_picker_screen.dart';
import 'chip_input.dart';

class DiveAnnotationsSection extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;
  final List<DiveGasMix> gasMixes;
  final Map<int, int> activeSecondsByMix;
  final DiveAnnotationsDao annotationsDao;
  final EquipmentDao equipmentDao;

  const DiveAnnotationsSection({
    super.key,
    required this.notifier,
    required this.gasMixes,
    required this.activeSecondsByMix,
    required this.annotationsDao,
    required this.equipmentDao,
  });

  @override
  State<DiveAnnotationsSection> createState() =>
      _DiveAnnotationsSectionState();
}

class _DiveAnnotationsSectionState extends State<DiveAnnotationsSection> {
  DiveAnnotationsNotifier get _n => widget.notifier;
  final _site = TextEditingController();
  final _siteFocus = FocusNode();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  final _notes = TextEditingController();
  final _conditions = TextEditingController();

  List<String> _siteOptions = const [];
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
    _siteOptions = await widget.annotationsDao.distinctSiteNames();
    _buddyOptions = await widget.annotationsDao.distinctBuddies();
    _tagOptions = await widget.annotationsDao.distinctTags();
    _cylinders = await widget.equipmentDao.listCylinders();
    if (!mounted) return;
    _maybeHydrateControllers();
    setState(() {});
  }

  void _maybeHydrateControllers() {
    if (_controllersHydrated || !_n.loaded) return;
    _site.text = _n.siteName ?? '';
    _lat.text = _n.siteLatitude?.toString() ?? '';
    _lon.text = _n.siteLongitude?.toString() ?? '';
    _notes.text = _n.notes ?? '';
    _conditions.text = _n.conditions ?? '';
    _controllersHydrated = true;
  }

  void _onNotifierChanged() {
    _maybeHydrateControllers();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _n.removeListener(_onNotifierChanged);
    _site.dispose();
    _siteFocus.dispose();
    _lat.dispose();
    _lon.dispose();
    _notes.dispose();
    _conditions.dispose();
    super.dispose();
  }

  Future<void> _pickOnMap() async {
    final result = await Navigator.of(context).push<({double lat, double lon})>(
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialLat: double.tryParse(_lat.text.trim()),
          initialLon: double.tryParse(_lon.text.trim()),
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _lat.text = result.lat.toStringAsFixed(6);
      _lon.text = result.lon.toStringAsFixed(6);
    });
    _n.setLatLon(result.lat, result.lon);
  }

  Future<void> _useCurrentLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        final req = await Geolocator.requestPermission();
        if (req != LocationPermission.always &&
            req != LocationPermission.whileInUse) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Location permission denied'),
          ));
          return;
        }
      }
      final pos = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _lat.text = pos.latitude.toStringAsFixed(6);
        _lon.text = pos.longitude.toStringAsFixed(6);
      });
      _n.setLatLon(pos.latitude, pos.longitude);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not get current location: $e'),
      ));
    }
  }

  Future<void> _save() async {
    _n.setSiteName(_site.text.trim().isEmpty ? null : _site.text.trim());
    _n.setLatLon(
      double.tryParse(_lat.text.trim()),
      double.tryParse(_lon.text.trim()),
    );
    _n.setNotes(_notes.text.trim().isEmpty ? null : _notes.text.trim());
    _n.setConditions(
        _conditions.text.trim().isEmpty ? null : _conditions.text.trim());
    await _n.save();
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
          Text('Site', style: Theme.of(context).textTheme.titleSmall),
          RawAutocomplete<String>(
            textEditingController: _site,
            focusNode: _siteFocus,
            optionsBuilder: (tev) {
              if (tev.text.isEmpty) return const Iterable<String>.empty();
              return _siteOptions.where(
                  (o) => o.toLowerCase().contains(tev.text.toLowerCase()));
            },
            onSelected: (v) async {
              _site.text = v;
              _n.setSiteName(v);
              // Auto-fill lat/lon from the latest annotation with this site,
              // but don't overwrite user-typed coords.
              if (_lat.text.trim().isEmpty && _lon.text.trim().isEmpty) {
                final coords =
                    await widget.annotationsDao.getLatestSiteCoords(v);
                if (coords != null && mounted) {
                  setState(() {
                    _lat.text = coords.lat?.toStringAsFixed(6) ?? '';
                    _lon.text = coords.lon?.toStringAsFixed(6) ?? '';
                  });
                  _n.setLatLon(coords.lat, coords.lon);
                }
              }
            },
            fieldViewBuilder: (context, controller, focusNode, _) {
              return TextField(
                controller: controller, // === _site
                focusNode: focusNode, // === _siteFocus
                decoration: const InputDecoration(hintText: 'Site name'),
                onChanged: (v) =>
                    _n.setSiteName(v.trim().isEmpty ? null : v.trim()),
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                        maxHeight: 200, maxWidth: 320),
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
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _lat,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Latitude'),
                onChanged: (_) => _n.setLatLon(
                    double.tryParse(_lat.text.trim()),
                    double.tryParse(_lon.text.trim())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lon,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'Longitude'),
                onChanged: (_) => _n.setLatLon(
                    double.tryParse(_lat.text.trim()),
                    double.tryParse(_lon.text.trim())),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            TextButton.icon(
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use current location'),
              onPressed: _useCurrentLocation,
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              icon: const Icon(Icons.map, size: 18),
              label: const Text('Pick on map'),
              onPressed: _pickOnMap,
            ),
          ]),

          const SizedBox(height: 16),

          Text('Buddies', style: Theme.of(context).textTheme.titleSmall),
          ChipInput(
            initialValues: _n.buddies,
            autocompleteOptions: _buddyOptions,
            onChanged: _n.setBuddies,
          ),

          const SizedBox(height: 16),

          Text('Tags', style: Theme.of(context).textTheme.titleSmall),
          ChipInput(
            initialValues: _n.tags,
            autocompleteOptions: _tagOptions,
            onChanged: _n.setTags,
          ),

          const SizedBox(height: 16),

          Text('Conditions', style: Theme.of(context).textTheme.titleSmall),
          TextField(
            controller: _conditions,
            decoration: const InputDecoration(
              hintText: 'e.g. 8m viz, no current',
            ),
            onChanged: (v) =>
                _n.setConditions(v.trim().isEmpty ? null : v.trim()),
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

          if (widget.gasMixes.isNotEmpty) ...[
            Text('Gas mixes',
                style: Theme.of(context).textTheme.titleSmall),
            for (var i = 0; i < widget.gasMixes.length; i++)
              _GasMixRow(
                index: i,
                mix: widget.gasMixes[i],
                activeSeconds: widget.activeSecondsByMix[i] ?? 0,
                cylinders: _cylinders,
                selectedCylinderId: _n.cylinderByMix[i],
                onChanged: (cylinderId) =>
                    _n.setCylinderForMix(i, cylinderId),
              ),
            const SizedBox(height: 16),
          ],

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _n.dirty ? _save : null,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}

class _GasMixRow extends StatelessWidget {
  final int index;
  final DiveGasMix mix;
  final int activeSeconds;
  final List<Cylinder> cylinders;
  final String? selectedCylinderId;
  final void Function(String? cylinderId) onChanged;

  const _GasMixRow({
    required this.index,
    required this.mix,
    required this.activeSeconds,
    required this.cylinders,
    required this.selectedCylinderId,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final mixLabel = '${mix.oxygenPercent}/${mix.heliumPercent}';
    final mins = activeSeconds ~/ 60;
    // Coerce a missing-cylinder id to null for display only — handles the
    // case where a cylinder mapped to this dive was later soft-deleted from
    // the cylinders list. Underlying mapping stays in the DB until re-saved.
    final knownIds = cylinders.map((c) => c.id).toSet();
    final displayValue =
        (selectedCylinderId != null && knownIds.contains(selectedCylinderId))
            ? selectedCylinderId
            : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(
          child: Text('Mix ${index + 1} · $mixLabel · ~${mins}m active'),
        ),
        DropdownButton<String?>(
          value: displayValue,
          hint: const Text('—'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('—')),
            for (final c in cylinders)
              DropdownMenuItem<String?>(
                value: c.id,
                child: Text('${c.label} (${c.role})'),
              ),
          ],
          onChanged: onChanged,
        ),
      ]),
    );
  }
}
