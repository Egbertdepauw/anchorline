import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'site_mini_map.dart';

/// Tab-2 content of the site tab-group: a wider read-only minimap
/// showing the dive's coords with a name + lat/lon overlay strip.
/// Tap → caller-defined navigation (typically opens SitesMapScreen).
class SiteMapView extends StatelessWidget {
  const SiteMapView({
    super.key,
    required this.lat,
    required this.lon,
    this.siteName,
    this.onTap,
  });

  final double lat;
  final double lon;
  final String? siteName;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final coordsLabel =
        '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}';
    // Fills the available width and height so the map reaches edge-to-
    // edge inside its tab-view slot. The marker stays a fixed small
    // size regardless of map dimensions.
    return LayoutBuilder(builder: (context, constraints) {
      final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
      final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 220.0;
      return Stack(
        children: [
          SiteMiniMap(
            lat: lat,
            lon: lon,
            width: w,
            height: h,
            markerSize: 24,
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
                    if (siteName != null && siteName!.isNotEmpty)
                      Text(
                        siteName!,
                        style: AppTypography.body.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (siteName != null && siteName!.isNotEmpty)
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
    });
  }
}
