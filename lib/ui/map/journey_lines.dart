import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:maplibre_gl/maplibre_gl.dart' show LatLng;

import '../../data/gtfs/gtfs_repository.dart';
import '../../domain/map/route_geometry.dart';
import '../../domain/trip_planner/journey.dart';
import '../../domain/trip_planner/place.dart';
import '../kit/kit.dart';

/// What the map draws for a planned journey (spec §2.3): each ride's part of its trip in its route colour, and
/// each walk as a straight line. Coordinates are [lon, lat] pairs.
class JourneyLines {
  const JourneyLines({required this.rides, required this.walks});

  final List<({List<List<double>> line, Color color})> rides;
  final List<List<List<double>>> walks;

  /// The corners of the box around every line (south-west, north-east); null when nothing is drawn.
  (LatLng, LatLng)? get bounds {
    double? south, west, north, east;
    for (final line in [for (final r in rides) r.line, ...walks]) {
      for (final p in line) {
        south = math.min(south ?? p[1], p[1]);
        north = math.max(north ?? p[1], p[1]);
        west = math.min(west ?? p[0], p[0]);
        east = math.max(east ?? p[0], p[0]);
      }
    }
    if (south == null) return null;
    return (LatLng(south, west!), LatLng(north!, east!));
  }
}

/// The lines for [j]. A ride follows its trip's shape between the stops it is boarded and left at; with no shape
/// (or stops that can't be placed on it), it runs stop to stop. A walk's pin end is [from] (at the start) or
/// [to] (at the end); a walk whose ends aren't known is left out.
JourneyLines journeyLines(Journey j, GtfsRepository repo, RouteGeometry geometry, {Place? from, Place? to}) {
  List<double>? stopAt(String? id) {
    final s = id == null ? null : repo.stopsById[id];
    return s == null ? null : [s.stopLon, s.stopLat];
  }

  List<double>? placeAt(Place? p) => switch (p) {
        StopPlace(:final stopId) => stopAt(stopId),
        PinPlace(:final lat, :final lon) => [lon, lat],
        null => null,
      };

  final rides = <({List<List<double>> line, Color color})>[];
  final walks = <List<List<double>>>[];
  for (final leg in j.legs) {
    switch (leg) {
      case RideLeg():
        final line = _rideLine(leg, repo, geometry) ??
            [?stopAt(leg.boardStopId), ?stopAt(leg.alightStopId)];
        if (line.length < 2) continue;
        final name = repo.routesById[leg.routeId]?.routeShortName ?? leg.routeId;
        rides.add((line: line, color: RoutePalette.ofName(name).line));
      case WalkLeg():
        final start = leg.fromStopId == null ? placeAt(from) : stopAt(leg.fromStopId);
        final end = leg.toStopId == null ? placeAt(to) : stopAt(leg.toStopId);
        if (start != null && end != null) walks.add([start, end]);
    }
  }
  return JourneyLines(rides: rides, walks: walks);
}

/// The trip's own line between the ride's two stops: its shape, cut there, else its stops in order.
List<List<double>>? _rideLine(RideLeg leg, GtfsRepository repo, RouteGeometry geometry) {
  final shapeId = repo.tripsById[leg.tripId]?.shapeId;
  final stops = geometry.tripStops(leg.tripId, shapeId ?? '');
  // A loop trip can call at the board stop twice: take the call nearest the ride's departure.
  int? board;
  for (var i = 0; i < stops.length; i++) {
    if (stops[i].stopId != leg.boardStopId) continue;
    final gap = ((stops[i].departureSeconds ?? leg.departs) - leg.departs).abs();
    if (board == null || gap < ((stops[board].departureSeconds ?? leg.departs) - leg.departs).abs()) board = i;
  }
  if (board == null) return null;
  int? alight;
  for (var i = board + 1; i < stops.length; i++) {
    if (stops[i].stopId == leg.alightStopId) {
      alight = i;
      break;
    }
  }
  if (alight == null) return null;
  final from = stops[board].progress;
  final to = stops[alight].progress;
  if (shapeId != null && from != null && to != null) {
    final cut = geometry.shapeBetween(shapeId, from, to);
    if (cut != null) return cut;
  }
  final line = [
    for (var i = board; i <= alight; i++)
      if (repo.stopsById[stops[i].stopId] case final s?) [s.stopLon, s.stopLat],
  ];
  return line.length < 2 ? null : line;
}
