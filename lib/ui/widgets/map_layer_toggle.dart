import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'map_tile_sources.dart';

/// Floating Normal/Satellite layer toggle for a map. Sized small so it
/// sits unobtrusively in a corner. The icon represents the layer the
/// user would switch TO if they tap (so Normal mode shows the
/// satellite icon, and vice versa).
class MapLayerToggle extends StatelessWidget {
  const MapLayerToggle({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final MapLayerStyle current;
  final ValueChanged<MapLayerStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final next = current == MapLayerStyle.normal
        ? MapLayerStyle.satellite
        : MapLayerStyle.normal;
    final icon = current == MapLayerStyle.normal
        ? Icons.satellite_alt
        : Icons.layers_outlined;
    return Material(
      color: scheme.surfaceContainer.withValues(alpha: 0.92),
      borderRadius: Radii.cardBr,
      child: InkWell(
        borderRadius: Radii.cardBr,
        onTap: () => onChanged(next),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.sm),
          child: Icon(
            icon,
            size: 20,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}
