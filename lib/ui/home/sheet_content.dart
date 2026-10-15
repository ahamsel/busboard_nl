import 'package:flutter/widgets.dart';

import '../../state/home_sheet_provider.dart';
import '../map/bus_card.dart';
import 'home_sheet.dart';
import 'journey_sheet.dart';
import 'options_sheet.dart';
import 'stop_sheet.dart';

/// The sheet's header for what it shows. [onChooseStop] is the home sheet's "Choose your stop". On a phone ([wide]
/// false) the home sheet's header is its slim bar; the tablet panel keeps the full header.
Widget selectionHeader(HomeSheet sheet, {VoidCallback? onChooseStop, bool wide = false}) => switch (sheet) {
      HomeSheetHome() =>
        wide ? HomeSheetContent.header(onChooseStop: onChooseStop) : HomeSheetContent.bar(onChooseStop: onChooseStop),
      StopSheet(:final stopId) => StopSheetContent.header(stopId),
      BusSheet(:final vehicleId) => BusCardHeader(vehicleId: vehicleId),
      OptionsSheet() => OptionsSheetContent.header(),
      JourneySheet(:final journey) => JourneySheetContent.header(journey),
    };

/// The sheet's slivers under [selectionHeader] (the same [wide]).
List<Widget> selectionSlivers(HomeSheet sheet, {bool wide = false}) => switch (sheet) {
      HomeSheetHome() => [SliverToBoxAdapter(child: wide ? HomeSheetContent.body() : HomeSheetContent.barBody())],
      StopSheet(:final stopId) => [SliverToBoxAdapter(child: StopSheetContent.body(stopId))],
      BusSheet(:final vehicleId) => [SliverToBoxAdapter(child: BusCardBody(vehicleId: vehicleId))],
      OptionsSheet() => OptionsSheetContent.slivers(),
      JourneySheet(:final journey) => [SliverToBoxAdapter(child: JourneySheetContent.body(journey))],
    };
