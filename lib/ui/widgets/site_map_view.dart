import 'package:flutter/material.dart';

import '../notifiers/settings_notifier.dart';
import '../theme/tokens.dart';
import 'map_layer_toggle.dart';
import 'map_tile_sources.dart';
import 'site_mini_map.dart';

/// Tab-2 content of the site tab-group: a wider read-only minimap
/// showing the dive's coords with a name + lat/lon overlay strip.
/// Tap → caller-defined navigation (typically opens SitesMapScreen).
/// A floating [MapLayerToggle] in the top-right corner lets the user
/// switch between OSM and satellite imagery.
class SiteMapView extends StatefulWidget {
  const SiteMapView({
    super.key,
    required this.lat,
    required this.lon,
    required this.settingsNotifier,
    this.siteName,
    this.onTap,
  });

  final double lat;
  final double lon;
  final SettingsNotifier settingsNotifier;
  final String? siteName;
  final VoidCallback? onTap;

  @override
  State<SiteMapView> createState() => _SiteMapViewState();
}

class _SiteMapViewState extends State<SiteMapView> {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lat = widget.lat;
    final lon = widget.lon;
    final siteName = widget.siteName;
    final onTap = widget.onTap;
    final coordsLabel =
        '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';

    // Fills the available width and height so the map reaches edge-to-
    // edge inside its tab-view slot. The marker stays a fixed small
    // size regardless of map dimensions.
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
      return ListenableBuilder(
        listenable: widget.settingsNotifier,
        builder: (context, _) {
          final style = widget.settingsNotifier.mapLayerStyle;
          return Stack(
            children: [
              SiteMiniMap(
                lat: lat,
                lon: lon,
                width: w,
                height: h,
                markerSize: 24,
                tileUrl: tileUrlFor(style),
              ),
              Positioned(
                right: Spacing.sm,
                top: Spacing.sm,
                child: MapLayerToggle(
                  current: style,
                  onChanged: widget.settingsNotifier.setMapLayerStyle,
                ),
              ),
          Positioned(
            left: Spacing.sm,
            right: Spacing.sm,
            bottom: Spacing.sm,
            child: InkWell(
              onTap: onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Spacing.sm, vertical: Spacing.xs),
                decoration: BoxDecoration(
                  color: scheme.surface.withValues(alpha: 0.85),
                  borderRadius: Radii.cardBr,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (siteName != null && siteName.isNotEmpty)
                      Text(
                        siteName,
                        style: AppTypography.body.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (siteName != null && siteName.isNotEmpty)
                      const SizedBox(height: Spacing.xs),
                    Text(
                      coordsLabel,
                      style: AppTypography.readoutSm.copyWith(
                        color: scheme.outlineVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
          );
        },
      );
    });
  }
}
