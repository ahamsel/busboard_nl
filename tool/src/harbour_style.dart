/// Builds the "Harbour quiet" MapLibre styles (spec §3.1) from OpenFreeMap's
/// Positron style. Pure (no I/O) so it is unit-tested; tool/build_map_styles.dart
/// does the fetching and writing.
library;

import 'dart:convert';

class HarbourPalette {
  const HarbourPalette({
    required this.name,
    required this.land,
    required this.water,
    required this.park,
    required this.road,
    required this.roadCasing,
    required this.label,
    required this.building,
  });

  final String name;
  final String land;
  final String water;
  final String park;
  final String road;
  final String roadCasing;
  final String label;
  final String building;

  /// Neutral greys (spec 2026-10-14 §2.4): water stays blue-grey and parks a muted green, the only coloured land.
  static const light = HarbourPalette(
    name: 'Harbour light',
    land: '#EEF0F2',
    water: '#C9D9E4',
    park: '#DCE8DD',
    road: '#FFFFFF',
    roadCasing: '#D9DCE0',
    label: '#737880',
    building: '#E4E6E9',
  );

  /// A neutral dark grey a step below the app's dark `surface` (#1F2024), so sheets, cards and map buttons stand
  /// clear of the map; their hairline border does the rest. Water is a deeper blue than the land around it
  /// (ΔE OKLab 0.039), so the harbour, the coastline and the ponds stay visible at night.
  static const dark = HarbourPalette(
    name: 'Harbour dark',
    land: '#17181B',
    water: '#0E1F2E',
    park: '#172019',
    road: '#26282C',
    roadCasing: '#2F3237',
    label: '#80848C',
    building: '#1E1F23',
  );
}

/// Layers we draw ourselves (transit) or that are clutter for St. John's
/// (road shields, airport icons).
const _dropped = {
  'railway_transit',
  'railway_transit_dashline',
  'railway_service',
  'railway_service_dashline',
  'highway-shield-us-interstate',
  'road_shield_us',
  'highway-shield-non-us',
  'airport',
};

const _parkLayers = {'park', 'landuse_park', 'landcover_wood'};
const _landLayers = {'landuse_residential', 'landcover_ice_shelf', 'landcover_glacier'};
const _minorRoadLabels = {'highway-name-minor', 'highway-name-path'};

Map<String, dynamic> buildHarbourStyle(Map<String, dynamic> upstream, HarbourPalette p) {
  // Deep copy so the caller's map is untouched.
  final style = jsonDecode(jsonEncode(upstream)) as Map<String, dynamic>;
  style['name'] = p.name;
  final out = <Map<String, dynamic>>[];
  for (final layer in (style['layers'] as List).cast<Map<String, dynamic>>()) {
    final id = layer['id'] as String;
    final sourceLayer = layer['source-layer'];
    if (_dropped.contains(id) || sourceLayer == 'poi') continue;
    final paint = (layer['paint'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    final type = layer['type'];

    if (type == 'background') {
      paint['background-color'] = p.land;
    } else if (sourceLayer == 'water' && type == 'fill') {
      paint['fill-color'] = p.water;
    } else if (sourceLayer == 'waterway' && type == 'line') {
      paint['line-color'] = p.water;
    } else if (_parkLayers.contains(id)) {
      paint['fill-color'] = p.park;
      paint.remove('fill-pattern');
    } else if (_landLayers.contains(id)) {
      paint['fill-color'] = p.land;
    } else if (sourceLayer == 'building') {
      paint['fill-color'] = p.building;
      paint['fill-outline-color'] = p.building;
      final minzoom = (layer['minzoom'] as num?) ?? 0;
      layer['minzoom'] = minzoom < 16 ? 16 : minzoom;
    } else if (sourceLayer == 'aeroway') {
      if (type == 'fill') paint['fill-color'] = p.roadCasing;
      if (type == 'line') paint['line-color'] = p.roadCasing;
    } else if (sourceLayer == 'transportation' && type == 'line') {
      final casing = id.contains('casing') || id.startsWith('railway');
      paint['line-color'] = casing ? p.roadCasing : p.road;
    } else if (sourceLayer == 'transportation' && type == 'fill') {
      paint['fill-color'] = p.road;
    } else if (sourceLayer == 'boundary' && type == 'line') {
      paint['line-color'] = p.roadCasing;
    }

    if (type == 'symbol') {
      final layout = layer['layout'];
      // Positron's place labels carry a black dot icon that vanishes on the
      // dark map; the label text alone is enough.
      if (sourceLayer == 'place' && layout is Map) layout.remove('icon-image');
      if (paint.containsKey('text-color') || (layout is Map && layout.containsKey('text-field'))) {
        paint['text-color'] = p.label;
        paint['text-halo-color'] = p.land;
      }
      if (_minorRoadLabels.contains(id)) {
        final minzoom = (layer['minzoom'] as num?) ?? 0;
        layer['minzoom'] = minzoom < 15 ? 15 : minzoom;
      }
    }

    layer['paint'] = paint;
    out.add(layer);
  }
  style['layers'] = out;
  return style;
}

/// The committed file format: two-space JSON with a trailing newline.
String encodeHarbourStyle(Map<String, dynamic> style) => '${const JsonEncoder.withIndent('  ').convert(style)}\n';
