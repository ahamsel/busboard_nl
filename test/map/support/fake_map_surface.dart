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
