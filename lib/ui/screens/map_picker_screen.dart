import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// OpenStreetMap tile server. Note: tile.openstreetmap.org's usage policy
/// disallows production use in mobile apps; swap to a permitted provider
/// (MapTiler / Stadia / self-hosted) before public release.
const String _tileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

class MapPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLon;

  const MapPickerScreen({super.key, this.initialLat, this.initialLon});

  @override
  State<MapPickerScreen> createState() => _MapPickerScreenState();
}

class _MapPickerScreenState extends State<MapPickerScreen> {
  final _mapController = MapController();
  LatLng _pin = const LatLng(0, 0);
  bool _initialised = false;

  @override
  void initState() {
    super.initState();
    _initPin();
  }

  Future<void> _initPin() async {
    LatLng? p;
    if (widget.initialLat != null && widget.initialLon != null) {
      p = LatLng(widget.initialLat!, widget.initialLon!);
    } else {
      p = await _currentLocation();
    }
    p ??= const LatLng(0, 0);
    if (!mounted) return;
    setState(() {
      _pin = p!;
      _initialised = true;
    });
    // Don't call _mapController.move here — FlutterMap hasn't been built
    // on the first pump (we're inside the `_initialised == false`
    // branch). MapOptions.initialCenter handles the initial position.
    // _useCurrent() can move() later because by then the map is rendered.
  }

  Future<LatLng?> _currentLocation() async {
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        final req = await Geolocator.requestPermission();
        if (req != LocationPermission.always &&
            req != LocationPermission.whileInUse) {
          return null;
        }
      }
      final pos = await Geolocator.getCurrentPosition();
      return LatLng(pos.latitude, pos.longitude);
    } catch (_) {
      return null;
    }
  }

  Future<void> _useCurrent() async {
    final p = await _currentLocation();
    if (p == null || !mounted) return;
    setState(() => _pin = p);
    _mapController.move(p, 13);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick location'),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _useCurrent,
            tooltip: 'Use current location',
          ),
        ],
      ),
      body: !_initialised
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _pin,
                    initialZoom: 13,
                    onTap: (_, point) => setState(() => _pin = point),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: _tileUrlTemplate,
                      userAgentPackageName: 'app.ccrlogger',
                    ),
                    MarkerLayer(markers: [
                      Marker(
                        point: _pin,
                        width: 36,
                        height: 36,
                        child: const Icon(Icons.location_pin,
                            color: Colors.red, size: 36),
                      ),
                    ]),
                  ],
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 24,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.check),
                    label: Text(
                        'Use ${_pin.latitude.toStringAsFixed(5)}, ${_pin.longitude.toStringAsFixed(5)}'),
                    onPressed: () => Navigator.of(context).pop(
                      (lat: _pin.latitude, lon: _pin.longitude),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
