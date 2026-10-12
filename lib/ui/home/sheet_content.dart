import 'package:flutter/widgets.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../state/home_sheet_provider.dart';
import '../map/bus_card.dart';
import '../map/my_stop_card.dart';
import '../map/stop_card.dart';

/// The sheet's header for what it shows (home = your stop).
Widget selectionHeader(HomeSheet sheet, StopInfo? stop) => switch (sheet) {
      HomeSheetHome() => MyStopCard.header(),
      StopSheet() => stop == null ? const SizedBox.shrink() : StopCardHeader(stop: stop),
      BusSheet(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
      OptionsSheet() => const SizedBox.shrink(),
      JourneySheet() => const SizedBox.shrink(),
    };

/// The sheet's body under [selectionHeader].
Widget selectionBody(HomeSheet sheet, StopInfo? stop) => switch (sheet) {
      HomeSheetHome() => MyStopCard.body(),
      StopSheet() => stop == null ? const SizedBox.shrink() : StopCardBody(stop: stop),
      BusSheet(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
      OptionsSheet() => const SizedBox.shrink(),
      JourneySheet() => const SizedBox.shrink(),
    };
