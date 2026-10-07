import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import '../widgets/map_layer_toggle.dart';
import '../widgets/map_tile_sources.dart';
import '../widgets/sites_list_view.dart';

class SitesMapScreen extends StatefulWidget {
  final DiveAnnotationsDao dao;
  final double? currentLat;
  final double? currentLon;
  final SettingsNotifier settingsNotifier;

  const SitesMapScreen({
    super.key,
    required this.dao,
    required this.currentLat,
    required this.currentLon,
    required this.settingsNotifier,
  });

  @override
  State<SitesMapScreen> createState() => _SitesMapScreenState();
}

class _SitesMapScreenState extends State<SitesMapScreen> {
  static final _dateFmt = DateFormat('yyyy-MM-dd');

  List<({String? siteName, double lat, double lon})>? _sites;
  List<SiteStat>? _stats;

  /// false = map view (default), true = editable list view.
  bool _showList = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sites = await widget.dao.distinctSiteCoords();
    final stats = await widget.dao.siteStats();
    if (!mounted) return;
    setState(() {
      _sites = sites;
      _stats = stats;
    });
  }

  String _formatDate(int unixSeconds) => _dateFmt
      .format(DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000));

  bool _isCurrent(double lat, double lon) {
    final cLat = widget.currentLat;
    final cLon = widget.currentLon;
    if (cLat == null || cLon == null) return false;
    return lat.toStringAsFixed(5) == cLat.toStringAsFixed(5) &&
        lon.toStringAsFixed(5) == cLon.toStringAsFixed(5);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dive sites'),
        actions: [
          IconButton(
            icon: Icon(_showList ? Icons.map_outlined : Icons.view_list),
            tooltip: _showList ? 'Map view' : 'List view',
            onPressed: () => setState(() => _showList = !_showList),
          ),
        ],
      ),
      body: _showList
          ? SitesListView(dao: widget.dao)
          : ListenableBuilder(
              listenable: widget.settingsNotifier,
              builder: (context, _) {
                if (_sites == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final style = widget.settingsNotifier.mapLayerStyle;
                return Stack(
                  children: [
                    _buildMap(_sites!, style),
                    Positioned(
                      top: Spacing.sm,
                      right: Spacing.sm,
                      child: MapLayerToggle(
                        current: style,
                        onChanged: widget.settingsNotifier.setMapLayerStyle,
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }

  /// Opens a titled bottom sheet for a tapped marker: the site name (or
  /// "Unnamed site"), the coordinates to 5dp, and — for named markers that
  /// have matching stats — the dive count + first → last date.
  void _showSiteCard(({String? siteName, double lat, double lon}) s) {
    final name = s.siteName;
    SiteStat? stat;
    if (name != null) {
      for (final st in _stats ?? const <SiteStat>[]) {
        if (st.name == name) {
          stat = st;
          break;
        }
      }
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final coords =
            '${s.lat.toStringAsFixed(5)}, ${s.lon.toStringAsFixed(5)}';
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Spacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Unnamed site',
                  style: theme.textTheme.titleLarge,
                ),
                const SizedBox(height: Spacing.sm),
                Text(coords, style: theme.textTheme.bodyMedium),
                if (stat != null) ...[
                  const SizedBox(height: Spacing.sm),
                  Text(
                    _statsLine(stat),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _statsLine(SiteStat stat) {
    final dives =
        stat.diveCount == 1 ? '1 dive' : '${stat.diveCount} dives';
    final first = _formatDate(stat.firstDiveTime);
    final last = _formatDate(stat.lastDiveTime);
    final range = first == last ? first : '$first → $last';
    return '$dives · $range';
  }

  Widget _buildMap(
      List<({String? siteName, double lat, double lon})> sites,
      MapLayerStyle style) {
    final points = [for (final s in sites) LatLng(s.lat, s.lon)];
    final cLat = widget.currentLat;
    final cLon = widget.currentLon;

    final MapOptions options;
    if (points.isEmpty) {
      options = const MapOptions(
        initialCenter: LatLng(0, 0),
        initialZoom: 2,
      );
    } else if (cLat != null && cLon != null) {
      // Came from a specific dive — focus on it at z=14 so the diver
      // sees their dive's location at a useful scale. Other pins still
      // pinned; pan/zoom-out reveals them.
      options = MapOptions(
        initialCenter: LatLng(cLat, cLon),
        initialZoom: 14,
      );
    } else if (points.length == 1) {
      options = MapOptions(
        initialCenter: points.first,
        initialZoom: 11,
      );
    } else {
      options = MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(48),
        ),
      );
    }

    return FlutterMap(
      options: options,
      children: [
        TileLayer(
          urlTemplate: tileUrlFor(style),
          userAgentPackageName: 'app.ccrlogger',
        ),
        MarkerLayer(markers: [
          for (final s in sites)
            Marker(
              point: LatLng(s.lat, s.lon),
              width: _isCurrent(s.lat, s.lon) ? 44 : 36,
              height: _isCurrent(s.lat, s.lon) ? 44 : 36,
              child: GestureDetector(
                onTap: () => _showSiteCard(s),
                child: _isCurrent(s.lat, s.lon)
                    ? Icon(Icons.location_pin,
                        color: context.palette.accentPrimary, size: 44)
                    : const Icon(Icons.location_pin,
                        // Muted brick red — visibly recedes against the
                        // saturated accent of the current dive's pin
                        // while staying legible on OSM's mixed terrain.
                        color: Color(0xFF8B3A3A), size: 28),
              ),
            ),
        ]),
      ],
    );
  }
}
