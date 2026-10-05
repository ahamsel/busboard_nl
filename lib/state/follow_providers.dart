import 'package:flutter_riverpod/flutter_riverpod.dart';

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
