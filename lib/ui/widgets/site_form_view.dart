import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../notifiers/dive_annotations_notifier.dart';

class SiteFormView extends StatefulWidget {
  final DiveAnnotationsNotifier notifier;
  final DiveAnnotationsDao annotationsDao;

  /// Called when the user taps "Pick on map". The navigation is handled by
  /// the parent so this widget has no dependency on the map-picker screen.
  final Future<void> Function()? onPickOnMap;

  const SiteFormView({
    super.key,
    required this.notifier,
    required this.annotationsDao,
    this.onPickOnMap,
  });

  @override
  State<SiteFormView> createState() => _SiteFormViewState();
}

class _SiteFormViewState extends State<SiteFormView> {
  DiveAnnotationsNotifier get _n => widget.notifier;

  final _site = TextEditingController();
  final _siteFocus = FocusNode();
  final _lat = TextEditingController();
  final _lon = TextEditingController();

  List<String> _siteOptions = const [];
  bool _controllersHydrated = false;

  @override
  void initState() {
    super.initState();
    _n.addListener(_onNotifierChanged);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    _siteOptions = await widget.annotationsDao.distinctSiteNames();
    if (!mounted) return;
    _maybeHydrateControllers();
    setState(() {});
  }

  void _maybeHydrateControllers() {
    if (_controllersHydrated || !_n.loaded) return;
    _site.text = _n.siteName ?? '';
    _lat.text = _n.siteLatitude?.toString() ?? '';
    _lon.text = _n.siteLongitude?.toString() ?? '';
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
    super.dispose();
  }

  /// Parses a user-typed decimal, accepting `,` as the decimal separator
  /// (Dutch / German / French locales) in addition to `.`. Empty input
  /// returns null. `double.tryParse` only accepts `.`, which silently
  /// drops decimals on iPhone keypads in comma-locale regions.
  double? _parseDecimal(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    return double.tryParse(t.replaceAll(',', '.'));
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Site', style: Theme.of(context).textTheme.titleSmall),
        RawAutocomplete<String>(
          textEditingController: _site,
          focusNode: _siteFocus,
          optionsBuilder: (tev) {
            // Empty text on focus → show every known site so the field
            // doubles as a discovery dropdown, not just a filter.
            if (tev.text.isEmpty) return _siteOptions;
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
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _lat,
              keyboardType: const TextInputType.numberWithOptions(
                  decimal: true, signed: true),
              decoration: const InputDecoration(labelText: 'Latitude'),
              onChanged: (_) => _n.setLatLon(
                  _parseDecimal(_lat.text), _parseDecimal(_lon.text)),
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
                  _parseDecimal(_lat.text), _parseDecimal(_lon.text)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            TextButton.icon(
              icon: const Icon(Icons.my_location, size: 18),
              label: const Text('Use current location'),
              onPressed: _useCurrentLocation,
            ),
            TextButton.icon(
              icon: const Icon(Icons.map, size: 18),
              label: const Text('Pick on map'),
              onPressed: widget.onPickOnMap,
            ),
          ],
        ),
      ],
    );
  }
}
