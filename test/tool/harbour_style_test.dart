import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:busboard_nl/ui/kit/tokens.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import '../../tool/src/harbour_style.dart';
import '../kit/route_palette_test.dart' show deltaE, oklab;

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
      expect(_layer(light, 'background')['paint']['background-color'], '#EEF0F2');
      expect(_layer(light, 'water')['paint']['fill-color'], '#C9D9E4');
      expect(_layer(light, 'waterway')['paint']['line-color'], '#C9D9E4');
      expect(_layer(light, 'park')['paint']['fill-color'], '#DCE8DD');
      expect(_layer(light, 'landcover_wood')['paint']['fill-color'], '#DCE8DD');
      expect((_layer(light, 'landcover_wood')['paint'] as Map).containsKey('fill-pattern'), isFalse);
      expect(_layer(dark, 'background')['paint']['background-color'], '#17181B');
      expect(_layer(dark, 'water')['paint']['fill-color'], '#0E1F2E');
      expect(_layer(dark, 'park')['paint']['fill-color'], '#172019');
    });

    test('roads are white on a light casing (dark: road on casing)', () {
      expect(_layer(light, 'highway_major_inner')['paint']['line-color'], '#FFFFFF');
      expect(_layer(light, 'highway_major_casing')['paint']['line-color'], '#D9DCE0');
      expect(_layer(dark, 'highway_major_inner')['paint']['line-color'], '#26282C');
      expect(_layer(dark, 'highway_major_casing')['paint']['line-color'], '#2F3237');
      expect(_layer(light, 'highway_major_inner')['paint']['line-width'], 2, reason: 'widths are kept');
    });

    test('labels use the label colour with a land halo', () {
      for (final id in ['highway-name-minor', 'label_city']) {
        expect(_layer(light, id)['paint']['text-color'], '#737880');
        expect(_layer(light, id)['paint']['text-halo-color'], '#EEF0F2');
        expect(_layer(dark, id)['paint']['text-color'], '#80848C');
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
    for (final (path, palette, land) in [
      ('assets/map/harbour_light.json', HarbourPalette.light, '#EEF0F2'),
      ('assets/map/harbour_dark.json', HarbourPalette.dark, '#17181B'),
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

      test('$path is painted entirely in the current palette', () {
        final text = File(path).readAsStringSync();
        final style = jsonDecode(text) as Map<String, dynamic>;
        expect(encodeHarbourStyle(buildHarbourStyle(style, palette)), text,
            reason: 'run: dart run tool/build_map_styles.dart --recolour');
      });
    }
  });

  test('the dark map sits a step below the sheet floating on it (spec 2026-10-14 §2.4)', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    final land = hex(HarbourPalette.dark.land);
    expect(land.computeLuminance(), lessThan(BBColors.dark.surface.computeLuminance()));
  });

  test('both maps are neutral: only water and parks carry colour (spec 2026-10-14 §2.4)', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    double chroma(String h) {
      final lab = oklab(hex(h));
      return math.sqrt(lab[1] * lab[1] + lab[2] * lab[2]);
    }

    for (final p in [HarbourPalette.light, HarbourPalette.dark]) {
      for (final (name, value) in [
        ('land', p.land),
        ('road', p.road),
        ('roadCasing', p.roadCasing),
        ('label', p.label),
        ('building', p.building),
      ]) {
        expect(chroma(value), lessThanOrEqualTo(0.015), reason: '${p.name} $name $value is tinted');
      }
      expect(chroma(p.water), greaterThan(0.015), reason: '${p.name} water is still blue-grey');
      expect(chroma(p.park), greaterThan(0.015), reason: '${p.name} parks are still green');
    }
  });

  test('water stands clear of the land on both maps, so the coastline shows (ΔE OKLab 0.03 or more)', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    for (final p in [HarbourPalette.light, HarbourPalette.dark]) {
      final d = deltaE(hex(p.water), hex(p.land));
      expect(d, greaterThanOrEqualTo(0.03), reason: '${p.name} water ${p.water} is only ${d.toStringAsFixed(3)} from land ${p.land}');
    }
  });

  test('map labels stay readable on the land (3:1 or more)', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final p in [HarbourPalette.light, HarbourPalette.dark]) {
      expect(ratio(hex(p.label), hex(p.land)), greaterThanOrEqualTo(3.0), reason: p.name);
    }
  });

  test('map labels stay readable on the water too (3:1 or more), and the shipped styles use the palette', () {
    Color hex(String h) => Color(int.parse('FF${h.substring(1)}', radix: 16));
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final (p, asset) in [(HarbourPalette.light, 'harbour_light'), (HarbourPalette.dark, 'harbour_dark')]) {
      expect(ratio(hex(p.label), hex(p.water)), greaterThanOrEqualTo(3.0), reason: '${p.name} label on water');
      // The labels drawn on water in the bundled styles carry that same label and water colour.
      final style = jsonDecode(File('assets/map/$asset.json').readAsStringSync()) as Map<String, dynamic>;
      final layers = (style['layers'] as List).cast<Map<String, dynamic>>();
      Map<String, dynamic> paint(String id) => layers.firstWhere((l) => l['id'] == id)['paint'] as Map<String, dynamic>;
      expect(paint('water')['fill-color'], p.water, reason: asset);
      for (final id in ['water_name_point_label', 'water_name_line_label', 'waterway_line_label']) {
        expect(paint(id)['text-color'], p.label, reason: '$asset $id');
      }
    }
  });
}
