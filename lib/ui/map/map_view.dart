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
  /// credit link, in logical pixels on both platforms (maplibre_gl's Android side
  /// multiplies by the screen density itself).
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
