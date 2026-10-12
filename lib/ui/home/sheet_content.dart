import 'package:flutter/widgets.dart';

import '../../data/gtfs/gtfs_models.dart';
import '../../state/home_sheet_provider.dart';
import '../map/bus_card.dart';
import '../map/stop_card.dart';
import 'home_sheet.dart';

/// The sheet's header for what it shows. [onChooseStop] is the home sheet's "Choose your stop".
Widget selectionHeader(HomeSheet sheet, StopInfo? stop, {VoidCallback? onChooseStop}) => switch (sheet) {
      HomeSheetHome() => HomeSheetContent.header(onChooseStop: onChooseStop),
      StopSheet() => stop == null ? const SizedBox.shrink() : StopCardHeader(stop: stop),
      BusSheet(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
      OptionsSheet() => const SizedBox.shrink(),
      JourneySheet() => const SizedBox.shrink(),
    };

/// The sheet's body under [selectionHeader].
Widget selectionBody(HomeSheet sheet, StopInfo? stop, {VoidCallback? onChooseStop}) => switch (sheet) {
      HomeSheetHome() => HomeSheetContent.body(),
      StopSheet() => stop == null ? const SizedBox.shrink() : StopCardBody(stop: stop),
      BusSheet(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
      OptionsSheet() => const SizedBox.shrink(),
      JourneySheet() => const SizedBox.shrink(),
    };
