import 'package:flutter/widgets.dart';
// Material's icon font is used purely as a glyph source (rounded set), which
// renders identically on iOS and Android.
import 'package:flutter/material.dart' show Icons;

/// The app's single icon vocabulary. Screens use these names, never `Icons.*`.
abstract final class BBIcons {
  static const IconData board = Icons.departure_board_rounded;
  static const IconData map = Icons.map_rounded;
  static const IconData alerts = Icons.campaign_rounded;
  static const IconData settings = Icons.settings_rounded;
  static const IconData search = Icons.search_rounded;
  static const IconData location = Icons.my_location_rounded;
  static const IconData nearMe = Icons.near_me_rounded;
  static const IconData chevronRight = Icons.chevron_right_rounded;
  static const IconData chevronDown = Icons.expand_more_rounded;
  static const IconData close = Icons.close_rounded;
  static const IconData check = Icons.check_rounded;
  static const IconData refresh = Icons.refresh_rounded;
  static const IconData bus = Icons.directions_bus_rounded;
  static const IconData stop = Icons.place_rounded;
  static const IconData filter = Icons.filter_alt_rounded;
  static const IconData info = Icons.info_outline_rounded;
  static const IconData warning = Icons.warning_amber_rounded;
  static const IconData noService = Icons.block_rounded;
  static const IconData schedule = Icons.schedule_rounded;
  static const IconData star = Icons.star_rounded;
  static const IconData starOutline = Icons.star_outline_rounded;
  static const IconData theme = Icons.contrast_rounded;
  static const IconData offline = Icons.cloud_off_rounded;
  static const IconData error = Icons.error_outline_rounded;
  static const IconData back = Icons.arrow_back_rounded;
  static const IconData history = Icons.history_rounded;
  static const IconData update = Icons.update_rounded;
  static const IconData pin = Icons.pin_drop_rounded;
  static const IconData timer = Icons.timer_rounded;
  static const IconData download = Icons.cloud_download_rounded;
  static const IconData palette = Icons.palette_rounded;
  static const IconData detour = Icons.alt_route_rounded;
  static const IconData reducedService = Icons.remove_circle_outline_rounded;
  static const IconData stopMoved = Icons.wrong_location_rounded;
  static const IconData accessible = Icons.accessible_rounded;
  static const IconData additionalService = Icons.add_road_rounded;
  static const IconData checkCircle = Icons.check_circle_outline_rounded;
  static const IconData locationOff = Icons.location_off_rounded;
  static const IconData layers = Icons.layers_rounded;
  static const IconData add = Icons.add_rounded;
  static const IconData remove = Icons.remove_rounded;
}
