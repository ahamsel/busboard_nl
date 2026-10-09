import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/arrival/arrival_models.dart';

/// The bus being followed (spec §3.5): a vehicle ID, never a route or trip.
class FollowTarget {
  const FollowTarget(this.vehicleId, {this.stopId});
  final String vehicleId;

  /// "Your stop" for this follow: a planned trip's boarding stop. Null for the Board's saved stop.
  final String? stopId;

  @override
  bool operator ==(Object other) => other is FollowTarget && other.vehicleId == vehicleId && other.stopId == stopId;
  @override
  int get hashCode => Object.hash(vehicleId, stopId);
}

class FollowNotifier extends Notifier<FollowTarget?> {
  @override
  FollowTarget? build() => null;

  /// [stopId] stands in for the saved stop for this follow only (a planned trip's boarding stop).
  void follow(String vehicleId, {String? stopId}) => state = FollowTarget(vehicleId, stopId: stopId);
  void stop() => state = null;
}

/// App-wide so the Board can start a follow; only the map acts on it.
final followProvider = NotifierProvider<FollowNotifier, FollowTarget?>(FollowNotifier.new);

extension FollowableArrival on ArrivalRow {
  /// The bus this row can follow (spec §3.5), or null for rows that stay inert:
  /// scheduled-only rows and live rows without a known vehicle.
  String? get followableVehicle {
    final vehicle = vehicleNumber;
    return !isLive || vehicle == null || vehicle.isEmpty ? null : vehicle;
  }
}
