import 'package:flutter/widgets.dart';

import '../../state/home_sheet_provider.dart';
import '../map/bus_card.dart';
import 'home_sheet.dart';
import 'stop_sheet.dart';

/// The sheet's header for what it shows. [onChooseStop] is the home sheet's "Choose your stop".
Widget selectionHeader(HomeSheet sheet, {VoidCallback? onChooseStop}) => switch (sheet) {
      HomeSheetHome() => HomeSheetContent.header(onChooseStop: onChooseStop),
      StopSheet(:final stopId) => StopSheetContent.header(stopId),
      BusSheet(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
      OptionsSheet() => const SizedBox.shrink(),
      JourneySheet() => const SizedBox.shrink(),
    };

/// The sheet's body under [selectionHeader].
Widget selectionBody(HomeSheet sheet) => switch (sheet) {
      HomeSheetHome() => HomeSheetContent.body(),
      StopSheet(:final stopId) => StopSheetContent.body(stopId),
      BusSheet(:final vehicleId) => BusCardBody(vehicleId: vehicleId),
      OptionsSheet() => const SizedBox.shrink(),
      JourneySheet() => const SizedBox.shrink(),
    };
