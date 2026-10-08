import 'package:flutter/widgets.dart';

/// The app's single icon vocabulary: Phosphor (MIT), the same on iOS and
/// Android. The two weights we use are vendored under assets/fonts/phosphor/
/// (families `PhosphorRegular` and `PhosphorFill`) and the code points come
/// from the Phosphor Flutter tables. Screens use these names, never a glyph
/// set directly. Regular weight by default; the `*Fill` names (and [star])
/// mark active or selected states.
abstract final class BBIcons {
  static const IconData board = IconData(0xed2c, fontFamily: 'PhosphorRegular'); // clockCountdown
  static const IconData boardFill = IconData(0xed2c, fontFamily: 'PhosphorFill'); // clockCountdown
  static const IconData map = IconData(0xe31a, fontFamily: 'PhosphorRegular'); // mapTrifold
  static const IconData mapFill = IconData(0xe31a, fontFamily: 'PhosphorFill'); // mapTrifold
  static const IconData alerts = IconData(0xe324, fontFamily: 'PhosphorRegular'); // megaphone
  static const IconData alertsFill = IconData(0xe324, fontFamily: 'PhosphorFill'); // megaphone
  static const IconData settings = IconData(0xe272, fontFamily: 'PhosphorRegular'); // gearSix
  static const IconData search = IconData(0xe30c, fontFamily: 'PhosphorRegular'); // magnifyingGlass
  static const IconData location = IconData(0xe1d6, fontFamily: 'PhosphorRegular'); // crosshair
  static const IconData nearMe = IconData(0xeade, fontFamily: 'PhosphorRegular'); // navigationArrow
  static const IconData chevronRight = IconData(0xe13a, fontFamily: 'PhosphorRegular'); // caretRight
  static const IconData chevronDown = IconData(0xe136, fontFamily: 'PhosphorRegular'); // caretDown
  static const IconData close = IconData(0xe4f6, fontFamily: 'PhosphorRegular'); // x
  static const IconData check = IconData(0xe182, fontFamily: 'PhosphorRegular'); // check
  static const IconData refresh = IconData(0xe036, fontFamily: 'PhosphorRegular'); // arrowClockwise
  static const IconData bus = IconData(0xe106, fontFamily: 'PhosphorRegular'); // bus
  static const IconData stop = IconData(0xe316, fontFamily: 'PhosphorRegular'); // mapPin
  static const IconData filter = IconData(0xe266, fontFamily: 'PhosphorRegular'); // funnel
  static const IconData info = IconData(0xe2ce, fontFamily: 'PhosphorRegular'); // info
  static const IconData warning = IconData(0xe4e0, fontFamily: 'PhosphorRegular'); // warning
  static const IconData noService = IconData(0xe3de, fontFamily: 'PhosphorRegular'); // prohibit
  static const IconData schedule = IconData(0xe19a, fontFamily: 'PhosphorRegular'); // clock
  static const IconData star = IconData(0xe46a, fontFamily: 'PhosphorFill'); // star
  static const IconData starOutline = IconData(0xe46a, fontFamily: 'PhosphorRegular'); // star
  static const IconData theme = IconData(0xe18c, fontFamily: 'PhosphorRegular'); // circleHalf
  static const IconData offline = IconData(0xe1b6, fontFamily: 'PhosphorRegular'); // cloudSlash
  static const IconData error = IconData(0xe4e2, fontFamily: 'PhosphorRegular'); // warningCircle
  static const IconData back = IconData(0xe058, fontFamily: 'PhosphorRegular'); // arrowLeft
  static const IconData history = IconData(0xe1a0, fontFamily: 'PhosphorRegular'); // clockCounterClockwise
  static const IconData update = IconData(0xe094, fontFamily: 'PhosphorRegular'); // arrowsClockwise
  static const IconData pin = IconData(0xe318, fontFamily: 'PhosphorRegular'); // mapPinLine
  static const IconData timer = IconData(0xe492, fontFamily: 'PhosphorRegular'); // timer
  static const IconData download = IconData(0xe1ac, fontFamily: 'PhosphorRegular'); // cloudArrowDown
  static const IconData palette = IconData(0xe6c8, fontFamily: 'PhosphorRegular'); // palette
  static const IconData detour = IconData(0xed3c, fontFamily: 'PhosphorRegular'); // arrowsSplit
  static const IconData reducedService = IconData(0xe32c, fontFamily: 'PhosphorRegular'); // minusCircle
  static const IconData stopMoved = IconData(0xe89c, fontFamily: 'PhosphorRegular'); // signpost
  static const IconData accessible = IconData(0xe4e8, fontFamily: 'PhosphorRegular'); // wheelchair
  static const IconData additionalService = IconData(0xe3d6, fontFamily: 'PhosphorRegular'); // plusCircle
  static const IconData checkCircle = IconData(0xe184, fontFamily: 'PhosphorRegular'); // checkCircle
  static const IconData locationOff = IconData(0xedd4, fontFamily: 'PhosphorRegular'); // gpsSlash
  static const IconData layers = IconData(0xe466, fontFamily: 'PhosphorRegular'); // stack
  static const IconData add = IconData(0xe3d4, fontFamily: 'PhosphorRegular'); // plus
  static const IconData remove = IconData(0xe32a, fontFamily: 'PhosphorRegular'); // minus
  static const IconData bell = IconData(0xe0ce, fontFamily: 'PhosphorRegular'); // bell
  static const IconData bellFill = IconData(0xe0ce, fontFamily: 'PhosphorFill'); // bell
  static const IconData plan = IconData(0xe39c, fontFamily: 'PhosphorRegular'); // path
  static const IconData planFill = IconData(0xe39c, fontFamily: 'PhosphorFill'); // path
  static const IconData swap = IconData(0xe098, fontFamily: 'PhosphorRegular'); // arrowsDownUp
  static const IconData walk = IconData(0xe73a, fontFamily: 'PhosphorRegular'); // personSimpleWalk
  static const IconData calendar = IconData(0xe10a, fontFamily: 'PhosphorRegular'); // calendarBlank
}
