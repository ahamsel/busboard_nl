import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/arrival/arrival_models.dart';

/// The bus being followed (spec §3.5): a vehicle ID, never a route or trip.
class FollowTarget {
  const FollowTarget(this.vehicleId);
  final String vehicleId;

  @override
  bool operator ==(Object other) => other is FollowTarget && other.vehicleId == vehicleId;
  @override
  int get hashCode => vehicleId.hashCode;
}

class FollowNotifier extends Notifier<FollowTarget?> {
  @override
  FollowTarget? build() => null;

  void follow(String vehicleId) => state = FollowTarget(vehicleId);
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
