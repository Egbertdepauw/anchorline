// flutter_map's default TileProvider caches in-memory per session only;
// good enough for current scale, swap to a disk-cached provider later.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SiteMiniMap extends StatelessWidget {
  final double lat;
  final double lon;
  final double size;

  const SiteMiniMap({
    super.key,
    required this.lat,
    required this.lon,
    this.size = 64,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 11,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
              urlTemplate:
                  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'app.ccrlogger',
            ),
            MarkerLayer(markers: [
              Marker(
                point: point,
                width: size * 0.4,
                height: size * 0.4,
                child: Icon(
                  Icons.place,
                  size: size * 0.4,
                  color: Colors.redAccent,
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
