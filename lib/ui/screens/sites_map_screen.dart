import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/db/dive_annotations_dao.dart';
import '../theme/tokens.dart';
import '../widgets/map_layer_toggle.dart';
import '../widgets/map_tile_sources.dart';

class SitesMapScreen extends StatefulWidget {
  final DiveAnnotationsDao dao;
  final double? currentLat;
  final double? currentLon;

  const SitesMapScreen({
    super.key,
    required this.dao,
    required this.currentLat,
    required this.currentLon,
  });

  @override
  State<SitesMapScreen> createState() => _SitesMapScreenState();
}

class _SitesMapScreenState extends State<SitesMapScreen> {
  List<({String? siteName, double lat, double lon})>? _sites;
  MapLayerStyle _style = MapLayerStyle.normal;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final sites = await widget.dao.distinctSiteCoords();
    if (!mounted) return;
    setState(() => _sites = sites);
  }

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
      appBar: AppBar(title: const Text('Dive sites')),
      body: _sites == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                _buildMap(_sites!),
                Positioned(
                  top: Spacing.sm,
                  right: Spacing.sm,
                  child: MapLayerToggle(
                    current: _style,
                    onChanged: (next) => setState(() => _style = next),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildMap(List<({String? siteName, double lat, double lon})> sites) {
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
          urlTemplate: tileUrlFor(_style),
          userAgentPackageName: 'app.ccrlogger',
        ),
        MarkerLayer(markers: [
          for (final s in sites)
            Marker(
              point: LatLng(s.lat, s.lon),
              width: _isCurrent(s.lat, s.lon) ? 44 : 36,
              height: _isCurrent(s.lat, s.lon) ? 44 : 36,
              child: _isCurrent(s.lat, s.lon)
                  ? Icon(Icons.location_pin,
                      color: AppColors.wreck.accentPrimary, size: 44)
                  : const Icon(Icons.location_pin,
                      // Muted brick red — visibly recedes against the
                      // saturated accent of the current dive's pin
                      // while staying legible on OSM's mixed terrain.
                      color: Color(0xFF8B3A3A), size: 28),
            ),
        ]),
      ],
    );
  }
}
