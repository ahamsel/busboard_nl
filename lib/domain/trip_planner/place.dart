/// The label of the pin the place picker makes from the phone's position.
const myLocationLabel = 'My location';

/// One end of a trip: a stop, or a pin dropped on the map (spec §1).
sealed class Place {
  String get label;
  Map<String, Object?> toJson();

  /// Null for anything that isn't a well-formed stop or pin (an old or corrupt saved entry).
  static Place? fromJson(Object? json) {
    if (json is! Map) return null;
    return switch (json['kind']) {
      'stop' when json['stopId'] is String && json['name'] is String =>
        StopPlace(stopId: json['stopId'] as String, name: json['name'] as String),
      'pin' when json['lat'] is num && json['lon'] is num && json['label'] is String => PinPlace(
          lat: (json['lat'] as num).toDouble(),
          lon: (json['lon'] as num).toDouble(),
          label: json['label'] as String,
        ),
      _ => null,
    };
  }
}

class StopPlace extends Place {
  StopPlace({required this.stopId, required this.name});
  final String stopId;
  final String name;
  @override
  String get label => name;
  @override
  Map<String, Object?> toJson() => {'kind': 'stop', 'stopId': stopId, 'name': name};
  @override
  bool operator ==(Object other) => other is StopPlace && other.stopId == stopId;
  @override
  int get hashCode => stopId.hashCode;
}

class PinPlace extends Place {
  PinPlace({required this.lat, required this.lon, required this.label});
  final double lat;
  final double lon;
  @override
  final String label;
  @override
  Map<String, Object?> toJson() => {'kind': 'pin', 'lat': lat, 'lon': lon, 'label': label};
  @override
  bool operator ==(Object other) => other is PinPlace && other.lat == lat && other.lon == lon;
  @override
  int get hashCode => Object.hash(lat, lon);
}
