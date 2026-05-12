// flutter_map's default TileProvider caches in-memory per session only;
// good enough for current scale, swap to a disk-cached provider later.
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class SiteMiniMap extends StatelessWidget {
  final double lat;
  final double lon;

  /// Square shorthand. Used when [width] and [height] are not supplied.
  final double size;

  /// Optional explicit dimensions for non-square presentations (e.g. a
  /// full-width Map tab inside a TabBarView). Both default to [size].
  final double? width;
  final double? height;

  /// Pin marker size in logical pixels. Defaults to ~25% of the map's
  /// shortest dimension, capped at 32 px so the pin doesn't dominate
  /// on large maps. Independent of map dimensions when supplied.
  final double? markerSize;

  const SiteMiniMap({
    super.key,
    required this.lat,
    required this.lon,
    this.size = 64,
    this.width,
    this.height,
    this.markerSize,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    final w = width ?? size;
    final h = height ?? size;
    final shortest = w < h ? w : h;
    final pin = markerSize ?? (shortest * 0.4).clamp(16.0, 32.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: w,
        height: h,
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
                width: pin,
                height: pin,
                child: Icon(
                  Icons.place,
                  size: pin,
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
