import 'package:flutter/widgets.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../state/map_providers.dart';
import '../map/bus_card.dart';
import '../map/my_stop_card.dart';
import '../map/stop_card.dart';

/// The sheet's header for what is selected on the map (nothing = your stop).
Widget selectionHeader(MapSelection? selection, StopInfo? stop) => switch (selection) {
      null => MyStopCard.header(),
      StopSelection() => stop == null ? const SizedBox.shrink() : StopCardHeader(stop: stop),
      BusSelection(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
    };

/// The sheet's body under [selectionHeader].
Widget selectionBody(MapSelection? selection, StopInfo? stop) => switch (selection) {
      null => MyStopCard.body(),
      StopSelection() => stop == null ? const SizedBox.shrink() : StopCardBody(stop: stop),
      BusSelection(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
    };
