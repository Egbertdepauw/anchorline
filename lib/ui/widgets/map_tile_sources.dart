/// OSM raster tiles. Free, no API key. OSM's ToS asks heavy users to
/// move to a commercial provider; beta-scale usage is fine.
const String osmTileUrl =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// ESRI World Imagery — satellite raster tiles. Free for non-commercial
/// use, no API key required. Note: `{y}/{x}` swapped vs OSM.
const String esriSatelliteTileUrl =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

/// Visual style for a map's base layer. Used by [SitesMapScreen] and
/// [SiteMapView] to swap the active [TileLayer] URL. Mini-maps don't
/// expose a toggle and always render `normal`.
enum MapLayerStyle { normal, satellite }

String tileUrlFor(MapLayerStyle style) => switch (style) {
      MapLayerStyle.normal => osmTileUrl,
      MapLayerStyle.satellite => esriSatelliteTileUrl,
    };
