import 'dart:async';

import 'package:geolocator/geolocator.dart';

import '../trip_planner/place.dart';

/// How long a location fix may take before giving up.
const locateTimeLimit = Duration(seconds: 10);

/// One fix of the phone's position as a "My location" pin, or null when location is off, refused or too slow.
Future<PinPlace?> locateMe() async {
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      return null;
    }
    final p = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: locateTimeLimit),
    );
    return PinPlace(lat: p.latitude, lon: p.longitude, label: myLocationLabel);
  } on TimeoutException {
    return null;
  } catch (_) {
    return null;
  }
}
