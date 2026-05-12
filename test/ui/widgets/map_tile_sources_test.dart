import 'package:ccrlogger/ui/widgets/map_tile_sources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tileUrlFor returns OSM for normal style', () {
    expect(tileUrlFor(MapLayerStyle.normal), osmTileUrl);
    expect(osmTileUrl, contains('tile.openstreetmap.org'));
  });

  test('tileUrlFor returns ESRI World Imagery for satellite style', () {
    expect(tileUrlFor(MapLayerStyle.satellite), esriSatelliteTileUrl);
    expect(esriSatelliteTileUrl, contains('server.arcgisonline.com'));
    expect(esriSatelliteTileUrl, contains('World_Imagery'));
  });

  test('MapLayerStyle has exactly two values', () {
    expect(MapLayerStyle.values.length, 2);
  });
}
