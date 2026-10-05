# Harbour Phase 3b-2 — Map style, markers, cards and the map screen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the Map tab on the Harbour kit. It gets the "Harbour quiet" map style, route-badge bus markers with a heading notch, a floating sheet with stop and bus cards, the map chips and the control pill. No Material remains in `lib/ui/map/`.

**Architecture:**
- **Style:** a build-time Dart tool turns OpenFreeMap's Positron style into two committed style JSONs (light and dark).
- **Map layers:** a small `MapSurface` interface sits between our layer code and MapLibre. Layer setup, marker images and GeoJSON updates are therefore unit-tested against a fake.
- **Map screen:** the widget gets its map from an injectable `MapViewBuilder`. Widget tests then run the real layout, chips, sheet and cards with a stub instead of the MapLibre platform view.
- **Motion:** comes from Phase 3b-1 (`busTrackStoreProvider`, `busTrackRendererProvider`). The screen calls `renderAll` once per frame, exactly as today.

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5, Riverpod 3, go_router 18, maplibre_gl 0.27.1, `dart:ui` for marker bitmaps.

**Spec:** `docs/superpowers/specs/2026-10-04-harbour-phase3-design.md` §3.1–3.3 and §3.6 (with §2.4 for the AppShell padding). Parent spec: `docs/superpowers/specs/2026-10-04-harbour-redesign-design.md`. Carried-over items come from `docs/superpowers/notes/2026-10-04-harbour-phase3a-ledger.md` and `docs/superpowers/notes/2026-10-05-harbour-phase3b1-ledger.md`.

**Scope split:** follow mode (§3.5) — the followed route line, the follow camera, the follow card, Board-row entry and the bus card's *Follow* button — is **Plan 3b-3**. It builds on everything here. This plan leaves the map fully usable without it.

## Global Constraints

- Free and open-licensed parts only; no cloud project, accounts or API keys. Tiles, glyphs and sprites load from OpenFreeMap with no key (spec §1, §3.1).
- Screen code under `lib/ui/` (outside `lib/ui/kit/`) imports `package:flutter/widgets.dart` and `ui/kit/kit.dart`, never Material or Cupertino. `test/kit/kit_boundary_test.dart` enforces this, and its `_legacyAllowList` must end **empty** (spec §1, §3.6).
- `lib/domain/` has no Flutter imports (spec §3.4).
- Light map colours: land `#EEF1F4`, water `#BFD6EA`, parks `#DCE8DC`, roads white with `#D5DCE3` casing, labels `#7A8794` (spec §3.1).
- Dark map colours: land `#141C25`, water `#0E2A40`, parks `#16261F`, roads `#24303C` / `#2E3B48`, labels `#7D8B99` (spec §3.1).
- Clutter removed from the base map: POI icons, building outlines below zoom 16, minor road labels below zoom 15, transit layers (spec §3.1).
- The map follows the app theme, or the Settings → Map theme override (`AppSettings.mapThemeMode`; null = follow the app) (spec §3.1).
- Rotation and tilt are off and there is no compass (spec §3.1).
- Stops are small white dots with an ink ring, hidden below zoom 14.5. Your stop is a brand-blue disc with a white star at every zoom (spec §3.2).
- **Bus marker:** the board's rounded badge (radius 6.5, route `fill`, route ink number, 2 px white outline) plus a heading notch triangle in the route colour, rotated to the heading. Both are symbol layers with `icon-allow-overlap`. A stale bus (no fix for over 90 s) gets a grey badge (spec §3.2).
- **Layout:** full-screen map under the status bar. Top-left `BBChip` "★ MUN Centre · 1150 ▾" opens the stop picker. Top-right `BBChip` "All routes ▾" opens a floating card of route badges for multi-select. The right-hand `BBControlPill` holds my location. The bottom `BBSheet` peeks your stop's next 1–2 arrivals and drags up to the full list (spec §3.3).
- **Tapping a stop** opens its stop card, with arrivals, *Set as my stop* and *Open board*. **Tapping a bus** opens its bus card, with route, destination, bus number, early/late, and a collapsed *Technical details* section (speed, heading, last GPS time) (spec §3.3; the *Follow* button is Plan 3b-3).
- The map lays out its own sheet above the nav bar. AppShell no longer pads the map branch (spec §2.4).
- Debug snackbars are removed; debug logging stays behind `kDebugMode` (spec §3.6).
- Accessibility stays at least as good as today: every control has a label, and cards survive 320 pt and 360 pt widths at text ×2.0 (spec §1, §4).

## Review Focus

These are the inputs most likely to bite a rider that no task's main tests aim at. Each line is pinned by a test in the owning task.

1. **Theme or style switch mid-session** (Settings → Map theme, or the phone going dark). MapLibre drops every image, source and layer on a style reload. The map must re-register its images and layers and keep drawing buses. Test: Task 4, "install after a style reload re-adds images and layers".
2. **A route whose short name is not a plain number, or a bus with route number 0.** The badge must show a sensible label and a stable colour, never "0" with hue 0. Test: Task 4, "label falls back to routeRun, then '?'".
3. **Many buses on the same route.** Each badge and notch image is generated and registered once, not once per bus per frame. Test: Task 4, "images are registered once per id".
4. **No stop chosen yet.** The chip reads "Choose a stop", the sheet invites you to choose one, and nothing crashes. Test: Task 7, "with no stop chosen…".
5. **Large text.** Stop, bus and my-stop cards must not overflow at 320 pt and 360 pt widths at text ×2.0. Test: Task 6, overflow guard.

---

## File Structure

| File | Responsibility |
|---|---|
| `tool/src/harbour_style.dart` (new) | Pure transform: OpenFreeMap Positron style → Harbour light/dark style |
| `tool/build_map_styles.dart` (new) | Fetches Positron, writes the two assets |
| `assets/map/harbour_light.json`, `assets/map/harbour_dark.json` (new, generated) | Committed map styles |
| `lib/ui/map/map_style.dart` (new) | Which style asset to load for a brightness and override |
| `lib/ui/map/marker_images.dart` (new) | `dart:ui` bitmaps: route badge, heading notch, your-stop disc |
| `lib/domain/map/heading_smoother.dart` (new) | Shortest-arc, rate-limited heading per vehicle (pure Dart) |
| `lib/ui/map/map_surface.dart` (new) | `MapSurface` / `MapCamera` interfaces and the MapLibre adapter |
| `lib/ui/map/map_layers.dart` (new) | Source and layer ids, install order, GeoJSON builders, `BusMarker` |
| `lib/ui/map/map_hit_test.dart` (new) | Nearest bus or stop to a tap (pure) |
| `lib/state/map_providers.dart` (new) | Map selection, route filter, per-stop arrivals |
| `lib/ui/map/stop_card.dart`, `bus_card.dart`, `my_stop_card.dart` (new) | Sheet contents |
| `lib/ui/map/route_filter_card.dart` (new) | Floating multi-select card of route badges |
| `lib/ui/map/map_view.dart` (new) | `MapViewBuilder`, `MapViewConfig`, the MapLibre-backed default |
| `lib/ui/map/map_screen.dart` (rewrite) | Layout and wiring only |
| `lib/ui/map/bus_bottom_sheet.dart`, `stop_bottom_sheet.dart` (delete) | Replaced by the cards |
| `lib/ui/shell/app_shell.dart` | Drop the map-branch bottom padding |
| `lib/ui/kit/bb_sheet.dart` | Dark-mode hairline drawn as a foreground border (carried over) |
| `lib/domain/map/bus_tracking_state.dart` | `smoothed*` renamed to `lat`/`lon`/`heading` (carried over, Task 4) |
| `lib/domain/map/bus_track.dart`, `bus_track_store.dart`, `bus_tracking_state.dart` | `schedDiffMins` for early/late (Task 5) |

---

### Task 1: "Harbour quiet" map styles

**Files:**
- Create: `tool/src/harbour_style.dart`, `tool/build_map_styles.dart`
- Create (generated): `assets/map/harbour_light.json`, `assets/map/harbour_dark.json`
- Create: `lib/ui/map/map_style.dart`
- Modify: `pubspec.yaml` (assets), `README.md` (one line on regenerating styles)
- Test: `test/tool/harbour_style_test.dart`, `test/map/map_style_test.dart`

**Interfaces:**
- Produces:
  - `HarbourPalette { name, land, water, park, road, roadCasing, label, building }`, with `HarbourPalette.light` and `HarbourPalette.dark`.
  - `Map<String, dynamic> buildHarbourStyle(Map<String, dynamic> upstream, HarbourPalette p)`.
  - `abstract final class MapStyle { static const lightAsset = 'assets/map/harbour_light.json'; static const darkAsset = 'assets/map/harbour_dark.json'; static Brightness brightnessFor(Brightness app, BBThemeMode? override); static String assetFor(Brightness app, BBThemeMode? override); }`.

- [ ] **Step 1: Write the failing transform test**

Create `test/tool/harbour_style_test.dart`:

```dart
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
        {'id': 'label_city', 'type': 'symbol', 'source': 'openmaptiles', 'source-layer': 'place', 'paint': {'text-color': '#555555', 'text-halo-color': '#ffffff'}},
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
        expect(_layer(style, 'building')['minzoom'], greaterThanOrEqualTo(16));
        expect('${style['glyphs']}', startsWith('https://tiles.openfreemap.org/'));
        expect(jsonEncode(style).toLowerCase(), isNot(contains('key=')));
      });
    }
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/tool/harbour_style_test.dart`
Expected: a compile error, because `tool/src/harbour_style.dart` doesn't exist.

- [ ] **Step 3: Write the transform**

Create `tool/src/harbour_style.dart`:

```dart
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

  static const light = HarbourPalette(
    name: 'Harbour light',
    land: '#EEF1F4',
    water: '#BFD6EA',
    park: '#DCE8DC',
    road: '#FFFFFF',
    roadCasing: '#D5DCE3',
    label: '#7A8794',
    building: '#E4E8EC',
  );

  static const dark = HarbourPalette(
    name: 'Harbour dark',
    land: '#141C25',
    water: '#0E2A40',
    park: '#16261F',
    road: '#24303C',
    roadCasing: '#2E3B48',
    label: '#7D8B99',
    building: '#19222D',
  );
}

/// Layers we draw ourselves (transit) or that are clutter for St. John's
/// (US shields).
const _dropped = {
  'railway_transit',
  'railway_transit_dashline',
  'railway_service',
  'railway_service_dashline',
  'highway-shield-us-interstate',
  'road_shield_us',
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
      if (paint.containsKey('text-color') || layer['layout'] is Map && (layer['layout'] as Map).containsKey('text-field')) {
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
```

- [ ] **Step 4: Run the transform tests**

Run: `flutter test test/tool/harbour_style_test.dart --plain-name buildHarbourStyle`
Expected: the `buildHarbourStyle` group passes. The `committed styles` group still fails, because the assets don't exist yet.

- [ ] **Step 5: Write the generator and generate the assets**

Create `tool/build_map_styles.dart`:

```dart
/// Regenerates assets/map/harbour_{light,dark}.json from OpenFreeMap's
/// Positron style (spec §3.1). Run when OpenFreeMap changes its style:
///
///   dart run tool/build_map_styles.dart
library;

import 'dart:convert';
import 'dart:io';

import 'src/harbour_style.dart';

const upstreamUrl = 'https://tiles.openfreemap.org/styles/positron';

Future<void> main() async {
  final client = HttpClient();
  try {
    final response = await (await client.getUrl(Uri.parse(upstreamUrl))).close();
    if (response.statusCode != 200) {
      stderr.writeln('GET $upstreamUrl → ${response.statusCode}');
      exitCode = 1;
      return;
    }
    final upstream = jsonDecode(await response.transform(utf8.decoder).join()) as Map<String, dynamic>;
    for (final (path, palette) in [
      ('assets/map/harbour_light.json', HarbourPalette.light),
      ('assets/map/harbour_dark.json', HarbourPalette.dark),
    ]) {
      final file = File(path)..createSync(recursive: true);
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(buildHarbourStyle(upstream, palette))}\n');
      stdout.writeln('wrote $path');
    }
  } finally {
    client.close();
  }
}
```

Run: `dart run tool/build_map_styles.dart`
Expected: `wrote assets/map/harbour_light.json` and `wrote assets/map/harbour_dark.json`.

In `pubspec.yaml`, under `flutter: assets:`, add:

```yaml
    # Harbour map styles, generated by tool/build_map_styles.dart (spec §3.1).
    - assets/map/
```

In `README.md`, in the section that lists tools or commands, add one line: `dart run tool/build_map_styles.dart` regenerates the two map styles from OpenFreeMap Positron.

- [ ] **Step 6: Write the style-selection test**

Create `test/map/map_style_test.dart`:

```dart
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no override follows the app brightness', () {
    expect(MapStyle.assetFor(Brightness.light, null), MapStyle.lightAsset);
    expect(MapStyle.assetFor(Brightness.dark, null), MapStyle.darkAsset);
    expect(MapStyle.assetFor(Brightness.dark, BBThemeMode.system), MapStyle.darkAsset);
  });

  test('an override wins over the app brightness', () {
    expect(MapStyle.assetFor(Brightness.dark, BBThemeMode.light), MapStyle.lightAsset);
    expect(MapStyle.assetFor(Brightness.light, BBThemeMode.dark), MapStyle.darkAsset);
    expect(MapStyle.brightnessFor(Brightness.light, BBThemeMode.dark), Brightness.dark);
  });
}
```

Create `lib/ui/map/map_style.dart`:

```dart
import 'package:flutter/widgets.dart';

import '../kit/kit.dart';

/// Which "Harbour quiet" style the map loads (spec §3.1): the app theme, or
/// the Settings → Map theme override (null or system = follow the app).
abstract final class MapStyle {
  static const lightAsset = 'assets/map/harbour_light.json';
  static const darkAsset = 'assets/map/harbour_dark.json';

  static Brightness brightnessFor(Brightness app, BBThemeMode? override) => switch (override) {
        BBThemeMode.light => Brightness.light,
        BBThemeMode.dark => Brightness.dark,
        _ => app,
      };

  static String assetFor(Brightness app, BBThemeMode? override) =>
      brightnessFor(app, override) == Brightness.dark ? darkAsset : lightAsset;
}
```

- [ ] **Step 7: Run all Task 1 tests, analyze, commit**

Run: `flutter test test/tool/harbour_style_test.dart test/map/map_style_test.dart && flutter analyze lib test && dart analyze tool`
Expected: all pass; no analyzer issues.

```bash
git add tool/src/harbour_style.dart tool/build_map_styles.dart assets/map/harbour_light.json assets/map/harbour_dark.json \
  lib/ui/map/map_style.dart pubspec.yaml README.md test/tool/harbour_style_test.dart test/map/map_style_test.dart
git commit -m "feat(map): Harbour quiet map styles generated from OpenFreeMap Positron"
```

---

### Task 2: Marker bitmaps (route badge, heading notch, your stop)

**Files:**
- Create: `lib/ui/map/marker_images.dart`
- Test: `test/map/marker_images_test.dart`

**Interfaces:**
- Consumes: `RouteHue`, `RoutePalette.ink`, `BBText.family`, `BBColors.light/dark.brand`.
- Produces `abstract final class MarkerImages`:
  - `static String badgeId(String label, {required bool stale, required Brightness brightness})`
  - `static String notchId(RouteHue hue, {required bool stale})`
  - `static const String myStopId = 'bb-my-stop'`
  - `static Future<Uint8List> badge({required String label, required RouteHue hue, required bool stale, required Brightness brightness, required double pixelRatio})`
  - `static Future<Uint8List> notch({required RouteHue hue, required bool stale, required double pixelRatio})`
  - `static Future<Uint8List> myStop({required Brightness brightness, required double pixelRatio})`
  - constants `badgeHeight = 22`, `badgeMinWidth = 26`, `outline = 2`, `radius = 6.5`, `notchBox = 56`, `myStopSize = 26`
  - `static Size badgeSize(String label)` (logical size, so tests and hit-testing agree)

PNG bytes are rendered at the device pixel ratio. MapLibre reads an added image at the screen scale on both platforms: iOS decodes it with `UIScreen.main.scale`, and Android uses the bitmap's default density. The parity check in "After the last task" confirms the on-screen size.

- [ ] **Step 1: Write the failing test**

Create `test/map/marker_images_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/marker_images.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Future<ui.Image> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  return (await codec.getNextFrame()).image;
}

Future<Color> _pixel(ui.Image image, int x, int y) async {
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * image.width + x) * 4;
  return Color.fromARGB(data.getUint8(i + 3), data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2));
}

void _near(Color actual, Color expected) {
  int c(double v) => (v * 255).round();
  for (final (a, e) in [(actual.r, expected.r), (actual.g, expected.g), (actual.b, expected.b), (actual.a, expected.a)]) {
    expect((c(a) - c(e)).abs(), lessThanOrEqualTo(3), reason: 'got $actual, want $expected');
  }
}

void main() {
  test('ids separate label, staleness, brightness and hue', () {
    expect(MarkerImages.badgeId('10', stale: false, brightness: Brightness.light), 'bb-badge-light-10');
    expect(MarkerImages.badgeId('10', stale: true, brightness: Brightness.dark), 'bb-badge-dark-stale-10');
    expect(MarkerImages.notchId(RouteHue.green, stale: false), 'bb-notch-green');
    expect(MarkerImages.notchId(RouteHue.green, stale: true), 'bb-notch-stale');
  });

  testWidgets('a badge is the route fill inside a white outline, at the pixel ratio', (tester) async {
    await tester.runAsync(() async {
      const pr = 2.0;
      final image = await _decode(await MarkerImages.badge(
        label: '10',
        hue: RouteHue.green,
        stale: false,
        brightness: Brightness.light,
        pixelRatio: pr,
      ));
      final size = MarkerImages.badgeSize('10');
      expect(image.width, (size.width * pr).ceil());
      expect(image.height, (size.height * pr).ceil());
      // Just inside the outline on the left edge, vertically centred: the fill.
      _near(await _pixel(image, ((MarkerImages.outline + 2) * pr).round(), image.height ~/ 2), RouteHue.green.fill);
      // On the outline at the top edge, horizontally centred: white.
      _near(await _pixel(image, image.width ~/ 2, (0.6 * pr).round()), const Color(0xFFFFFFFF));
    });
  });

  testWidgets('a stale badge is grey, a dark badge uses the dark fill', (tester) async {
    await tester.runAsync(() async {
      final stale = await _decode(await MarkerImages.badge(
          label: '10', hue: RouteHue.green, stale: true, brightness: Brightness.light, pixelRatio: 1));
      _near(await _pixel(stale, (MarkerImages.outline + 2).round(), stale.height ~/ 2), MarkerImages.staleFill);
      final dark = await _decode(await MarkerImages.badge(
          label: '10', hue: RouteHue.green, stale: false, brightness: Brightness.dark, pixelRatio: 1));
      _near(await _pixel(dark, (MarkerImages.outline + 2).round(), dark.height ~/ 2), RouteHue.green.fillDark);
    });
  });

  test('longer labels make wider badges', () {
    expect(MarkerImages.badgeSize('10A').width, greaterThan(MarkerImages.badgeSize('1').width));
    expect(MarkerImages.badgeSize('1').width, MarkerImages.badgeMinWidth + 2 * MarkerImages.outline);
  });

  testWidgets('the notch points up from the top edge and leaves the centre clear', (tester) async {
    await tester.runAsync(() async {
      const pr = 2.0;
      final image = await _decode(await MarkerImages.notch(hue: RouteHue.green, stale: false, pixelRatio: pr));
      expect(image.width, (MarkerImages.notchBox * pr).ceil());
      expect(image.height, image.width);
      _near(await _pixel(image, image.width ~/ 2, (6 * pr).round()), RouteHue.green.line);
      expect((await _pixel(image, image.width ~/ 2, image.height ~/ 2)).a, 0);
    });
  });

  testWidgets('your stop is a brand disc', (tester) async {
    await tester.runAsync(() async {
      final image = await _decode(await MarkerImages.myStop(brightness: Brightness.light, pixelRatio: 1));
      expect(image.width, MarkerImages.myStopSize.ceil());
      // Left of centre, inside the disc but outside the star: brand blue.
      _near(await _pixel(image, 5, image.height ~/ 2), BBColors.light.brand);
    });
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/map/marker_images_test.dart`
Expected: a compile error, because `marker_images.dart` doesn't exist.

- [ ] **Step 3: Implement the bitmaps**

Create `lib/ui/map/marker_images.dart`:

```dart
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../kit/kit.dart';

/// Bitmaps the map draws (spec §3.2): one route badge per label (the board's
/// badge: radius 6.5, route fill, ink number, 2 px white outline), one heading
/// notch per hue, and your stop's brand disc with a white star. Rendered at
/// the device pixel ratio; MapLibre reads added images at the screen scale.
abstract final class MarkerImages {
  static const double badgeHeight = 22;
  static const double badgeMinWidth = 26;
  static const double outline = 2;
  static const double radius = 6.5;
  static const double fontSize = 12.5;

  /// Square box the notch is drawn in; its centre sits on the bus, so the
  /// triangle on the top edge clears even a three-character badge when rotated.
  static const double notchBox = 56;
  static const double myStopSize = 26;
  static const String myStopId = 'bb-my-stop';

  static const Color staleFill = Color(0xFFC4CBD2);
  static const Color staleInk = Color(0xFF5A6674);
  static const Color staleNotch = Color(0xFF9AA4AE);
  static const Color _white = Color(0xFFFFFFFF);

  static String badgeId(String label, {required bool stale, required Brightness brightness}) =>
      'bb-badge-${brightness.name}-${stale ? 'stale-' : ''}$label';

  static String notchId(RouteHue hue, {required bool stale}) => 'bb-notch-${stale ? 'stale' : hue.name}';

  static TextPainter _label(String label, Color color) => TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(fontFamily: BBText.family, fontSize: fontSize, fontWeight: FontWeight.w800, color: color),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();

  /// Logical size of a badge including its outline.
  static Size badgeSize(String label) {
    final text = _label(label, RoutePalette.ink);
    final inner = math.max(badgeMinWidth, text.width + 10);
    return Size(inner + 2 * outline, badgeHeight + 2 * outline);
  }

  static Future<Uint8List> badge({
    required String label,
    required RouteHue hue,
    required bool stale,
    required Brightness brightness,
    required double pixelRatio,
  }) {
    final size = badgeSize(label);
    return _render(size, pixelRatio, (canvas) {
      final outer = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(radius + outline));
      canvas.drawRRect(outer, Paint()..color = _white);
      final inner = RRect.fromRectAndRadius(
        Rect.fromLTWH(outline, outline, size.width - 2 * outline, badgeHeight),
        const Radius.circular(radius),
      );
      canvas.drawRRect(inner, Paint()..color = stale ? staleFill : hue.fillFor(brightness));
      final text = _label(label, stale ? staleInk : RoutePalette.ink);
      text.paint(canvas, Offset((size.width - text.width) / 2, (size.height - text.height) / 2));
    });
  }

  static Future<Uint8List> notch({required RouteHue hue, required bool stale, required double pixelRatio}) {
    const size = Size.square(notchBox);
    return _render(size, pixelRatio, (canvas) {
      const mid = notchBox / 2;
      final path = Path()
        ..moveTo(mid, 1.5)
        ..lineTo(mid + 6, 11)
        ..lineTo(mid - 6, 11)
        ..close();
      canvas.drawPath(path, Paint()..color = stale ? staleNotch : hue.line);
      canvas.drawPath(
        path,
        Paint()
          ..color = _white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeJoin = StrokeJoin.round,
      );
    });
  }

  static Future<Uint8List> myStop({required Brightness brightness, required double pixelRatio}) {
    const size = Size.square(myStopSize);
    final brand = brightness == Brightness.dark ? BBColors.dark.brand : BBColors.light.brand;
    return _render(size, pixelRatio, (canvas) {
      const c = Offset(myStopSize / 2, myStopSize / 2);
      canvas.drawCircle(c, myStopSize / 2, Paint()..color = _white);
      canvas.drawCircle(c, myStopSize / 2 - 2, Paint()..color = brand);
      canvas.drawPath(_star(c, 6.5, 2.8), Paint()..color = _white);
    });
  }

  static Path _star(Offset c, double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? outer : inner;
      final a = -math.pi / 2 + i * math.pi / 5;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }

  static Future<Uint8List> _render(Size size, double pixelRatio, void Function(Canvas) draw) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(pixelRatio);
    draw(canvas);
    final picture = recorder.endRecording();
    final image = await picture.toImage((size.width * pixelRatio).ceil(), (size.height * pixelRatio).ceil());
    picture.dispose();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return bytes!.buffer.asUint8List();
  }
}
```

- [ ] **Step 4: Run the tests**

Run: `flutter test test/map/marker_images_test.dart`
Expected: PASS. Test fonts may render the label with the Ahem test font, but the sampled pixels avoid the text, so the colour checks don't depend on it.

- [ ] **Step 5: Analyze and commit**

```bash
flutter analyze lib test
git add lib/ui/map/marker_images.dart test/map/marker_images_test.dart
git commit -m "feat(map): route-badge, heading-notch and your-stop marker bitmaps"
```

---

### Task 3: Heading smoother

**Files:**
- Create: `lib/domain/map/heading_smoother.dart`
- Test: `test/map/heading_smoother_test.dart`

**Interfaces:**
- Produces:
  - `class HeadingSmoother { static const double maxDegreesPerSecond = 180; static const Duration snapGap = Duration(seconds: 2); double smooth(String vehicleId, double target, DateTime now); void prune(Set<String> keep); static double shortestDelta(double from, double to); }`

This closes the item parked in the 3b-1 ledger: "heading tween / shortest-arc rotation → Phase 3b-2 marker layer". The renderer's heading jumps at shape vertices and on trip changes. Without smoothing, the notch would spin the long way round.

- [ ] **Step 1: Write the failing test**

Create `test/map/heading_smoother_test.dart`:

```dart
import 'package:busboard_nl/domain/map/heading_smoother.dart';
import 'package:flutter_test/flutter_test.dart';

final _t0 = DateTime(2026, 10, 5, 12);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));

void main() {
  test('shortestDelta takes the short way round', () {
    expect(HeadingSmoother.shortestDelta(350, 10), 20);
    expect(HeadingSmoother.shortestDelta(10, 350), -20);
    expect(HeadingSmoother.shortestDelta(0, 180), 180);
    expect(HeadingSmoother.shortestDelta(90, 90), 0);
  });

  test('the first frame takes the target', () {
    expect(HeadingSmoother().smooth('a', 270, _t0), 270);
  });

  test('350° → 10° turns through north, never through south', () {
    final s = HeadingSmoother()..smooth('a', 350, _t0);
    for (var ms = 16; ms <= 400; ms += 16) {
      final h = s.smooth('a', 10, _at(ms));
      expect(h < 30 || h > 330, isTrue, reason: 'heading $h at $ms ms');
    }
    expect(s.smooth('a', 10, _at(416)), 10);
  });

  test('turns at most 180° per second', () {
    final s = HeadingSmoother()..smooth('a', 0, _t0);
    expect(s.smooth('a', 90, _at(250)), closeTo(45, 1e-9));
    expect(s.smooth('a', 90, _at(500)), closeTo(90, 1e-9));
  });

  test('snaps after a gap of more than 2 s, and holds at the same time', () {
    final s = HeadingSmoother()..smooth('a', 0, _t0);
    expect(s.smooth('a', 180, _at(2500)), 180);
    expect(s.smooth('a', 0, _at(2500)), 180);
  });

  test('normalises targets and prunes vehicles that are gone', () {
    final s = HeadingSmoother();
    expect(s.smooth('a', -90, _t0), 270);
    expect(s.smooth('b', 450, _t0), 90);
    s.prune({'b'});
    expect(s.smooth('a', 10, _at(16)), 10, reason: 'a was pruned, so this is a first frame');
  });
}
```

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/map/heading_smoother_test.dart`
Expected: a compile error, because `heading_smoother.dart` doesn't exist.

- [ ] **Step 3: Implement**

Create `lib/domain/map/heading_smoother.dart`:

```dart
/// Turns each drawn heading toward the renderer's heading the short way round,
/// at most [maxDegreesPerSecond], so a bus's heading notch never spins through
/// 180° at a shape vertex or after a trip change. Snaps on the first frame and
/// after a render gap over [snapGap]. One instance per map; call [prune] with
/// the vehicles still drawn.
class HeadingSmoother {
  static const double maxDegreesPerSecond = 180;
  static const Duration snapGap = Duration(seconds: 2);

  final _state = <String, ({double heading, DateTime at})>{};

  double smooth(String vehicleId, double target, DateTime now) {
    final goal = _norm(target);
    final prev = _state[vehicleId];
    double out;
    if (prev == null) {
      out = goal;
    } else {
      final dt = now.difference(prev.at);
      if (dt <= Duration.zero) return prev.heading;
      if (dt > snapGap) {
        out = goal;
      } else {
        final diff = shortestDelta(prev.heading, goal);
        final step = maxDegreesPerSecond * dt.inMicroseconds / Duration.microsecondsPerSecond;
        out = diff.abs() <= step ? goal : _norm(prev.heading + step * diff.sign);
      }
    }
    _state[vehicleId] = (heading: out, at: now);
    return out;
  }

  void prune(Set<String> keep) => _state.removeWhere((id, _) => !keep.contains(id));

  /// Signed turn from [from] to [to] in (-180, 180].
  static double shortestDelta(double from, double to) {
    final d = (to - from) % 360;
    return d > 180 ? d - 360 : d;
  }

  static double _norm(double heading) => heading % 360;
}
```

- [ ] **Step 4: Run, analyze, commit**

Run: `flutter test test/map/heading_smoother_test.dart && flutter analyze lib test`
Expected: PASS; no issues.

```bash
git add lib/domain/map/heading_smoother.dart test/map/heading_smoother_test.dart
git commit -m "feat(map): shortest-arc heading smoothing for bus notches"
```

---

### Task 4: Map surface, layers and hit-testing

**Files:**
- Create: `lib/ui/map/map_surface.dart`, `lib/ui/map/map_layers.dart`, `lib/ui/map/map_hit_test.dart`
- Modify: `lib/domain/map/bus_tracking_state.dart` and every use of `smoothedLat` / `smoothedLon` / `smoothedHeading` (rename, Step 0)
- Test: `test/map/map_layers_test.dart`, `test/map/map_hit_test_test.dart`, `test/map/support/fake_map_surface.dart`

**Interfaces:**
- Consumes:
  - `MarkerImages` (Task 2), `HeadingSmoother` (Task 3);
  - `RenderedBus` from `lib/domain/map/delayed_track_renderer.dart`;
  - `BusTrackingState`, `BusStatus`, `StopInfo`, `RoutePalette`.
- Produces:
  - `abstract interface class MapSurface`, with:
    - `addImage(String, Uint8List)`, `addGeoJsonSource(String, Map<String, dynamic>)`, `setGeoJsonSource(String, Map<String, dynamic>)`;
    - `addCircleLayer(String sourceId, String layerId, CircleLayerProperties, {double? minzoom})`;
    - `addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties, {double? minzoom})`.
  - `abstract interface class MapCamera`, with:
    - `double get zoom`;
    - `Future<void> moveTo(LatLng target, double zoom, {required bool animate})`;
    - `Future<LatLng?> myLocation()`.
  - `class MapLibreSurface implements MapSurface, MapCamera` (wraps `MapLibreMapController`).
  - `class BusMarker { vehicleId, lat, lon, heading, label, hue, stale }`.
  - `List<BusMarker> busMarkers({required Map<String, BusTrackingState> tracking, required Map<String, RenderedBus> drawn, required Set<int> routeFilter, required HeadingSmoother headings, required DateTime now})`.
  - `String busLabel(BusTrackingState s)`.
  - `class MapLayers`, with:
    - `MapLayers(MapSurface surface, {required Brightness brightness, required double pixelRatio})`;
    - `Future<void> install({required Iterable<StopInfo> stops})`;
    - `Future<void> updateBuses(List<BusMarker> markers)`;
    - `Future<void> updateMyStop(StopInfo? stop)`;
    - the static source and layer ids listed in the code below.
  - Hit-testing in `map_hit_test.dart`:
    - `double tapRadiusMeters(double zoom)`;
    - `String? nearestBus(LatLng tap, double radius, List<BusMarker> drawn)`;
    - `StopInfo? nearestStop(LatLng tap, double radius, Iterable<StopInfo> stops)`.
  - `BusTrackingState.lat`, `.lon` and `.heading`, renamed from `smoothedLat`, `smoothedLon` and `smoothedHeading`. The values are unchanged. Every later task uses the new names.

- [ ] **Step 0: Rename `smoothed*` (carried over from the 3b-1 ledger, Task 6 M6)**

These fields are now the latest fix's snapped position (raw when off-route) and its feed heading; nothing smooths them. In `lib/domain/map/bus_tracking_state.dart`, rename the fields and constructor parameters:
- `smoothedLat` → `lat`
- `smoothedLon` → `lon`
- `smoothedHeading` → `heading`

Update `fromTrack` and the class doc. Update every reference in `lib/` and `test/`. Then run `grep -rn smoothed lib test`, which must print nothing, and `flutter test && flutter analyze lib test`, which must be green. Commit:

```bash
git add -u lib test
git commit -m "refactor(map): BusTrackingState smoothed* → lat/lon/heading"
```

Check `git status` first: `analysis_options.yaml` must not be staged. `git add -u` stages only tracked changes, so check it isn't modified-and-staged.

- [ ] **Step 1: Write the fake surface**

Create `test/map/support/fake_map_surface.dart`:

```dart
import 'dart:typed_data';

import 'package:busboard_nl/ui/map/map_surface.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// Records every call the map layers make, in order.
class FakeMapSurface implements MapSurface, MapCamera {
  final calls = <String>[];
  final images = <String, Uint8List>{};
  final sources = <String, Map<String, dynamic>>{};
  final layers = <String, Object>{};
  final layerMinZoom = <String, double?>{};
  final moves = <(LatLng, double, bool)>[];
  LatLng? location;
  @override
  double zoom = 13;

  @override
  Future<void> addImage(String name, Uint8List bytes) async {
    calls.add('image $name');
    images[name] = bytes;
  }

  @override
  Future<void> addGeoJsonSource(String id, Map<String, dynamic> data) async {
    calls.add('source $id');
    sources[id] = data;
  }

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) async {
    calls.add('set $id');
    sources[id] = data;
  }

  @override
  Future<void> addCircleLayer(String sourceId, String layerId, CircleLayerProperties p, {double? minzoom}) async {
    calls.add('layer $layerId');
    layers[layerId] = p;
    layerMinZoom[layerId] = minzoom;
  }

  @override
  Future<void> addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties p, {double? minzoom}) async {
    calls.add('layer $layerId');
    layers[layerId] = p;
    layerMinZoom[layerId] = minzoom;
  }

  @override
  Future<void> moveTo(LatLng target, double zoom, {required bool animate}) async => moves.add((target, zoom, animate));

  @override
  Future<LatLng?> myLocation() async => location;

  List<Map<String, dynamic>> features(String source) =>
      (sources[source]!['features'] as List).cast<Map<String, dynamic>>();
}
```

- [ ] **Step 2: Write the failing layer and hit-test tests**

Create `test/map/map_layers_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/domain/map/delayed_track_renderer.dart';
import 'package:busboard_nl/domain/map/heading_smoother.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:busboard_nl/ui/map/marker_images.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_map_surface.dart';

final _now = DateTime(2026, 10, 5, 12);

BusTrackingState _bus(String id, {int route = 10, String routeRun = 'Rt 10', BusStatus status = BusStatus.active, double lat = 47.56, double lon = -52.71}) =>
    BusTrackingState(
      routeRun: routeRun,
      vehicleId: id,
      routeNumber: route,
      headsign: 'Downtown',
      lat: lat,
      lon: lon,
      heading: 90,
      speedKmh: 30,
      lastGpsTime: _now,
      status: status,
      lastUpdateTime: _now,
    );

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

void main() {
  group('busMarkers', () {
    test('uses the drawn position and heading, falling back to the latest fix', () {
      final markers = busMarkers(
        tracking: {'a': _bus('a'), 'b': _bus('b', lat: 47.5)},
        drawn: {'a': const RenderedBus(vehicleId: 'a', lat: 47.6, lon: -52.7, heading: 45)},
        routeFilter: const {},
        headings: HeadingSmoother(),
        now: _now,
      );
      final a = markers.firstWhere((m) => m.vehicleId == 'a');
      expect((a.lat, a.lon, a.heading), (47.6, -52.7, 45));
      final b = markers.firstWhere((m) => m.vehicleId == 'b');
      expect((b.lat, b.heading), (47.5, 90));
    });

    test('the route filter keeps only chosen routes; empty means all', () {
      final tracking = {'a': _bus('a', route: 10), 'b': _bus('b', route: 2)};
      List<String> ids(Set<int> filter) => [
            for (final m in busMarkers(tracking: tracking, drawn: const {}, routeFilter: filter, headings: HeadingSmoother(), now: _now)) m.vehicleId,
          ];
      expect(ids(const {}), unorderedEquals(['a', 'b']));
      expect(ids(const {2}), ['b']);
    });

    test('stale buses stay on the map, flagged stale', () {
      final markers = busMarkers(
        tracking: {'a': _bus('a', status: BusStatus.stale)},
        drawn: const {},
        routeFilter: const {},
        headings: HeadingSmoother(),
        now: _now,
      );
      expect(markers.single.stale, isTrue);
    });

    test('label falls back to routeRun, then "?"', () {
      expect(busLabel(_bus('a', route: 10)), '10');
      expect(busLabel(_bus('a', route: 0, routeRun: 'Rt 10A')), '10A');
      expect(busLabel(_bus('a', route: 0, routeRun: '')), '?');
      expect(busMarkers(tracking: {'a': _bus('a', route: 0, routeRun: 'Rt 10A')}, drawn: const {}, routeFilter: const {}, headings: HeadingSmoother(), now: _now).single.hue,
          RoutePalette.ofName('10A'));
    });
  });

  group('MapLayers', () {
    testWidgets('install adds images, sources and layers bottom to top', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        await MapLayers(surface, brightness: Brightness.light, pixelRatio: 1).install(stops: const [_mun]);
        final layerOrder = [for (final c in surface.calls) if (c.startsWith('layer ')) c.substring(6)];
        expect(layerOrder, [MapLayers.stopsLayer, MapLayers.myStopLayer, MapLayers.notchLayer, MapLayers.badgeLayer]);
        expect(surface.images.keys, contains(MarkerImages.myStopId));
        expect(surface.layerMinZoom[MapLayers.stopsLayer], MapLayers.stopsMinZoom);
        expect(surface.layerMinZoom[MapLayers.myStopLayer], isNull, reason: 'your stop shows at every zoom');
        expect(surface.features(MapLayers.stopsSource).single['properties']['stopId'], '1150');
      });
    });

    testWidgets('images are registered once per id', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final markers = busMarkers(
          tracking: {'a': _bus('a'), 'b': _bus('b'), 'c': _bus('c')},
          drawn: const {},
          routeFilter: const {},
          headings: HeadingSmoother(),
          now: _now,
        );
        await layers.updateBuses(markers);
        await layers.updateBuses(markers);
        final imageCalls = surface.calls.where((c) => c.startsWith('image bb-badge') || c.startsWith('image bb-notch'));
        expect(imageCalls, ['image ${MarkerImages.badgeId('10', stale: false, brightness: Brightness.light)}', 'image ${MarkerImages.notchId(RoutePalette.of(10), stale: false)}']);
        final f = surface.features(MapLayers.busesSource);
        expect(f, hasLength(3));
        expect(f.first['properties']['badge'], MarkerImages.badgeId('10', stale: false, brightness: Brightness.light));
        expect(f.first['properties']['heading'], 90);
      });
    });

    testWidgets('install after a style reload re-adds images and layers', (tester) async {
      await tester.runAsync(() async {
        final first = FakeMapSurface();
        final layers = MapLayers(first, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        final markers = busMarkers(tracking: {'a': _bus('a')}, drawn: const {}, routeFilter: const {}, headings: HeadingSmoother(), now: _now);
        await layers.updateBuses(markers);
        first.calls.clear();
        // A style reload drops every image and layer on the native side.
        await layers.install(stops: const []);
        await layers.updateBuses(markers);
        expect(first.calls, contains('layer ${MapLayers.badgeLayer}'));
        expect(first.calls, contains('image ${MarkerImages.badgeId('10', stale: false, brightness: Brightness.light)}'));
      });
    });

    testWidgets('your stop is one feature, or none', (tester) async {
      await tester.runAsync(() async {
        final surface = FakeMapSurface();
        final layers = MapLayers(surface, brightness: Brightness.light, pixelRatio: 1);
        await layers.install(stops: const []);
        await layers.updateMyStop(_mun);
        expect(surface.features(MapLayers.myStopSource).single['geometry']['coordinates'], [-52.73, 47.57]);
        await layers.updateMyStop(null);
        expect(surface.features(MapLayers.myStopSource), isEmpty);
      });
    });
  });
}
```

Create `test/map/map_hit_test_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_hit_test.dart';
import 'package:busboard_nl/ui/map/map_layers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

BusMarker _m(String id, double lat, double lon) =>
    BusMarker(vehicleId: id, lat: lat, lon: lon, heading: 0, label: '10', hue: RouteHue.green, stale: false);

void main() {
  test('tap radius shrinks as you zoom in', () {
    expect(tapRadiusMeters(13), 200);
    expect(tapRadiusMeters(15), 50);
    expect(tapRadiusMeters(10), 200, reason: 'clamped below zoom 13');
  });

  test('nearestBus picks the closest drawn bus within the radius', () {
    final drawn = [_m('far', 47.5700, -52.7300), _m('near', 47.5601, -52.7100)];
    expect(nearestBus(const LatLng(47.5600, -52.7100), 50, drawn), 'near');
    expect(nearestBus(const LatLng(47.6000, -52.7100), 50, drawn), isNull);
  });

  test('nearestStop picks the closest stop within the radius', () {
    const a = StopInfo(stopId: 'a', stopName: 'A', stopLat: 47.5600, stopLon: -52.7100);
    const b = StopInfo(stopId: 'b', stopName: 'B', stopLat: 47.5610, stopLon: -52.7100);
    expect(nearestStop(const LatLng(47.5608, -52.7100), 200, const [a, b])?.stopId, 'b');
    expect(nearestStop(const LatLng(47.6, -52.7), 50, const [a, b]), isNull);
  });
}
```

- [ ] **Step 3: Run them and watch them fail**

Run: `flutter test test/map/map_layers_test.dart test/map/map_hit_test_test.dart`
Expected: compile errors, because `map_surface.dart`, `map_layers.dart` and `map_hit_test.dart` don't exist.

- [ ] **Step 4: Implement the surface**

Create `lib/ui/map/map_surface.dart`:

```dart
import 'dart:typed_data';

import 'package:maplibre_gl/maplibre_gl.dart';

/// The slice of MapLibre the map layers use, so layer setup and updates are
/// tested against a fake. [MapLibreSurface] adapts a live controller.
abstract interface class MapSurface {
  Future<void> addImage(String name, Uint8List bytes);
  Future<void> addGeoJsonSource(String id, Map<String, dynamic> data);
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data);
  Future<void> addCircleLayer(String sourceId, String layerId, CircleLayerProperties properties, {double? minzoom});
  Future<void> addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties properties, {double? minzoom});
}

/// Camera moves the screen makes (my location, your stop).
abstract interface class MapCamera {
  double get zoom;
  Future<void> moveTo(LatLng target, double zoom, {required bool animate});
  Future<LatLng?> myLocation();
}

class MapLibreSurface implements MapSurface, MapCamera {
  MapLibreSurface(this.controller);

  final MapLibreMapController controller;

  @override
  Future<void> addImage(String name, Uint8List bytes) => controller.addImage(name, bytes);

  @override
  Future<void> addGeoJsonSource(String id, Map<String, dynamic> data) => controller.addGeoJsonSource(id, data);

  @override
  Future<void> setGeoJsonSource(String id, Map<String, dynamic> data) => controller.setGeoJsonSource(id, data);

  @override
  Future<void> addCircleLayer(String sourceId, String layerId, CircleLayerProperties properties, {double? minzoom}) =>
      controller.addCircleLayer(sourceId, layerId, properties, minzoom: minzoom, enableInteraction: false);

  @override
  Future<void> addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties properties, {double? minzoom}) =>
      controller.addSymbolLayer(sourceId, layerId, properties, minzoom: minzoom, enableInteraction: false);

  @override
  double get zoom => controller.cameraPosition?.zoom ?? 13;

  @override
  Future<void> moveTo(LatLng target, double zoom, {required bool animate}) async {
    final update = CameraUpdate.newLatLngZoom(target, zoom);
    if (animate) {
      await controller.animateCamera(update);
    } else {
      await controller.moveCamera(update);
    }
  }

  @override
  Future<LatLng?> myLocation() => controller.requestMyLocationLatLng();
}
```

`enableInteraction: false` stops MapLibre's native feature taps. The screen hit-tests every tap itself in Task 7, which ends the Android `onFeatureTapped` versus `onMapClick` split the old screen had to handle. If `addSymbolLayer` has no `enableInteraction` parameter in 0.27.1, drop that argument from both calls and keep the `onFeatureTapped` forwarding described in Task 7.

- [ ] **Step 5: Implement layers and hit-testing**

Create `lib/ui/map/map_layers.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/map/bus_tracking_state.dart';
import '../../domain/map/delayed_track_renderer.dart';
import '../../domain/map/heading_smoother.dart';
import '../kit/kit.dart';
import 'map_surface.dart';
import 'marker_images.dart';

/// One bus as the map draws it this frame.
class BusMarker {
  const BusMarker({
    required this.vehicleId,
    required this.lat,
    required this.lon,
    required this.heading,
    required this.label,
    required this.hue,
    required this.stale,
  });

  final String vehicleId;
  final double lat;
  final double lon;
  final double heading;
  final String label;
  final RouteHue hue;
  final bool stale;
}

/// The number on a bus badge: the route number, else the route from
/// "Rt 10A"-style routeRun, else "?".
String busLabel(BusTrackingState s) {
  if (s.routeNumber > 0) return '${s.routeNumber}';
  final run = s.routeRun.replaceFirst(RegExp(r'^Rt\s*'), '').split('-').first.trim();
  return run.isEmpty ? '?' : run;
}

/// Markers for this frame. The renderer's drawn position wins; a bus it has
/// not drawn yet uses its latest fix. Stale buses stay, flagged for a grey
/// badge (spec §3.2). An empty [routeFilter] shows every route.
List<BusMarker> busMarkers({
  required Map<String, BusTrackingState> tracking,
  required Map<String, RenderedBus> drawn,
  required Set<int> routeFilter,
  required HeadingSmoother headings,
  required DateTime now,
}) {
  final out = <BusMarker>[];
  for (final MapEntry(key: id, value: s) in tracking.entries) {
    if (routeFilter.isNotEmpty && !routeFilter.contains(s.routeNumber)) continue;
    final pos = drawn[id];
    final label = busLabel(s);
    out.add(BusMarker(
      vehicleId: id,
      lat: pos?.lat ?? s.lat,
      lon: pos?.lon ?? s.lon,
      heading: headings.smooth(id, pos?.heading ?? s.heading, now),
      label: label,
      hue: RoutePalette.ofName(label),
      stale: s.status == BusStatus.stale,
    ));
  }
  headings.prune({for (final m in out) m.vehicleId});
  return out;
}

Map<String, dynamic> _collection(List<Map<String, dynamic>> features) => {'type': 'FeatureCollection', 'features': features};

Map<String, dynamic> _point(double lat, double lon, Map<String, dynamic> properties, {String? id}) => {
      'type': 'Feature',
      'id': ?id,
      'geometry': {
        'type': 'Point',
        'coordinates': [lon, lat],
      },
      'properties': properties,
    };

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// Sources, layers and marker images of the Harbour map (spec §3.2), bottom to
/// top: stops, your stop, bus notches, bus badges. [install] runs after every
/// style load (a style switch clears everything natively); updates are cheap
/// GeoJSON swaps that register any new marker image first.
class MapLayers {
  MapLayers(this.surface, {required this.brightness, required this.pixelRatio});

  final MapSurface surface;
  final Brightness brightness;
  final double pixelRatio;

  static const stopsSource = 'bb-stops';
  static const stopsLayer = 'bb-stops-layer';
  static const myStopSource = 'bb-my-stop';
  static const myStopLayer = 'bb-my-stop-layer';
  static const busesSource = 'bb-buses';
  static const notchLayer = 'bb-bus-notch';
  static const badgeLayer = 'bb-bus-badge';
  static const double stopsMinZoom = 14.5;

  final _images = <String>{};

  Future<void> install({required Iterable<StopInfo> stops}) async {
    _images.clear();
    await surface.addImage(MarkerImages.myStopId, await MarkerImages.myStop(brightness: brightness, pixelRatio: pixelRatio));
    _images.add(MarkerImages.myStopId);

    await surface.addGeoJsonSource(stopsSource, _collection([
      for (final s in stops) _point(s.stopLat, s.stopLon, {'stopId': s.stopId}),
    ]));
    await surface.addCircleLayer(
      stopsSource,
      stopsLayer,
      CircleLayerProperties(
        circleRadius: 3.5,
        circleColor: '#FFFFFF',
        circleStrokeWidth: 1.5,
        circleStrokeColor: _hex(RoutePalette.ink),
      ),
      minzoom: stopsMinZoom,
    );

    await surface.addGeoJsonSource(myStopSource, _collection(const []));
    await surface.addSymbolLayer(
      myStopSource,
      myStopLayer,
      const SymbolLayerProperties(iconImage: MarkerImages.myStopId, iconAllowOverlap: true, iconIgnorePlacement: true),
    );

    await surface.addGeoJsonSource(busesSource, _collection(const []));
    await surface.addSymbolLayer(
      busesSource,
      notchLayer,
      const SymbolLayerProperties(
        iconImage: [Expressions.get, 'notch'],
        iconRotate: [Expressions.get, 'heading'],
        iconRotationAlignment: 'map',
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
      ),
    );
    await surface.addSymbolLayer(
      busesSource,
      badgeLayer,
      const SymbolLayerProperties(
        iconImage: [Expressions.get, 'badge'],
        iconAllowOverlap: true,
        iconIgnorePlacement: true,
        symbolSortKey: [Expressions.get, 'sort'],
      ),
    );
  }

  Future<void> updateBuses(List<BusMarker> markers) async {
    final features = <Map<String, dynamic>>[];
    for (final m in markers) {
      final badge = MarkerImages.badgeId(m.label, stale: m.stale, brightness: brightness);
      if (_images.add(badge)) {
        await surface.addImage(
          badge,
          await MarkerImages.badge(label: m.label, hue: m.hue, stale: m.stale, brightness: brightness, pixelRatio: pixelRatio),
        );
      }
      final notch = MarkerImages.notchId(m.hue, stale: m.stale);
      if (_images.add(notch)) {
        await surface.addImage(notch, await MarkerImages.notch(hue: m.hue, stale: m.stale, pixelRatio: pixelRatio));
      }
      features.add(_point(m.lat, m.lon, {
        'vehicleId': m.vehicleId,
        'badge': badge,
        'notch': notch,
        'heading': m.heading,
        'sort': m.stale ? 0 : 1,
      }, id: m.vehicleId));
    }
    await surface.setGeoJsonSource(busesSource, _collection(features));
  }

  Future<void> updateMyStop(StopInfo? stop) => surface.setGeoJsonSource(
        myStopSource,
        _collection([if (stop != null) _point(stop.stopLat, stop.stopLon, {'stopId': stop.stopId})]),
      );
}
```

The `'id': ?id` null-aware map entry needs Dart 3.8 or later, and the project is on 3.13. The analyzer accepts it.

Create `lib/ui/map/map_hit_test.dart`:

```dart
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/location/nearest_stop_service.dart';
import 'map_layers.dart';

/// Tap radius in metres: ~200 m at zoom 13, halving per zoom level to ~6 m at 18.
double tapRadiusMeters(double zoom) => 200.0 / (1 << (zoom - 13).clamp(0, 5).toInt());

double _dist(LatLng a, double lat, double lon) =>
    NearestStopService.haversineDistance(a.latitude, a.longitude, lat, lon);

/// The vehicle ID of the drawn bus closest to [tap] within [radius] metres.
String? nearestBus(LatLng tap, double radius, List<BusMarker> drawn) {
  String? best;
  var bestDist = radius;
  for (final m in drawn) {
    final d = _dist(tap, m.lat, m.lon);
    if (d < bestDist) {
      best = m.vehicleId;
      bestDist = d;
    }
  }
  return best;
}

StopInfo? nearestStop(LatLng tap, double radius, Iterable<StopInfo> stops) {
  StopInfo? best;
  var bestDist = radius;
  for (final s in stops) {
    final d = _dist(tap, s.stopLat, s.stopLon);
    if (d < bestDist) {
      best = s;
      bestDist = d;
    }
  }
  return best;
}
```

- [ ] **Step 6: Run, analyze, commit**

Run: `flutter test test/map/map_layers_test.dart test/map/map_hit_test_test.dart && flutter analyze lib test`
Expected: PASS; no issues.

```bash
git add lib/ui/map/map_surface.dart lib/ui/map/map_layers.dart lib/ui/map/map_hit_test.dart \
  test/map/map_layers_test.dart test/map/map_hit_test_test.dart test/map/support/fake_map_surface.dart
git commit -m "feat(map): map layers behind a testable MapSurface; badge+notch bus markers"
```

---

### Task 5: Map state — selection, route filter, per-stop arrivals, bus delay

**Files:**
- Create: `lib/state/map_providers.dart`
- Modify:
  - `lib/state/providers.dart`: delete the unused `arrivalsProvider` and the now-unused imports it leaves.
  - `lib/domain/map/bus_track.dart`: add `TrackFix.schedDiffMins`.
  - `lib/domain/map/bus_track_store.dart`: set `schedDiffMins`.
  - `lib/domain/map/bus_tracking_state.dart`: add `schedDiffMins` and pass it through `fromTrack`.
- Test: `test/state/map_providers_test.dart`, plus an added case in `test/map/bus_tracking_state_test.dart`

**Interfaces:**
- Produces:
  - Map selection:
    - `sealed class MapSelection`, with `StopSelection(String stopId)` and `BusSelection(String vehicleId)` (value equality).
    - `final mapSelectionProvider = NotifierProvider<MapSelectionNotifier, MapSelection?>`.
    - `MapSelectionNotifier.select(MapSelection?)` and `.clear()`.
  - Route filter:
    - `final mapRouteFilterProvider = NotifierProvider<RouteFilterNotifier, Set<int>>`.
    - `RouteFilterNotifier.toggle(int route)` and `.showAll()`.
    - An empty set means all routes.
  - Per-stop arrivals:
    - `final stopArrivalsProvider = FutureProvider.autoDispose.family<List<ArrivalRow>, String>`.
    - It re-fetches every `refreshIntervalSeconds` while watched.
  - Bus delay:
    - `int? TrackFix.schedDiffMins` and `int? BusTrackingState.schedDiffMins`.
    - Positive means ahead (early), negative means behind (late).
    - It is null when the feed reported no delay.

- [ ] **Step 1: Write the failing tests**

Create `test/state/map_providers_test.dart`:

```dart
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/data/realtime/metrobus_mobile_api.dart';
import 'package:busboard_nl/data/realtime/timetrack_api.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTimeTrack extends TimeTrackApi {
  @override
  Future<TimeTrackFetchResult> fetchVehiclesResult() async =>
      TimeTrackFetchResult.success(const [], source: LiveDataSource.gtfsRealtime);
}

class _FakeMobile extends MetrobusMobileApi {
  final asked = <String>[];
  @override
  Future<MetrobusDeparturesResult> fetchDeparturesResult(String stopId) async {
    asked.add(stopId);
    return MetrobusDeparturesResult.failure();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('route filter: empty is all; toggling adds and removes; showAll clears', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(mapRouteFilterProvider.notifier);
    expect(c.read(mapRouteFilterProvider), isEmpty);
    n.toggle(10);
    expect(c.read(mapRouteFilterProvider), {10});
    n.toggle(2);
    expect(c.read(mapRouteFilterProvider), {10, 2});
    n.toggle(10);
    expect(c.read(mapRouteFilterProvider), {2});
    n.showAll();
    expect(c.read(mapRouteFilterProvider), isEmpty);
  });

  test('selection holds a stop or a bus, by value', () {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(mapSelectionProvider.notifier).select(const StopSelection('1150'));
    expect(c.read(mapSelectionProvider), const StopSelection('1150'));
    c.read(mapSelectionProvider.notifier).select(const BusSelection('2573'));
    expect(c.read(mapSelectionProvider), const BusSelection('2573'));
    expect(const BusSelection('2573') == const BusSelection('2574'), isFalse);
    c.read(mapSelectionProvider.notifier).clear();
    expect(c.read(mapSelectionProvider), isNull);
  });

  test('stop arrivals ask the stop-prediction feed for that stop', () async {
    final mobile = _FakeMobile();
    final c = ProviderContainer(overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => GtfsRepository()),
      timetrackApiProvider.overrideWithValue(_FakeTimeTrack()),
      metrobusMobileApiProvider.overrideWithValue(mobile),
    ]);
    addTearDown(c.dispose);
    await c.read(gtfsRepositoryProvider.future);
    c.listen(stopArrivalsProvider('1150'), (_, _) {});
    expect(await c.read(stopArrivalsProvider('1150').future), isEmpty);
    expect(mobile.asked, ['1150']);
  });
}
```

In `test/map/bus_tracking_state_test.dart`, add a test that builds a track whose latest fix has `schedDiffMins: -2` and asserts `BusTrackingState.fromTrack(track, stale: false).schedDiffMins == -2`. Construct the fix the same way the file's existing tests do.

In `test/map/bus_track_store_test.dart`, add a test that ingests one fix with `gtfsStopSequenceDeviation: '2 MINS BEHIND'` and `gtfsStopSequenceSchedDifferenceMins: -2` and expects `track.latest.schedDiffMins == -2`. Then ingest a second, later fix with `gtfsStopSequenceDeviation: ''` and expect `schedDiffMins` to be null. Use the file's existing `fix()` / `copyForTest` helpers and add those two named parameters if the helper lacks them.

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/state/map_providers_test.dart test/map/bus_tracking_state_test.dart test/map/bus_track_store_test.dart`
Expected: compile errors, because `map_providers.dart` and `schedDiffMins` don't exist.

- [ ] **Step 3: Add the delay to the track**

In `lib/domain/map/bus_track.dart`, add to `TrackFix` a constructor parameter `this.schedDiffMins` (optional) and the field:

```dart
  /// Schedule difference reported with this fix, in minutes: positive = ahead
  /// (early), negative = behind (late), null = the feed reported no delay.
  final int? schedDiffMins;
```

In `lib/domain/map/bus_track_store.dart`, where `TrackFix(...)` is built in `_ingestOne`, pass:

```dart
      // The adapters leave the deviation text empty exactly when no delay was
      // reported; the difference is then 0 and means "unknown", not on time.
      schedDiffMins: v.gtfsStopSequenceDeviation.isEmpty ? null : v.gtfsStopSequenceSchedDifferenceMins,
```

In `lib/domain/map/bus_tracking_state.dart`, add `final int? schedDiffMins;` with `this.schedDiffMins` in the constructor, and `schedDiffMins: f.schedDiffMins,` in `fromTrack`.

- [ ] **Step 4: Write the providers**

Create `lib/state/map_providers.dart`:

```dart
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/realtime/metrobus_mobile_api.dart';
import '../data/realtime/timetrack_models.dart';
import '../domain/arrival/arrival_models.dart';
import '../domain/arrival/arrival_service.dart';
import 'providers.dart';

/// What the map sheet shows besides your stop: a tapped stop or a tapped bus.
sealed class MapSelection {
  const MapSelection();
}

class StopSelection extends MapSelection {
  const StopSelection(this.stopId);
  final String stopId;

  @override
  bool operator ==(Object other) => other is StopSelection && other.stopId == stopId;
  @override
  int get hashCode => Object.hash(StopSelection, stopId);
}

class BusSelection extends MapSelection {
  const BusSelection(this.vehicleId);
  final String vehicleId;

  @override
  bool operator ==(Object other) => other is BusSelection && other.vehicleId == vehicleId;
  @override
  int get hashCode => Object.hash(BusSelection, vehicleId);
}

class MapSelectionNotifier extends Notifier<MapSelection?> {
  @override
  MapSelection? build() => null;

  void select(MapSelection? selection) => state = selection;
  void clear() => state = null;
}

final mapSelectionProvider = NotifierProvider<MapSelectionNotifier, MapSelection?>(MapSelectionNotifier.new);

/// Routes shown on the map. Empty = every route (spec §3.3).
class RouteFilterNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void toggle(int route) {
    final next = {...state};
    if (!next.remove(route)) next.add(route);
    state = Set.unmodifiable(next);
  }

  void showAll() => state = const {};
}

final mapRouteFilterProvider = NotifierProvider<RouteFilterNotifier, Set<int>>(RouteFilterNotifier.new);

/// Upcoming arrivals at any stop (the map's stop card and your-stop peek), from
/// the schedule, the live vehicle feed and the stop-prediction feed. Re-fetches
/// every refresh interval while something watches it.
final stopArrivalsProvider = FutureProvider.autoDispose.family<List<ArrivalRow>, String>((ref, stopId) async {
  final repo = ref.watch(gtfsRepositoryProvider).value;
  if (repo == null) return const [];
  final seconds = ref.watch(settingsProvider.select((s) => s.refreshIntervalSeconds));
  final timer = Timer(Duration(seconds: seconds), ref.invalidateSelf);
  ref.onDispose(timer.cancel);

  List<TimeTrackVehicle>? liveVehicles;
  try {
    final result = await ref.read(timetrackApiProvider).fetchVehiclesResult();
    if (result.succeeded) liveVehicles = result.vehicles;
  } catch (_) {
    // Schedule only.
  }
  List<MetrobusDeparture>? stopPredictions;
  try {
    stopPredictions = (await ref.read(metrobusMobileApiProvider).fetchDeparturesResult(stopId)).departures;
  } catch (_) {
    // Schedule and live vehicles only.
  }
  return ArrivalService(repo).getUpcomingArrivals(
    stopId: stopId,
    now: DateTime.now(),
    liveVehicles: liveVehicles,
    stopPredictions: stopPredictions,
  );
});
```

Fix the import paths of `ArrivalService`, `ArrivalRow`, `MetrobusDeparture` and `TimeTrackVehicle` to wherever `lib/ui/board/arrival_board_screen.dart` imports them from. That file already uses all four.

In `lib/state/providers.dart`, delete `arrivalsProvider` (nothing references it; `grep -rn arrivalsProvider lib test` must print nothing afterwards) and any import only it used.

- [ ] **Step 5: Run, analyze, commit**

Run: `flutter test test/state/ test/map/ && flutter analyze lib test`
Expected: PASS; no issues.

```bash
git add lib/state/map_providers.dart lib/state/providers.dart lib/domain/map/bus_track.dart lib/domain/map/bus_track_store.dart \
  lib/domain/map/bus_tracking_state.dart test/state/map_providers_test.dart test/map/bus_tracking_state_test.dart test/map/bus_track_store_test.dart
git commit -m "feat(map): map selection, route filter, per-stop arrivals and bus delay"
```

---

### Task 6: Sheet cards — your stop, a stop, a bus

**Files:**
- Create: `lib/ui/map/my_stop_card.dart`, `lib/ui/map/stop_card.dart`, `lib/ui/map/bus_card.dart`
- Delete: `lib/ui/map/bus_bottom_sheet.dart`, `lib/ui/map/stop_bottom_sheet.dart`, `test/bus_bottom_sheet_test.dart`
- Test: `test/ui/map_cards_test.dart`; extend `test/ui/screen_overflow_test.dart`

**Interfaces:**
- Consumes:
  - `stopArrivalsProvider`, `mapSelectionProvider` (Task 5);
  - `busTrackingStreamProvider`, `busTrackRendererProvider`, `settingsProvider`, `serviceUpdatesProvider`, `stopInfoProvider`;
  - `ArrivalRowTile` (`lib/ui/board/arrival_row_tile.dart`);
  - `ServiceAlertCard` (`lib/ui/alerts/service_alert_card.dart`).
- Produces (each card is a header plus a body; the map screen puts the header in `BBSheet.header` and the body in a `SliverToBoxAdapter`):
  - `class MyStopCard { static Widget header(); static Widget body(); }`. Both are `ConsumerWidget`s: `MyStopHeader` and `MyStopBody`.
  - `class StopCardHeader extends ConsumerWidget { const StopCardHeader({required StopInfo stop}); }` and `class StopCardBody extends ConsumerWidget { const StopCardBody({required StopInfo stop}); }`.
  - `class BusCardHeader extends ConsumerWidget { const BusCardHeader({required String vehicleId}); }` and `class BusCardBody extends ConsumerStatefulWidget { const BusCardBody({required String vehicleId}); }` (it holds the expanded state of *Technical details*).
  - `String delayText(int? schedDiffMins)`: `'on time'`, `'2 min early'`, `'1 min late'`, or `''` for null.
  - `String agoText(Duration d)`: `'12 s ago'` under a minute, else `'3 min ago'`.

- [ ] **Step 1: Write the failing card tests**

Create `test/ui/map_cards_test.dart`. Host each card in a `kitHost`-style app inside a `ProviderScope`, with a `CustomScrollView` holding the header (`SliverToBoxAdapter`) and body (`SliverToBoxAdapter`), the way the sheet will. Use `GoRouter` with `/`, `/board/:id` and `/alerts` routes, as `test/ui/stop_picker_test.dart` does, so the buttons' navigation is observable.

```dart
import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/bus_card.dart';
import 'package:busboard_nl/ui/map/my_stop_card.dart';
import 'package:busboard_nl/ui/map/stop_card.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.57, stopLon: -52.73);

GtfsRepository _repo() => GtfsRepository()..stopsById['1150'] = _mun;

BusTrackingState _bus({int? schedDiffMins = -1, BusStatus status = BusStatus.active}) => BusTrackingState(
      routeRun: 'Rt 10',
      vehicleId: '2573',
      routeNumber: 10,
      headsign: 'Downtown',
      lat: 47.56,
      lon: -52.71,
      heading: 90,
      speedKmh: 29,
      lastGpsTime: DateTime.now().subtract(const Duration(seconds: 12)),
      status: status,
      lastUpdateTime: DateTime.now(),
      schedDiffMins: schedDiffMins,
    );

Future<void> _host(
  WidgetTester tester, {
  required Widget header,
  required Widget body,
  List<ArrivalRow> arrivals = const [],
  Map<String, Object> prefs = const {},
  Map<String, BusTrackingState> buses = const {},
  double textScale = 1,
  double width = 390,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => CustomScrollView(slivers: [SliverToBoxAdapter(child: header), SliverToBoxAdapter(child: body)])),
    GoRoute(path: '/board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  tester.view.physicalSize = Size(width * 3, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      stopArrivalsProvider.overrideWith((ref, stopId) async => arrivals),
      busTrackingStreamProvider.overrideWith((ref) => Stream.value(buses)),
    ],
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('delay and age wording', () {
    expect(delayText(0), 'on time');
    expect(delayText(2), '2 min early');
    expect(delayText(-1), '1 min late');
    expect(delayText(null), '');
    expect(agoText(const Duration(seconds: 12)), '12 s ago');
    expect(agoText(const Duration(minutes: 3, seconds: 5)), '3 min ago');
  });

  testWidgets('stop card: name, number, and the two actions', (tester) async {
    await _host(tester, header: const StopCardHeader(stop: _mun), body: const StopCardBody(stop: _mun));
    expect(find.text('MUN Centre'), findsOneWidget);
    expect(find.text('Stop 1150'), findsOneWidget);
    await tester.tap(find.text('Set as my stop'));
    await tester.pumpAndSettle();
    expect(find.text('Your stop'), findsOneWidget, reason: 'it is now your stop');
    await tester.tap(find.text('Open board'));
    await tester.pumpAndSettle();
    expect(find.text('BOARD 1150'), findsOneWidget);
  });

  testWidgets('stop card with no arrivals says so', (tester) async {
    await _host(tester, header: const StopCardHeader(stop: _mun), body: const StopCardBody(stop: _mun));
    expect(find.text('No buses due soon'), findsOneWidget);
  });

  testWidgets('bus card: route, destination, bus number and lateness', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'), body: const BusCardBody(vehicleId: '2573'), buses: {'2573': _bus()});
    expect(find.bySemanticsLabel('Route 10'), findsOneWidget);
    expect(find.text('to Downtown'), findsOneWidget);
    expect(find.text('Bus 2573 · 1 min late'), findsOneWidget);
  });

  testWidgets('technical details start collapsed and open on tap', (tester) async {
    await _host(tester,
        header: const BusCardHeader(vehicleId: '2573'), body: const BusCardBody(vehicleId: '2573'), buses: {'2573': _bus()});
    expect(find.text('29 km/h'), findsNothing);
    await tester.tap(find.text('Technical details'));
    await tester.pumpAndSettle();
    expect(find.text('29 km/h'), findsOneWidget);
    expect(find.textContaining('s ago'), findsOneWidget);
  });

  testWidgets('a bus that has gone away shows a plain message', (tester) async {
    await _host(tester, header: const BusCardHeader(vehicleId: '9999'), body: const BusCardBody(vehicleId: '9999'));
    expect(find.text('This bus is no longer reporting'), findsOneWidget);
  });

  testWidgets('your-stop card invites you to choose a stop when there is none', (tester) async {
    await _host(tester, header: MyStopCard.header(), body: MyStopCard.body());
    expect(find.text('Choose a stop to see its next buses'), findsOneWidget);
  });

  testWidgets('your-stop card names your stop', (tester) async {
    await _host(tester, header: MyStopCard.header(), body: MyStopCard.body(), prefs: {'selectedStopId': '1150'});
    expect(find.text('MUN Centre'), findsOneWidget);
  });
}
```

Use whatever SharedPreferences key `SettingsNotifier` actually reads for the selected stop in the last test; check `_loadFromPrefs` in `lib/state/providers.dart`. If `BBTheme.light()` is not the theme factory, use the one `test/kit/kit_test_helpers.dart` uses.

Extend `test/ui/screen_overflow_test.dart` with the map cards, following that file's existing pattern of widths 320 and 360 at text ×2.0:
- `StopCardHeader` + `StopCardBody` with three arrivals;
- `BusCardHeader` + `BusCardBody` with *Technical details* expanded;
- `MyStopCard` with a stop and two arrivals.

Build the `ArrivalRow`s the way `test/ui/arrival_row_tile_test.dart` does.

- [ ] **Step 2: Run them and watch them fail**

Run: `flutter test test/ui/map_cards_test.dart`
Expected: compile errors, because the cards don't exist.

- [ ] **Step 3: Implement the cards**

Create `lib/ui/map/stop_card.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/arrival/arrival_models.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../alerts/service_alert_card.dart';
import '../board/arrival_row_tile.dart';
import '../kit/kit.dart';

/// Stop card header (spec §3.3): stop pole, name, stop number.
class StopCardHeader extends StatelessWidget {
  const StopCardHeader({super.key, required this.stop});

  final StopInfo stop;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.m),
      child: Row(
        children: [
          BBGlyph(BBGlyphKind.stopPole, size: 28, color: bb.colors.brand),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stop.stopName, style: bb.text.headline, maxLines: 2, overflow: TextOverflow.ellipsis),
                Text('Stop ${stop.stopId}', style: bb.text.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Stop card body: next arrivals, any stop alert, Set as my stop, Open board.
class StopCardBody extends ConsumerWidget {
  const StopCardBody({super.key, required this.stop});

  final StopInfo stop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMine = ref.watch(settingsProvider.select((s) => s.selectedStopId)) == stop.stopId;
    final alerts = ref
            .watch(serviceUpdatesProvider)
            .value
            ?.activeAlertsAt(DateTime.now())
            .where((a) => a.appliesTo(routeIds: const {}, stopId: stop.stopId))
            .toList() ??
        const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ArrivalsPreview(stopId: stop.stopId, max: 3),
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: BBSpace.m),
            ServiceAlertCard(
              alert: alerts.first,
              stopNames: {stop.stopId: stop.stopName},
              compact: true,
              onTap: () => context.go('/alerts'),
            ),
          ],
          const SizedBox(height: BBSpace.l),
          BBButton(
            label: 'Open board',
            icon: BBIcons.board,
            expand: true,
            onPressed: () => context.go('/board/${stop.stopId}'),
          ),
          const SizedBox(height: BBSpace.s),
          BBButton(
            label: isMine ? 'Your stop' : 'Set as my stop',
            icon: isMine ? BBIcons.star : BBIcons.starOutline,
            kind: BBButtonKind.quiet,
            expand: true,
            onPressed: isMine ? null : () => ref.read(settingsProvider.notifier).setSelectedStop(stop.stopId),
          ),
        ],
      ),
    );
  }
}

/// The next [max] arrivals at a stop, or a skeleton while the first load runs.
class ArrivalsPreview extends ConsumerWidget {
  const ArrivalsPreview({super.key, required this.stopId, this.max});

  final String stopId;
  final int? max;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final arrivals = ref.watch(stopArrivalsProvider(stopId));
    final rows = arrivals.value;
    if (rows == null) {
      return arrivals.hasError
          ? Text("Couldn't load arrivals", style: bb.text.caption)
          : BBSkeleton(kind: BBSkeletonKind.arrivalRow, count: max ?? 3);
    }
    if (rows.isEmpty) return Text('No buses due soon', style: bb.text.caption);
    final shown = max == null ? rows : rows.take(max!).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final ArrivalRow a in shown) ArrivalRowTile(arrival: a)],
    );
  }
}
```

Create `lib/ui/map/bus_card.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/map/bus_tracking_state.dart';
import '../../state/providers.dart';
import '../alerts/service_alert_card.dart';
import '../kit/kit.dart';

String delayText(int? schedDiffMins) => switch (schedDiffMins) {
      null => '',
      0 => 'on time',
      > 0 => '$schedDiffMins min early',
      _ => '${-schedDiffMins} min late',
    };

String agoText(Duration d) {
  final s = d.isNegative ? 0 : d.inSeconds;
  return s < 60 ? '$s s ago' : '${s ~/ 60} min ago';
}

BusTrackingState? _live(WidgetRef ref, String vehicleId) =>
    ref.watch(busTrackingStreamProvider).value?[vehicleId];

/// Bus card header (spec §3.3): route badge, destination, bus number, early/late.
class BusCardHeader extends ConsumerWidget {
  const BusCardHeader({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final bus = _live(ref, vehicleId);
    if (bus == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
        child: Text('This bus is no longer reporting', style: bb.text.body),
      );
    }
    final delay = delayText(bus.schedDiffMins);
    final (pill, tone) = switch (bus.status) {
      BusStatus.active => ('Live', BBPillTone.live),
      BusStatus.offRoute => ('Off route', BBPillTone.warn),
      BusStatus.stale => ('Last seen ${agoText(DateTime.now().difference(bus.lastGpsTime))}', BBPillTone.neutral),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.m),
      child: Row(
        children: [
          RouteBadge(routeNumber: bus.routeNumber),
          const SizedBox(width: BBSpace.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bus.headsign.isNotEmpty ? 'to ${bus.headsign}' : 'Route ${bus.routeNumber}',
                  style: bb.text.headline,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(delay.isEmpty ? 'Bus ${bus.vehicleId}' : 'Bus ${bus.vehicleId} · $delay', style: bb.text.caption),
              ],
            ),
          ),
          const SizedBox(width: BBSpace.s),
          Flexible(child: BBPill(label: pill, tone: tone, leadingDot: bus.status == BusStatus.active, wrap: true)),
        ],
      ),
    );
  }
}

/// Bus card body: any route alert, then a collapsed "Technical details"
/// section (speed, heading, last GPS update, map delay).
class BusCardBody extends ConsumerStatefulWidget {
  const BusCardBody({super.key, required this.vehicleId});

  final String vehicleId;

  @override
  ConsumerState<BusCardBody> createState() => _BusCardBodyState();
}

class _BusCardBodyState extends ConsumerState<BusCardBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    final bus = _live(ref, widget.vehicleId);
    if (bus == null) return const SizedBox.shrink();
    final alerts = ref
            .watch(serviceUpdatesProvider)
            .value
            ?.activeAlertsAt(DateTime.now())
            .where((a) => a.appliesTo(routeIds: {'${bus.routeNumber}'}))
            .toList() ??
        const [];
    final delay = ref.read(busTrackRendererProvider)?.currentDelayFor(bus.vehicleId);
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (alerts.isNotEmpty) ...[
            ServiceAlertCard(alert: alerts.first, compact: true, onTap: () => context.go('/alerts')),
            const SizedBox(height: BBSpace.m),
          ],
          BBPressable(
            onTap: () => setState(() => _open = !_open),
            semanticLabel: _open ? 'Technical details, expanded' : 'Technical details, collapsed',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: BBSpace.s),
              child: Row(
                children: [
                  Expanded(child: Text('Technical details', style: bb.text.label)),
                  Icon(_open ? BBIcons.chevronDown : BBIcons.chevronRight, size: 16, color: bb.colors.muted),
                ],
              ),
            ),
          ),
          if (_open) ...[
            _Detail(label: 'Speed', value: '${bus.speedKmh.round()} km/h'),
            _Detail(label: 'Heading', value: '${bus.heading.round()}°'),
            _Detail(label: 'Last GPS update', value: agoText(DateTime.now().difference(bus.lastGpsTime))),
            if (delay != null) _Detail(label: 'Drawn behind live by', value: '${delay.inSeconds} s'),
          ],
        ],
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final bb = context.bb;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: BBSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: bb.text.caption)),
          const SizedBox(width: BBSpace.m),
          Flexible(child: Text(value, style: bb.text.label, textAlign: TextAlign.end)),
        ],
      ),
    );
  }
}
```

`currentDelayFor` is `DelayedTrackRenderer.currentDelayFor(String) → Duration?` from 3b-1. Check its exact return type in `lib/domain/map/delayed_track_renderer.dart` and adapt the `.inSeconds` call if it differs.

Create `lib/ui/map/my_stop_card.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../kit/kit.dart';
import 'stop_card.dart';

/// The sheet when nothing is selected (spec §3.3): your stop's next 1–2
/// arrivals at peek, the full list when dragged up, or an invitation to choose
/// a stop.
abstract final class MyStopCard {
  static Widget header() => const _MyStopHeader();
  static Widget body() => const _MyStopBody();
}

class _MyStopHeader extends ConsumerWidget {
  const _MyStopHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    final stop = stopId == null ? null : ref.watch(stopInfoProvider(stopId));
    if (stop == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Choose a stop to see its next buses', style: bb.text.body),
            const SizedBox(height: BBSpace.m),
            BBButton(label: 'Choose a stop', icon: BBIcons.search, expand: true, onPressed: () => context.go('/')),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(BBIcons.star, size: 18, color: bb.colors.brand),
              const SizedBox(width: BBSpace.s),
              Expanded(child: Text(stop.stopName, style: bb.text.headline, maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
          const SizedBox(height: BBSpace.s),
          ArrivalsPreview(stopId: stop.stopId, max: 2),
        ],
      ),
    );
  }
}

class _MyStopBody extends ConsumerWidget {
  const _MyStopBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stopId = ref.watch(settingsProvider.select((s) => s.selectedStopId));
    if (stopId == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(BBSpace.l, 0, BBSpace.l, BBSpace.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const BBSectionHeader(title: 'Later'),
          _LaterArrivals(stopId: stopId),
          const SizedBox(height: BBSpace.m),
          BBButton(
            label: 'Open board',
            icon: BBIcons.board,
            kind: BBButtonKind.quiet,
            expand: true,
            onPressed: () => context.go('/board/$stopId'),
          ),
        ],
      ),
    );
  }
}

/// Arrivals after the first two (those are in the header at peek).
class _LaterArrivals extends ConsumerWidget {
  const _LaterArrivals({required this.stopId});

  final String stopId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(stopArrivalsProvider(stopId)).value ?? const [];
    if (rows.length <= 2) return Text('Nothing else due soon', style: context.bb.text.caption);
    return ArrivalsList(rows: rows.skip(2).toList());
  }
}
```

`stopArrivalsProvider` comes from `../../state/map_providers.dart`; add that import. Also add `ArrivalsList` to `stop_card.dart`: a `StatelessWidget` taking `List<ArrivalRow> rows` that returns the same `Column` of `ArrivalRowTile`s that `ArrivalsPreview` builds. Have `ArrivalsPreview` call it, so the row list is written once.

Delete `lib/ui/map/bus_bottom_sheet.dart`, `lib/ui/map/stop_bottom_sheet.dart` and `test/bus_bottom_sheet_test.dart`. Their coverage now lives in `map_cards_test.dart`, and nothing else imports them once Task 7 rewrites the screen. **Until Task 7**, `map_screen.dart` still imports them, so delete them in Task 7 Step 1 instead of here if the analyzer complains. Either order is fine, as long as the commit that deletes them also removes the imports.

- [ ] **Step 4: Run, analyze, commit**

Run: `flutter test test/ui/map_cards_test.dart test/ui/screen_overflow_test.dart && flutter analyze lib test`
Expected: PASS; no issues.

```bash
git add lib/ui/map/my_stop_card.dart lib/ui/map/stop_card.dart lib/ui/map/bus_card.dart test/ui/map_cards_test.dart test/ui/screen_overflow_test.dart
git commit -m "feat(map): stop, bus and your-stop cards on the kit"
```

---

### Task 7: The map screen on the kit

**Files:**
- Create: `lib/ui/map/map_view.dart`, `lib/ui/map/route_filter_card.dart`
- Rewrite: `lib/ui/map/map_screen.dart`
- Delete (if Task 6 did not): `lib/ui/map/bus_bottom_sheet.dart`, `lib/ui/map/stop_bottom_sheet.dart`, `test/bus_bottom_sheet_test.dart`
- Modify:
  - `lib/ui/shell/app_shell.dart`: drop the map padding.
  - `test/ui/app_shell_test.dart`: the map now runs under the bar.
  - `test/kit/kit_boundary_test.dart`: empty the allow-list.
  - `docs/superpowers/specs/2026-10-04-harbour-phase3-design.md`: amend §3.1, see Step 9.
- Test: `test/ui/map_screen_test.dart`

**Interfaces:**
- Consumes everything from Tasks 1–6, `busTrackStoreProvider` and `busTrackRendererProvider` (3b-1), `LegalCopy.mapCredit`, and `BBNavBar.reservedHeight`.
- Produces, in `map_view.dart`:
  - `class MapViewConfig { styleString, initialTarget, initialZoom, myLocationEnabled, attributionMargin (Point<num>), attributionColor (Color), onReady(MapSurface, MapCamera), onStyleLoaded(), onTap(LatLng) }`.
  - `typedef MapViewBuilder = Widget Function(MapViewConfig config)`.
  - `Widget maplibreMapView(MapViewConfig c)`.
  - `final mapViewBuilderProvider = Provider<MapViewBuilder>((ref) => maplibreMapView)`.
- Produces, in `route_filter_card.dart`: `Future<void> showRouteFilterCard(BuildContext context, {required List<int> routes})`.
- `MapScreen` keeps its name and constructor, so the router is unchanged.

**Behaviour, from the spec, which the code below implements:**
- **Map and style:**
  - The map fills the screen under the status bar and the nav bar. Nothing pads it.
  - The style is `MapStyle.assetFor(context.bb.brightness, settings.mapThemeMode)`.
  - Rotation, tilt and the compass are off.
- **Chips and controls:**
  - Top-left `BBChip` reads "MUN Centre · 1150" with a leading star, or "Choose a stop" with a leading search icon. Both have a chevron, and tapping opens the stop picker with `context.go('/')`.
  - Top-right `BBChip` reads "All routes", or "Routes 2, 10" when filtered. It opens the route filter card.
  - The right-hand `BBControlPill` holds a single item, *My location*. It moves the camera to you at zoom 15, animating unless Reduce Motion is on (`MediaQuery.disableAnimationsOf`).
  - The old map-theme sheet, legend, "selected stop" button and FABs are gone. Map theme lives in Settings.
- **Sheet:**
  - One `BBSheet` stays mounted, with `bottomInset: BBNavBar.reservedHeight(context)`.
  - Its content follows `mapSelectionProvider`: none shows `MyStopCard`, `StopSelection` shows the stop card, and `BusSelection` shows the bus card.
  - The sheet is keyed by selection, so each card starts at the top. On a new selection it animates to half.
  - The peek fraction fits the header: `((168 * textScale).clamp(140, 320)) / availableHeight`, clamped to 0.12–0.45.
- **Taps:**
  - A tap hit-tests the last drawn bus markers first, then stops (`tapRadiusMeters(camera.zoom)`).
  - A bus hit selects `BusSelection` and a stop hit selects `StopSelection`. A miss clears the selection and collapses the sheet to peek.
- **Credit and attribution:**
  - The credit link `"© OpenStreetMap · OpenFreeMap"` (kit caption, `muted`) sits bottom-left, just above the peeking sheet.
  - Tapping it opens a `BBDialog` titled "Map credits" with `LegalCopy.mapCredit` and one *OK* action.
- **Drawing buses:**
  - Every ~120 ms frame (the existing ticker), the screen calls `renderer.renderAll(store.tracks.values, now)` once and keeps the result.
  - It builds `busMarkers(...)` with the route filter and one `HeadingSmoother`, and calls `layers.updateBuses`.
  - Your stop updates whenever `selectedStopId` changes.
- **States and lifecycle:**
  - While the GTFS loads, the screen shows `BBLoading(label: 'Loading the map')` centred on `bg`. On error it shows `BBEmptyState(icon: BBIcons.error, title: "Couldn't load the schedule", message: 'Check your connection and try again from Settings.', tone: BBEmptyTone.error)`.
  - The ticker stops when the app is paused and restarts on resume, as today.

- [ ] **Step 1: Write the failing screen test**

Create `test/ui/map_screen_test.dart`:

```dart
import 'dart:async';

import 'package:busboard_nl/data/gtfs/gtfs_models.dart';
import 'package:busboard_nl/data/gtfs/gtfs_repository.dart';
import 'package:busboard_nl/domain/arrival/arrival_models.dart';
import 'package:busboard_nl/domain/map/bus_tracking_state.dart';
import 'package:busboard_nl/state/map_providers.dart';
import 'package:busboard_nl/state/providers.dart';
import 'package:busboard_nl/ui/copy/legal_copy.dart';
import 'package:busboard_nl/ui/kit/kit.dart';
import 'package:busboard_nl/ui/map/map_screen.dart';
import 'package:busboard_nl/ui/map/map_view.dart';
import 'package:flutter/material.dart' show MaterialApp;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;
import 'package:shared_preferences/shared_preferences.dart';

import '../map/support/fake_map_surface.dart';

const _mun = StopInfo(stopId: '1150', stopName: 'MUN Centre', stopLat: 47.5700, stopLon: -52.7300);

GtfsRepository _repo() => GtfsRepository()..stopsById['1150'] = _mun;

BusTrackingState _bus() => BusTrackingState(
      routeRun: 'Rt 10',
      vehicleId: '2573',
      routeNumber: 10,
      headsign: 'Downtown',
      lat: 47.5600,
      lon: -52.7100,
      heading: 90,
      speedKmh: 29,
      lastGpsTime: DateTime.now(),
      status: BusStatus.active,
      lastUpdateTime: DateTime.now(),
    );

/// The last config the stub map was built with, so tests can tap the "map".
MapViewConfig? _config;
final _surface = FakeMapSurface();

Widget _stubMap(MapViewConfig config) {
  _config = config;
  scheduleMicrotask(() => config.onReady(_surface, _surface));
  return const ColoredBox(key: ValueKey('stub-map'), color: Color(0xFFEEF1F4));
}

Future<void> _pump(WidgetTester tester, {Map<String, Object> prefs = const {}, Map<String, BusTrackingState> buses = const {}, double textScale = 1}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final router = GoRouter(initialLocation: '/map', routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('PICKER')),
    GoRoute(path: '/map', builder: (_, _) => const MapScreen()),
    GoRoute(path: '/board/:id', builder: (_, s) => Text('BOARD ${s.pathParameters['id']}')),
    GoRoute(path: '/alerts', builder: (_, _) => const Text('ALERTS')),
  ]);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      mapViewBuilderProvider.overrideWithValue(_stubMap),
      gtfsRepositoryProvider.overrideWith((ref) async => _repo()),
      stopArrivalsProvider.overrideWith((ref, stopId) async => const <ArrivalRow>[]),
      busTrackingStreamProvider.overrideWith((ref) => Stream.value(buses)),
    ],
    child: MaterialApp.router(
      theme: BBTheme.light(),
      routerConfig: router,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
    ),
  ));
  // The ticker never settles; pump a few frames instead of pumpAndSettle.
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    _config = null;
    _surface.calls.clear();
  });

  testWidgets('with no stop chosen, the chip and sheet invite you to choose one', (tester) async {
    await _pump(tester);
    expect(find.byKey(const ValueKey('stub-map')), findsOneWidget);
    expect(find.text('Choose a stop'), findsWidgets);
    expect(find.text('All routes'), findsOneWidget);
    expect(find.text('Choose a stop to see its next buses'), findsOneWidget);
  });

  testWidgets('the stop chip names your stop and opens the picker', (tester) async {
    await _pump(tester, prefs: {'selectedStopId': '1150'});
    await tester.tap(find.text('MUN Centre · 1150'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('PICKER'), findsOneWidget);
  });

  testWidgets('tapping near a stop opens its card; tapping empty map returns to your stop', (tester) async {
    await _pump(tester);
    _config!.onTap(const LatLng(47.5701, -52.7300));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Open board'), findsOneWidget);
    expect(find.text('Stop 1150'), findsOneWidget);
    _config!.onTap(const LatLng(47.0, -52.0));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Stop 1150'), findsNothing);
    expect(find.text('Choose a stop to see its next buses'), findsOneWidget);
  });

  testWidgets('tapping near a bus opens its card', (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    _config!.onTap(const LatLng(47.5601, -52.7100));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('to Downtown'), findsOneWidget);
  });

  testWidgets('the credit link opens the map credits', (tester) async {
    await _pump(tester);
    await tester.tap(find.text('© OpenStreetMap · OpenFreeMap'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Map credits'), findsOneWidget);
    expect(find.text(LegalCopy.mapCredit), findsOneWidget);
  });

  testWidgets('the route chip opens a filter card; picking a route filters the map', (tester) async {
    await _pump(tester, buses: {'2573': _bus()});
    await tester.tap(find.text('All routes'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.bySemanticsLabel(RegExp('Route 10')).last);
    await tester.pump(const Duration(milliseconds: 100));
    final container = ProviderScope.containerOf(tester.element(find.byType(MapScreen)));
    expect(container.read(mapRouteFilterProvider), {10});
  });

  testWidgets('the map is built with rotation off and a Harbour style asset', (tester) async {
    await _pump(tester);
    expect(_config!.styleString, 'assets/map/harbour_light.json');
  });

  testWidgets('no overflow at 320 pt and text x2.0', (tester) async {
    tester.view.physicalSize = const Size(320 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await _pump(tester, prefs: {'selectedStopId': '1150'}, textScale: 2);
    expect(tester.takeException(), isNull);
  });
}
```

Use the real selected-stop prefs key, as in Task 6.

- [ ] **Step 2: Run it and watch it fail**

Run: `flutter test test/ui/map_screen_test.dart`
Expected: a compile error, because `map_view.dart` and `mapViewBuilderProvider` don't exist.

- [ ] **Step 3: Write the map view seam**

Create `lib/ui/map/map_view.dart`:

```dart
import 'dart:math' show Point;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import 'map_surface.dart';

/// Everything the map screen needs from the map widget, so widget tests can
/// stand in a stub (MapLibre is a platform view that does not run in tests).
class MapViewConfig {
  const MapViewConfig({
    required this.styleString,
    required this.initialTarget,
    required this.initialZoom,
    required this.myLocationEnabled,
    required this.attributionMargin,
    required this.attributionColor,
    required this.onReady,
    required this.onStyleLoaded,
    required this.onTap,
  });

  final String styleString;
  final LatLng initialTarget;
  final double initialZoom;
  final bool myLocationEnabled;

  /// Where MapLibre's own attribution button sits (bottom-left): next to our
  /// credit link, in the platform's units (Android: pixels; iOS: points).
  final Point<num> attributionMargin;
  final Color attributionColor;
  final void Function(MapSurface surface, MapCamera camera) onReady;
  final VoidCallback onStyleLoaded;
  final void Function(LatLng coordinates) onTap;
}

typedef MapViewBuilder = Widget Function(MapViewConfig config);

/// The real map: north-up (no rotation, tilt or compass), no MapLibre logo.
Widget maplibreMapView(MapViewConfig c) => MapLibreMap(
      styleString: c.styleString,
      initialCameraPosition: CameraPosition(target: c.initialTarget, zoom: c.initialZoom),
      onMapCreated: (controller) {
        final surface = MapLibreSurface(controller);
        // Some platforms report taps on features here instead of onMapClick.
        controller.onFeatureTapped.add((_, coordinates, _, _, _) => c.onTap(coordinates));
        c.onReady(surface, surface);
      },
      onStyleLoadedCallback: c.onStyleLoaded,
      onMapClick: (_, coordinates) => c.onTap(coordinates),
      trackCameraPosition: true,
      myLocationEnabled: c.myLocationEnabled,
      myLocationRenderMode: MyLocationRenderMode.normal,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: false,
      logoEnabled: false,
      attributionButtonPosition: AttributionButtonPosition.bottomLeft,
      attributionButtonMargins: c.attributionMargin,
      attributionButtonColor: c.attributionColor,
    );

final mapViewBuilderProvider = Provider<MapViewBuilder>((ref) => maplibreMapView);
```

If `onFeatureTapped`'s callback arity differs in 0.27.1, match it. The old screen used `(Point<double> point, LatLng coordinates, String id, String layerId, Annotation? annotation)`.

- [ ] **Step 4: Write the route filter card**

Create `lib/ui/map/route_filter_card.dart`:

```dart
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/map_providers.dart';
import '../kit/kit.dart';

/// Floating card of route badges under the route chip (spec §3.3): tap badges
/// to choose which routes the map shows; "Show all" clears the choice. A chosen
/// badge is full colour; with a choice made, the others fade.
Future<void> showRouteFilterCard(BuildContext context, {required List<int> routes}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Close route filter',
    barrierColor: const Color(0x331C2A3A),
    transitionDuration: BBMotion.of(context, BBMotion.standard),
    pageBuilder: (_, _, _) => _RouteFilterCard(routes: routes),
    transitionBuilder: (_, animation, _, child) =>
        FadeTransition(opacity: CurvedAnimation(parent: animation, curve: BBMotion.curve), child: child),
  );
}

class _RouteFilterCard extends ConsumerWidget {
  const _RouteFilterCard({required this.routes});

  final List<int> routes;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bb = context.bb;
    final filter = ref.watch(mapRouteFilterProvider);
    final notifier = ref.read(mapRouteFilterProvider.notifier);
    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(BBSpace.l, 56, BBSpace.s, BBSpace.l),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: DecoratedBox(
              decoration: bb.floating(radius: BBRadius.sheet),
              child: Padding(
                padding: const EdgeInsets.all(BBSpace.l),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Show routes', style: bb.text.headline),
                    const SizedBox(height: BBSpace.m),
                    if (routes.isEmpty)
                      Text('No buses are reporting right now', style: bb.text.caption)
                    else
                      Wrap(
                        spacing: BBSpace.s,
                        runSpacing: BBSpace.s,
                        children: [
                          for (final r in routes)
                            Semantics(
                              selected: filter.contains(r) ? true : null,
                              child: BBPressable(
                                onTap: () => notifier.toggle(r),
                                semanticLabel: filter.contains(r) ? 'Route $r, shown' : 'Route $r',
                                child: Opacity(
                                  opacity: filter.isEmpty || filter.contains(r) ? 1 : 0.4,
                                  child: RouteBadge(routeNumber: r),
                                ),
                              ),
                            ),
                        ],
                      ),
                    const SizedBox(height: BBSpace.m),
                    BBButton(
                      label: 'Show all',
                      kind: BBButtonKind.quiet,
                      onPressed: filter.isEmpty ? null : notifier.showAll,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

The card lives on a route above the map, so it needs the `ProviderScope` — the dialog route inherits it from the app root. If `RouteBadge`'s own `Semantics(excludeSemantics: true)` hides the pressable's label, keep the `BBPressable` label as the one announced. The test finds it by `'Route 10'`.

- [ ] **Step 5: Rewrite the map screen**

Replace `lib/ui/map/map_screen.dart` entirely:

```dart
import 'dart:async';
import 'dart:math' show Point;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../data/gtfs/gtfs_models.dart';
import '../../domain/map/bus_tracking_state.dart';
import '../../domain/map/heading_smoother.dart';
import '../../state/map_providers.dart';
import '../../state/providers.dart';
import '../copy/legal_copy.dart';
import '../kit/kit.dart';
import 'bus_card.dart';
import 'map_hit_test.dart';
import 'map_layers.dart';
import 'map_style.dart';
import 'map_surface.dart';
import 'map_view.dart';
import 'my_stop_card.dart';
import 'route_filter_card.dart';
import 'stop_card.dart';

/// The Map tab (spec §3.3): full-screen Harbour map with your-stop and route
/// chips, a my-location control and one floating sheet whose card follows the
/// selection (your stop / a stop / a bus).
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> with WidgetsBindingObserver {
  static const _defaultTarget = LatLng(47.5615, -52.7126);
  static const _defaultZoom = 13.0;
  static const _frameInterval = Duration(milliseconds: 120);
  static const _creditText = '© OpenStreetMap · OpenFreeMap';

  MapSurface? _surface;
  MapCamera? _camera;
  MapLayers? _layers;
  Ticker? _ticker;
  DateTime? _lastFrame;
  bool _frameInFlight = false;
  bool _myLocationEnabled = false;
  List<BusMarker> _lastMarkers = const [];
  final _headings = HeadingSmoother();
  final _sheet = BBSheetController();

  void _log(String msg) {
    if (kDebugMode) debugPrint('[Map] $msg');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableMyLocation(request: false));
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _sheet.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _ticker != null && !_ticker!.isActive) _ticker!.start();
    if (state == AppLifecycleState.paused) _ticker?.stop();
  }

  // ─── Map lifecycle ────────────────────────────────────────

  void _onReady(MapSurface surface, MapCamera camera) {
    _surface = surface;
    _camera = camera;
  }

  Future<void> _onStyleLoaded() async {
    final surface = _surface;
    final repo = ref.read(gtfsRepositoryProvider).value;
    if (surface == null || repo == null || !mounted) return;
    final settings = ref.read(settingsProvider);
    final layers = MapLayers(
      surface,
      brightness: MapStyle.brightnessFor(context.bb.brightness, settings.mapThemeMode),
      pixelRatio: MediaQuery.devicePixelRatioOf(context),
    );
    try {
      await layers.install(stops: repo.stopsById.values);
      await layers.updateMyStop(_myStop());
    } catch (e) {
      _log('Could not install map layers: $e');
      return;
    }
    _layers = layers;
    _ticker ??= Ticker(_onTick);
    if (!_ticker!.isActive) _ticker!.start();
  }

  StopInfo? _myStop() {
    final id = ref.read(settingsProvider).selectedStopId;
    return id == null ? null : ref.read(stopInfoProvider(id));
  }

  void _onTick(Duration _) {
    final now = DateTime.now();
    if (_lastFrame != null && now.difference(_lastFrame!) < _frameInterval) return;
    _lastFrame = now;
    if (_frameInFlight) return;
    _frameInFlight = true;
    unawaited(_drawFrame(now).whenComplete(() => _frameInFlight = false));
  }

  Future<void> _drawFrame(DateTime now) async {
    final layers = _layers;
    final renderer = ref.read(busTrackRendererProvider);
    final store = ref.read(busTrackStoreProvider);
    if (layers == null || renderer == null || store == null) return;
    // The renderer is stateful per vehicle: every track, once per frame; the
    // output is filtered (route filter) after.
    final drawn = renderer.renderAll(store.tracks.values, now);
    final markers = busMarkers(
      tracking: ref.read(busTrackingStreamProvider).value ?? const {},
      drawn: drawn,
      routeFilter: ref.read(mapRouteFilterProvider),
      headings: _headings,
      now: now,
    );
    _lastMarkers = markers;
    try {
      await layers.updateBuses(markers);
    } catch (e) {
      _log('Could not update buses: $e');
    }
  }

  // ─── Interaction ──────────────────────────────────────────

  void _onTap(LatLng tap) {
    final radius = tapRadiusMeters(_camera?.zoom ?? _defaultZoom);
    final selection = ref.read(mapSelectionProvider.notifier);
    final markers = _lastMarkers.isNotEmpty ? _lastMarkers : _markersFromTracking();
    final bus = nearestBus(tap, radius, markers);
    if (bus != null) return _select(BusSelection(bus));
    final repo = ref.read(gtfsRepositoryProvider).value;
    final stop = repo == null ? null : nearestStop(tap, radius, repo.stopsById.values);
    if (stop != null) return _select(StopSelection(stop.stopId));
    selection.clear();
    unawaited(_sheet.collapse());
  }

  /// Before the first frame is drawn, hit-test the latest fixes.
  List<BusMarker> _markersFromTracking() => busMarkers(
        tracking: ref.read(busTrackingStreamProvider).value ?? const {},
        drawn: const {},
        routeFilter: ref.read(mapRouteFilterProvider),
        headings: HeadingSmoother(),
        now: DateTime.now(),
      );

  void _select(MapSelection selection) {
    ref.read(mapSelectionProvider.notifier).select(selection);
    // The sheet is re-keyed by selection; open the new card at half once built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_sheet.animateToDetent(BBSheetDetent.half));
    });
  }

  Future<void> _enableMyLocation({required bool request}) async {
    var permission = await Geolocator.checkPermission();
    if (request && permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    final granted = permission == LocationPermission.whileInUse || permission == LocationPermission.always;
    if (granted && mounted && !_myLocationEnabled) setState(() => _myLocationEnabled = true);
  }

  Future<void> _goToMyLocation() async {
    await _enableMyLocation(request: true);
    final camera = _camera;
    if (!_myLocationEnabled || camera == null) return;
    final here = await camera.myLocation();
    if (here == null || !mounted) return;
    await camera.moveTo(here, 15, animate: !MediaQuery.disableAnimationsOf(context));
  }

  void _openRouteFilter() {
    final tracking = ref.read(busTrackingStreamProvider).value ?? const <String, BusTrackingState>{};
    final routes = {for (final s in tracking.values) if (s.routeNumber > 0) s.routeNumber}.toList()..sort();
    unawaited(showRouteFilterCard(context, routes: routes));
  }

  void _openCredits() => unawaited(BBDialog.show<void>(
        context,
        title: 'Map credits',
        message: LegalCopy.mapCredit,
        actions: const [BBDialogAction(label: 'OK', value: null, primary: true)],
      ));

  // ─── Layout ───────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(settingsProvider.select((s) => s.selectedStopId), (prev, next) {
      if (prev != next) unawaited(_layers?.updateMyStop(_myStop()));
    });
    final bb = context.bb;
    final gtfs = ref.watch(gtfsRepositoryProvider);
    if (gtfs.value == null) {
      return ColoredBox(
        color: bb.colors.bg,
        child: Center(
          child: gtfs.hasError
              ? const BBEmptyState(
                  icon: BBIcons.error,
                  title: "Couldn't load the schedule",
                  message: 'Check your connection and try again from Settings.',
                  tone: BBEmptyTone.error,
                )
              : const BBLoading(label: 'Loading the map'),
        ),
      );
    }

    final settings = ref.watch(settingsProvider);
    final myStop = settings.selectedStopId == null ? null : ref.watch(stopInfoProvider(settings.selectedStopId!));
    final filter = ref.watch(mapRouteFilterProvider);
    final selection = ref.watch(mapSelectionProvider);
    final buildMap = ref.watch(mapViewBuilderProvider);
    final media = MediaQuery.of(context);
    final navInset = BBNavBar.reservedHeight(context);

    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxHeight - navInset - media.padding.top;
      final peekPx = (168 * media.textScaler.scale(1)).clamp(140.0, 320.0);
      final peek = (peekPx / available).clamp(0.12, 0.45);
      final creditBottom = navInset + peekPx + BBSpace.s;
      final ratio = defaultTargetPlatform == TargetPlatform.android ? media.devicePixelRatio : 1.0;

      return ColoredBox(
        color: bb.colors.bg,
        child: Stack(
          children: [
            Positioned.fill(
              child: buildMap(MapViewConfig(
                styleString: MapStyle.assetFor(bb.brightness, settings.mapThemeMode),
                initialTarget: myStop == null ? _defaultTarget : LatLng(myStop.stopLat, myStop.stopLon),
                initialZoom: _defaultZoom,
                myLocationEnabled: _myLocationEnabled,
                attributionMargin: Point(BBSpace.s * ratio + 200 * ratio, creditBottom * ratio),
                attributionColor: bb.colors.muted,
                onReady: _onReady,
                onStyleLoaded: () => unawaited(_onStyleLoaded()),
                onTap: _onTap,
              )),
            ),
            Positioned(
              top: media.padding.top + BBSpace.s,
              left: BBSpace.s,
              right: BBSpace.s,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    flex: 3,
                    child: BBChip(
                      label: myStop == null ? 'Choose a stop' : '${myStop.stopName} · ${myStop.stopId}',
                      icon: myStop == null ? BBIcons.search : BBIcons.star,
                      chevron: true,
                      semanticLabel: myStop == null ? 'Choose a stop' : 'Your stop, ${myStop.stopName}. Change stop',
                      onTap: () => context.go('/'),
                    ),
                  ),
                  const SizedBox(width: BBSpace.s),
                  Flexible(
                    flex: 2,
                    child: BBChip(
                      label: filter.isEmpty ? 'All routes' : 'Routes ${(filter.toList()..sort()).join(', ')}',
                      icon: BBIcons.filter,
                      chevron: true,
                      selected: filter.isNotEmpty,
                      onTap: _openRouteFilter,
                    ),
                  ),
                ],
              ),
            ),
            Positioned(
              right: BBSpace.s,
              top: media.padding.top + BBSpace.s + 44 + BBSpace.m,
              child: BBControlPill(items: [
                BBControlPillItem(icon: BBIcons.location, semanticLabel: 'My location', onPressed: _goToMyLocation),
              ]),
            ),
            Positioned(
              left: BBSpace.s + BBSpace.xs,
              bottom: creditBottom,
              child: BBPressable(
                onTap: _openCredits,
                semanticLabel: 'Map credits',
                child: Text(_creditText, style: bb.text.caption),
              ),
            ),
            Positioned.fill(
              child: BBSheet(
                key: ValueKey(selection),
                controller: _sheet,
                peekFraction: peek,
                bottomInset: navInset,
                semanticLabel: 'Map sheet',
                header: switch (selection) {
                  null => MyStopCard.header(),
                  StopSelection(:final stopId) => _stopHeader(stopId),
                  BusSelection(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
                },
                slivers: [
                  SliverToBoxAdapter(
                    child: switch (selection) {
                      null => MyStopCard.body(),
                      StopSelection(:final stopId) => _stopBody(stopId),
                      BusSelection(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _stopHeader(String stopId) {
    final stop = ref.watch(stopInfoProvider(stopId));
    return stop == null ? const SizedBox.shrink() : StopCardHeader(stop: stop);
  }

  Widget _stopBody(String stopId) {
    final stop = ref.watch(stopInfoProvider(stopId));
    return stop == null ? const SizedBox.shrink() : StopCardBody(stop: stop);
  }
}
```

Notes for the implementer:
- **Sheet controller and re-keying.** `BBSheet` is re-keyed per selection while the same `_sheet` controller is reused. 3a made the controller hand over correctly in `didUpdateWidget`, but a new key disposes the old state and attaches a new one. Confirm that `BBSheet`'s dispose detaches without disposing an *external* controller (it only disposes internal ones). If it does dispose it, give each selection its own `BBSheetController` instead.
- **Attribution margin.** The x margin (`BBSpace.s + 200`) places MapLibre's button just right of the credit text. Tune the 200 to the rendered width of `_creditText` at text ×1.0 during the parity check, and keep the platform unit conversion.
- **Removed behaviour.** `Geolocator` permission prompting moves from `initState` (always asked) to the first *My location* tap. `initState` only checks. This is a behaviour change: the app no longer asks for location the moment the map opens.

- [ ] **Step 6: Drop AppShell's map padding**

In `lib/ui/shell/app_shell.dart`:
- delete `_mapBranch` and the `Padding` around `navigationShell`, so the child is `Positioned.fill(child: navigationShell)`;
- update the class doc: every branch now runs under the bar, and the map lays out its own sheet above it (spec §2.4).

In `test/ui/app_shell_test.dart`, the map-branch tests currently expect the map content to end `height - r` above the bar. Change them to expect the map to reach the bottom, `height`, like the Alerts branch. Rename the test "the map content clears the bottom safe area as well as the bar" to "the map runs under the bar (it lays out its own sheet)".

- [ ] **Step 7: Empty the kit guard's allow-list**

In `test/kit/kit_boundary_test.dart`, make `_legacyAllowList` an empty `const <String>{}` and update its comment: "Empty: every screen is on the kit (Phase 3b-2). It must stay empty."

- [ ] **Step 8: Run, analyze**

Run: `flutter test test/ui/ test/kit/ test/map/ && flutter analyze lib test`
Expected: PASS; no issues. `grep -rn "package:flutter/material.dart" lib/ui --include=*.dart | grep -v lib/ui/kit/` prints nothing.

- [ ] **Step 9: Amend the spec for attribution and commit**

In `docs/superpowers/specs/2026-10-04-harbour-phase3-design.md` §3.1, replace "The default MapLibre "i" attribution control is replaced by a small kit text link, …" with the following:

> MapLibre's own "i" attribution button can't be removed through maplibre_gl 0.27 (Android forces it on), so it sits bottom-left, tinted `muted`, directly after a small kit text link, "© OpenStreetMap · OpenFreeMap", that is always visible above the sheet and opens the credits. *(Amended in 3b-2.)*

In the same file, add to §3.3 after "Tapping a bus": "*(3b-2 ships the bus card without the Follow button; Plan 3b-3 adds it with follow mode.)*"

```bash
git add lib/ui/map/ lib/ui/shell/app_shell.dart test/ui/map_screen_test.dart test/ui/app_shell_test.dart test/kit/kit_boundary_test.dart \
  docs/superpowers/specs/2026-10-04-harbour-phase3-design.md
git add -u lib/ui/map test   # stages the deleted bottom-sheet files and test
git commit -m "feat(map): rebuild the map screen on the kit; no Material left in lib/ui"
```

Check `git status` before committing: `analysis_options.yaml` and `tool/capture_raw_gtfsrt.dart` must not be staged.

---

### Task 8: Carry-over — the sheet's hairline in dark mode

**Files:**
- Modify: `lib/ui/kit/bb_sheet.dart`
- Test: `test/kit/sheet_test.dart`, `test/kit/kit_golden_test.dart` (a dark sheet golden)

**Interfaces:** none new.

This item is parked in the 3a ledger (Task 6, carried over by ruling to 3b): "dark-mode hairline border may be covered by the header ColoredBox/ClipRRect".

- [ ] **Step 1: Write the failing hairline test**

In `test/kit/sheet_test.dart`, add:

```dart
  testWidgets('in dark mode the hairline border is painted above the card content', (tester) async {
    await tester.pumpWidget(kitHost(
      Stack(children: [
        BBSheet(
          peekFraction: 0.3,
          header: const SizedBox(height: 40),
          slivers: const [SliverToBoxAdapter(child: SizedBox(height: 400))],
        ),
      ]),
      brightness: Brightness.dark,
    ));
    await tester.pumpAndSettle();
    final borders = tester
        .widgetList<DecoratedBox>(find.descendant(of: find.byKey(BBSheet.cardKey), matching: find.byType(DecoratedBox)).hitTestable())
        .followedBy([tester.widget<DecoratedBox>(find.byKey(BBSheet.cardKey))])
        .where((d) => d.position == DecorationPosition.foreground && (d.decoration as BoxDecoration).border != null);
    expect(borders, isNotEmpty);
  });
```

Adapt it to the file's existing helpers. The assertion is that a `DecoratedBox` with `position: DecorationPosition.foreground` and a non-null border wraps the card's clipped content in dark mode.

Add a dark sheet golden to `test/kit/kit_golden_test.dart`, following that file's existing sheet golden at light ×1.0: the same sheet with `brightness: Brightness.dark`, file name `sheet_dark.png`. Generate it with `flutter test --update-goldens test/kit/kit_golden_test.dart --plain-name "<the new test name>"`, then look at the PNG and confirm a 1 px line around the card.

- [ ] **Step 2: Run and watch it fail**

Run: `flutter test test/kit/sheet_test.dart`
Expected: the new test FAILS, because no foreground border exists.

- [ ] **Step 3: Paint the border in front**

In `lib/ui/kit/bb_sheet.dart`, in `build`'s `builder`, wrap the `ClipRRect` in a foreground `DecoratedBox` when dark, and drop the border from the background decoration:

```dart
          builder: (context, scrollController) {
            final card = bb.floating(radius: BBRadius.sheet);
            // In dark mode the hairline is the card's edge; paint it in front
            // of the clipped content so the pinned header can't cover it.
            final content = ClipRRect(
              borderRadius: BorderRadius.circular(BBRadius.sheet),
              child: CustomScrollView(
                controller: scrollController,
                slivers: [
                  PinnedHeaderSliver(
                    child: ColoredBox(
                      color: bb.colors.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [_handle(context), ?widget.header],
                      ),
                    ),
                  ),
                  ...widget.slivers,
                ],
              ),
            );
            return DecoratedBox(
              key: BBSheet.cardKey,
              decoration: card.copyWith(border: null),
              child: card.border == null
                  ? content
                  : DecoratedBox(
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        border: card.border,
                        borderRadius: BorderRadius.circular(BBRadius.sheet),
                      ),
                      child: content,
                    ),
            );
          },
```

`BoxDecoration.copyWith(border: null)` keeps the old border, because `copyWith` treats null as "unchanged". Build the background decoration explicitly instead: `BoxDecoration(color: card.color, borderRadius: card.borderRadius, boxShadow: card.boxShadow)`.

- [ ] **Step 4: Run everything, analyze, commit**

Run: `flutter analyze lib test && TZ=UTC flutter test && flutter test`
Expected: all pass in both timezones; no analyzer issues.

```bash
git add lib/ui/kit/bb_sheet.dart test/kit/sheet_test.dart test/kit/kit_golden_test.dart test/kit/goldens/
git commit -m "fix(kit): dark sheet hairline painted in front of the card content"
```

Check `git status` first: `analysis_options.yaml` and `tool/capture_raw_gtfsrt.dart` must not be staged.

---

## After the last task (controller)

- **Parity check: iOS simulator and Android emulator, light and dark, text ×1.0 and ×2.0, live data.** Buses run from about 06:30 NDT, and the feed is empty overnight. Check:
  - **Style:** it matches §3.1, and switching Settings → Map theme reloads it with the buses still drawn (Review Focus 1).
  - **Markers:** each badge matches its board badge colour. The notch points the way the bus drives and turns the short way round. A stale bus is grey. The badge is about the same size as the board's compact badge on both platforms; if Android's image density differs, fix it in `MarkerImages`.
  - **Taps:** tapping a stop or a bus opens its card at half. Tapping empty map returns to your stop at peek.
  - **Chips and controls:** the chips, the route filter and My location work.
  - **Attribution:** the credit link and MapLibre's "i" sit together bottom-left above the peeking sheet. Tune `attributionMargin`.
  - **Android cold boot:** watch for the map freezing on the first launch, a carried-over watch item.
- **Record:** note the results in the ledger.
- **Next plan:** Plan 3b-3 (follow mode, §3.5). It consumes:
  - `mapSelectionProvider` / `BusSelection`, `MapLayers` (adding the route-line layer below stops), `MapCamera.moveTo`;
  - the bus card, to gain *Follow*;
  - `HeadingSmoother`;
  - `stopArrivalsProvider` / `ArrivalsPreview`.
