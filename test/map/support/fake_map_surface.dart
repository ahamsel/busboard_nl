import 'dart:typed_data';

import 'package:busboard_nl/ui/map/map_surface.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;
import 'package:maplibre_gl/maplibre_gl.dart';

/// Records every call the map layers make, in order.
class FakeMapSurface implements MapSurface, MapCamera {
  final calls = <String>[];
  final images = <String, Uint8List>{};
  final sources = <String, Map<String, dynamic>>{};
  final layers = <String, Object>{};
  final layerMinZoom = <String, double?>{};
  final moves = <(LatLng, double, bool)>[];
  final fits = <(LatLng, LatLng, EdgeInsets, bool)>[];
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
    if (sources.containsKey(id)) throw StateError('Source with id $id already exists.');
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
    if (layers.containsKey(layerId)) throw StateError('Layer with id $layerId already exists.');
    calls.add('layer $layerId');
    layers[layerId] = p;
    layerMinZoom[layerId] = minzoom;
  }

  @override
  Future<void> addSymbolLayer(String sourceId, String layerId, SymbolLayerProperties p, {double? minzoom}) async {
    if (layers.containsKey(layerId)) throw StateError('Layer with id $layerId already exists.');
    calls.add('layer $layerId');
    layers[layerId] = p;
    layerMinZoom[layerId] = minzoom;
  }

  @override
  Future<void> addLineLayer(String sourceId, String layerId, LineLayerProperties p) async {
    if (layers.containsKey(layerId)) throw StateError('Layer with id $layerId already exists.');
    calls.add('layer $layerId');
    layers[layerId] = p;
    layerMinZoom[layerId] = null;
  }

  @override
  Future<void> removeLayer(String layerId) async {
    calls.add('remove layer $layerId');
    if (layers.remove(layerId) == null) throw StateError('Layer $layerId does not exist.');
    layerMinZoom.remove(layerId);
  }

  @override
  Future<void> removeSource(String sourceId) async {
    calls.add('remove source $sourceId');
    if (sources.remove(sourceId) == null) throw StateError('Source $sourceId does not exist.');
  }

  @override
  Future<void> moveTo(LatLng target, double zoom, {required bool animate}) async => moves.add((target, zoom, animate));

  @override
  Future<void> fitBounds(LatLng a, LatLng b, {required EdgeInsets padding, required bool animate}) async =>
      fits.add((a, b, padding, animate));

  @override
  Future<LatLng?> myLocation() async => location;

  List<Map<String, dynamic>> features(String source) =>
      (sources[source]!['features'] as List).cast<Map<String, dynamic>>();
}
