import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/harbour_style.dart';

/// A cut-down Positron: one layer of each kind the transform handles.
Map<String, dynamic> _upstream() => {
      'version': 8,
      'name': 'Positron',
      'glyphs': 'https://tiles.openfreemap.org/fonts/{fontstack}/{range}.pbf',
      'sprite': 'https://tiles.openfreemap.org/sprites/ofm_f384/ofm',
      'sources': {
        'openmaptiles': {'type': 'vector', 'url': 'https://tiles.openfreemap.org/planet'},
      },
      'layers': [
        {'id': 'background', 'type': 'background', 'paint': {'background-color': '#f2f3f0'}},
        {'id': 'park', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'park', 'paint': {'fill-color': '#e6f0e1'}},
        {'id': 'water', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'water', 'paint': {'fill-color': '#c2c8ca'}},
        {'id': 'waterway', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'waterway', 'paint': {'line-color': '#c2c8ca'}},
        {'id': 'landcover_wood', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'landcover', 'minzoom': 10, 'paint': {'fill-color': '#e6eedf', 'fill-pattern': 'wood'}},
        {'id': 'building', 'type': 'fill', 'source': 'openmaptiles', 'source-layer': 'building', 'minzoom': 12, 'paint': {'fill-color': '#e4e4e4', 'fill-outline-color': '#d8d8d8'}},
        {'id': 'highway_major_casing', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'transportation', 'paint': {'line-color': '#dddddd', 'line-width': 3}},
        {'id': 'highway_major_inner', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'transportation', 'paint': {'line-color': '#ffffff', 'line-width': 2}},
        {'id': 'railway_transit', 'type': 'line', 'source': 'openmaptiles', 'source-layer': 'transportation', 'paint': {'line-color': '#dddddd'}},
        {'id': 'poi_z16', 'type': 'symbol', 'source': 'openmaptiles', 'source-layer': 'poi', 'layout': {'icon-image': 'x'}},
        {'id': 'highway-name-minor', 'type': 'symbol', 'source': 'openmaptiles', 'source-layer': 'transportation_name', 'minzoom': 14, 'paint': {'text-color': '#666666', 'text-halo-color': '#ffffff'}},
        {'id': 'label_city', 'type': 'symbol', 'source': 'openmaptiles', 'source-layer': 'place', 'layout': {'text-field': '{name}', 'icon-image': 'dot_city'}, 'paint': {'text-color': '#555555', 'text-halo-color': '#ffffff'}},
        {'id': 'highway-shield-non-us', 'type': 'symbol', 'source': 'openmaptiles', 'source-layer': 'transportation_name', 'layout': {'icon-image': 'road_{ref_length}'}},
        {'id': 'airport', 'type': 'symbol', 'source': 'openmaptiles', 'source-layer': 'aerodrome_label', 'layout': {'icon-image': 'airport'}},
      ],
    };

Map<String, dynamic> _layer(Map<String, dynamic> style, String id) =>
    (style['layers'] as List).cast<Map<String, dynamic>>().firstWhere((l) => l['id'] == id);

bool _has(Map<String, dynamic> style, String id) =>
    (style['layers'] as List).cast<Map<String, dynamic>>().any((l) => l['id'] == id);

void main() {
  group('buildHarbourStyle', () {
    final light = buildHarbourStyle(_upstream(), HarbourPalette.light);
    final dark = buildHarbourStyle(_upstream(), HarbourPalette.dark);

    test('paints land, water and parks in the palette', () {
      expect(_layer(light, 'background')['paint']['background-color'], '#EEF1F4');
      expect(_layer(light, 'water')['paint']['fill-color'], '#BFD6EA');
      expect(_layer(light, 'waterway')['paint']['line-color'], '#BFD6EA');
      expect(_layer(light, 'park')['paint']['fill-color'], '#DCE8DC');
      expect(_layer(light, 'landcover_wood')['paint']['fill-color'], '#DCE8DC');
      expect((_layer(light, 'landcover_wood')['paint'] as Map).containsKey('fill-pattern'), isFalse);
      expect(_layer(dark, 'background')['paint']['background-color'], '#141C25');
      expect(_layer(dark, 'water')['paint']['fill-color'], '#0E2A40');
      expect(_layer(dark, 'park')['paint']['fill-color'], '#16261F');
    });

    test('roads are white on a light casing (dark: road on casing)', () {
      expect(_layer(light, 'highway_major_inner')['paint']['line-color'], '#FFFFFF');
      expect(_layer(light, 'highway_major_casing')['paint']['line-color'], '#D5DCE3');
      expect(_layer(dark, 'highway_major_inner')['paint']['line-color'], '#24303C');
      expect(_layer(dark, 'highway_major_casing')['paint']['line-color'], '#2E3B48');
      expect(_layer(light, 'highway_major_inner')['paint']['line-width'], 2, reason: 'widths are kept');
    });

    test('labels use the label colour with a land halo', () {
      for (final id in ['highway-name-minor', 'label_city']) {
        expect(_layer(light, id)['paint']['text-color'], '#7A8794');
        expect(_layer(light, id)['paint']['text-halo-color'], '#EEF1F4');
        expect(_layer(dark, id)['paint']['text-color'], '#7D8B99');
      }
    });

    test('clutter is removed: transit, POI, early buildings and minor road labels', () {
      expect(_has(light, 'railway_transit'), isFalse);
      expect(_has(light, 'poi_z16'), isFalse);
      expect(_layer(light, 'building')['minzoom'], 16);
      expect(_layer(light, 'highway-name-minor')['minzoom'], 15);
    });

    test('sprite clutter is removed: shields, airport icons and place dots', () {
      expect(_has(light, 'highway-shield-non-us'), isFalse);
      expect(_has(light, 'airport'), isFalse);
      expect((_layer(light, 'label_city')['layout'] as Map).containsKey('icon-image'), isFalse);
      expect(_layer(light, 'label_city')['layout']['text-field'], '{name}', reason: 'the label itself stays');
    });

    test('keeps OpenFreeMap sources, glyphs and sprite, and needs no key', () {
      expect(light['sources'], _upstream()['sources']);
      expect(light['glyphs'], _upstream()['glyphs']);
      expect(light['sprite'], _upstream()['sprite']);
      expect(light['name'], 'Harbour light');
      expect(jsonEncode(light).toLowerCase(), isNot(contains('key=')));
    });

    test('does not modify its input', () {
      final upstream = _upstream();
      buildHarbourStyle(upstream, HarbourPalette.light);
      expect(upstream, _upstream());
    });
  });

  group('committed styles', () {
    for (final (path, land) in [
      ('assets/map/harbour_light.json', '#EEF1F4'),
      ('assets/map/harbour_dark.json', '#141C25'),
    ]) {
      test('$path is a generated Harbour style', () {
        final style = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
        expect(style['version'], 8);
        expect(_layer(style, 'background')['paint']['background-color'], land);
        final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
        expect(layers.where((l) => '${l['id']}'.startsWith('railway_transit')), isEmpty);
        expect(layers.where((l) => l['source-layer'] == 'poi'), isEmpty);
        expect(layers.where((l) => l['id'] == 'airport' || l['id'] == 'highway-shield-non-us'), isEmpty);
        expect(_layer(style, 'building')['minzoom'], greaterThanOrEqualTo(16));
        expect('${style['glyphs']}', startsWith('https://tiles.openfreemap.org/'));
        expect(jsonEncode(style).toLowerCase(), isNot(contains('key=')));
      });
    }
  });
}
