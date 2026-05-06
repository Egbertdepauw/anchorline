import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../data/db/dive_annotations_dao.dart';

/// OpenStreetMap tile server. Same caveat as MapPickerScreen: swap to a
/// permitted provider before public release.
const String _tileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

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
          : _buildMap(_sites!),
    );
  }

  Widget _buildMap(List<({String? siteName, double lat, double lon})> sites) {
    final points = [for (final s in sites) LatLng(s.lat, s.lon)];

    final MapOptions options;
    if (points.isEmpty) {
      options = const MapOptions(
        initialCenter: LatLng(0, 0),
        initialZoom: 2,
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
          urlTemplate: _tileUrlTemplate,
          userAgentPackageName: 'app.ccrlogger',
        ),
        MarkerLayer(markers: [
          for (final s in sites)
            Marker(
              point: LatLng(s.lat, s.lon),
              width: 36,
              height: 36,
              child: _isCurrent(s.lat, s.lon)
                  ? const Icon(Icons.location_pin,
                      color: Colors.redAccent, size: 36)
                  : const Icon(Icons.location_pin,
                      color: Color(0xFF80DEEA), size: 28),
            ),
        ]),
      ],
    );
  }
}
