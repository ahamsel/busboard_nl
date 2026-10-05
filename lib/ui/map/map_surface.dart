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
