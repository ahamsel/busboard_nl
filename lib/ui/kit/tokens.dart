import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Colour roles for one brightness (spec 2026-10-14 §2: neutral greys and the brightened Harbour blue).
/// Only the brand, routes, live and status states carry colour; everything else is a neutral grey.
/// Raw colour values live only here and in route_palette.dart.
@immutable
class BBColors {
  const BBColors({
    required this.bg,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceField,
    required this.surfaceFloat,
    required this.surfaceSunken,
    required this.skeleton,
    required this.line,
    required this.handle,
    required this.highlight,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.onBrand,
    required this.brandInk,
    required this.brandSoft,
    required this.live,
    required this.liveInk,
    required this.liveSoft,
    required this.soon,
    required this.warnBg,
    required this.warnInk,
    required this.dangerBg,
    required this.dangerInk,
  });

  /// Page background behind pushed pages.
  final Color bg;

  /// Sheets, panels and pushed-page cards (dark: level 1).
  final Color surface;

  /// Cards inside a sheet (dark: level 2).
  final Color surfaceRaised;

  /// Fields, segmented controls and chips on a sheet (dark: level 3).
  final Color surfaceField;

  /// Buttons and chips floating on the map.
  final Color surfaceFloat;

  /// Rare recessed areas only. Never a field fill (spec §2.2).
  final Color surfaceSunken;

  /// Placeholder blocks in `BBSkeleton`.
  final Color skeleton;

  /// Hairlines and field outlines.
  final Color line;

  /// The sheet's grab handle: a control, so a neutral grey at 3:1 on the sheet (WCAG 1.4.11), unlike [line].
  final Color handle;

  /// The 1 px top-edge highlight on dark floating layers (transparent in light).
  final Color highlight;
  final Color ink;
  final Color muted;

  /// Fills only: primary buttons, selected chips, your location, badges. Never text on a surface.
  final Color brand;
  final Color onBrand;

  /// Blue text and icons on surfaces (saved-place icons, quick-pick chips).
  final Color brandInk;
  final Color brandSoft;
  final Color live;
  final Color liveInk;
  final Color liveSoft;
  final Color soon;
  final Color warnBg;
  final Color warnInk;
  final Color dangerBg;
  final Color dangerInk;

  static const light = BBColors(
    bg: Color(0xFFF4F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceField: Color(0xFFFFFFFF),
    surfaceFloat: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEEF0F2),
    skeleton: Color(0xFFE6E8EB),
    line: Color(0xFFE3E5E8),
    handle: Color(0xFF8E939B),
    highlight: Color(0x00000000),
    ink: Color(0xFF16181C),
    muted: Color(0xFF5F646C),
    brand: Color(0xFF1272C9),
    onBrand: Color(0xFFFFFFFF),
    brandInk: Color(0xFF0D5DA6),
    brandSoft: Color(0xFFE3EEFA),
    live: Color(0xFF2FB67C),
    liveInk: Color(0xFF1E7A4E),
    liveSoft: Color(0xFFDFF4EA),
    soon: Color(0xFFD9480F),
    warnBg: Color(0xFFFCEFD2),
    warnInk: Color(0xFF7A5200),
    dangerBg: Color(0xFFFBD9D6),
    dangerInk: Color(0xFF9B1C1C),
  );

  static const dark = BBColors(
    bg: Color(0xFF121316),
    surface: Color(0xFF1F2024),
    surfaceRaised: Color(0xFF27292E),
    surfaceField: Color(0xFF2B2D32),
    surfaceFloat: Color(0xFF2A2C31),
    surfaceSunken: Color(0xFF18191C),
    skeleton: Color(0xFF33353B),
    line: Color(0xFF3A3D44),
    handle: Color(0xFF6E727B),
    highlight: Color(0x14FFFFFF),
    ink: Color(0xFFF2F3F5),
    muted: Color(0xFFA3A7AF),
    brand: Color(0xFF5EA2F0),
    onBrand: Color(0xFF08203A),
    brandInk: Color(0xFF8CC0F7),
    brandSoft: Color(0xFF16304A),
    live: Color(0xFF45D695),
    liveInk: Color(0xFF45D695),
    liveSoft: Color(0xFF123227),
    soon: Color(0xFFFF8A5B),
    warnBg: Color(0xFF3A2E12),
    warnInk: Color(0xFFF9D58A),
    dangerBg: Color(0xFF3A1A1A),
    dangerInk: Color(0xFFF5A3A3),
  );

  BBColors lerp(BBColors other, double t) {
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BBColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceRaised: l(surfaceRaised, other.surfaceRaised),
      surfaceField: l(surfaceField, other.surfaceField),
      surfaceFloat: l(surfaceFloat, other.surfaceFloat),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      skeleton: l(skeleton, other.skeleton),
      line: l(line, other.line),
      handle: l(handle, other.handle),
      highlight: l(highlight, other.highlight),
      ink: l(ink, other.ink),
      muted: l(muted, other.muted),
      brand: l(brand, other.brand),
      onBrand: l(onBrand, other.onBrand),
      brandInk: l(brandInk, other.brandInk),
      brandSoft: l(brandSoft, other.brandSoft),
      live: l(live, other.live),
      liveInk: l(liveInk, other.liveInk),
      liveSoft: l(liveSoft, other.liveSoft),
      soon: l(soon, other.soon),
      warnBg: l(warnBg, other.warnBg),
      warnInk: l(warnInk, other.warnInk),
      dangerBg: l(dangerBg, other.dangerBg),
      dangerInk: l(dangerInk, other.dangerInk),
    );
  }
}

/// Type scale (spec §4.3). Every style sets `decoration: none` so text never
/// shows Flutter's "missing Material" debug underline, and a solid
/// `decorationStyle`, so a strike-through added later is one line, not the
/// fallback's double line.
@immutable
class BBText {
  const BBText({
    required this.display,
    required this.title,
    required this.headline,
    required this.body,
    required this.label,
    required this.caption,
    required this.minutes,
    required this.minutesUnit,
  });

  static const family = 'Figtree';

  final TextStyle display;
  final TextStyle title;
  final TextStyle headline;
  final TextStyle body;
  final TextStyle label;
  final TextStyle caption;

  /// Arrival minutes: tabular figures so digits don't jitter as they change.
  final TextStyle minutes;
  final TextStyle minutesUnit;

  factory BBText.of(BBColors c) {
    TextStyle s(double size, FontWeight weight, {Color? color, double? spacing, double? height}) {
      return TextStyle(
        fontFamily: family,
        fontSize: size,
        fontWeight: weight,
        color: color ?? c.ink,
        letterSpacing: spacing,
        height: height,
        decoration: TextDecoration.none,
        decorationStyle: TextDecorationStyle.solid,
      );
    }

    return BBText(
      display: s(28, FontWeight.w800, spacing: -0.56, height: 1.15),
      title: s(22, FontWeight.w800, spacing: -0.22, height: 1.2),
      headline: s(17, FontWeight.w700, height: 1.25),
      body: s(15, FontWeight.w500, height: 1.4),
      label: s(13, FontWeight.w700, height: 1.25),
      caption: s(12, FontWeight.w500, color: c.muted, height: 1.3),
      minutes: s(26, FontWeight.w800, height: 1.0)
          .copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
      minutesUnit: s(11, FontWeight.w600, color: c.muted, height: 1.1),
    );
  }

  BBText lerp(BBText o, double t) {
    TextStyle l(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return BBText(
      display: l(display, o.display),
      title: l(title, o.title),
      headline: l(headline, o.headline),
      body: l(body, o.body),
      label: l(label, o.label),
      caption: l(caption, o.caption),
      minutes: l(minutes, o.minutes),
      minutesUnit: l(minutesUnit, o.minutesUnit),
    );
  }
}

/// 4-pt spacing scale (spec §4.4).
abstract final class BBSpace {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 12;
  static const double l = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
  static const double screen = 16;
}

abstract final class BBRadius {
  static const double pill = 8;
  static const double badge = 12;
  static const double button = 14;
  static const double card = 16;
  static const double sheet = 24;
}

/// The motion system (visual refresh spec §3.1). Everything honours Reduce Motion
/// (`MediaQuery.disableAnimations`): [of] gives zero, [spring] a near-instant spring,
/// and loops don't run at all.
abstract final class BBMotion {
  /// Presses, toggles.
  static const quick = Duration(milliseconds: 120);

  /// Most fades and slides.
  static const standard = Duration(milliseconds: 220);

  /// Sheets snapping to detents, cards entering, the picker sheet (with [emphasisCurve]).
  static const emphasis = Duration(milliseconds: 360);

  /// Between list items as they enter, for at most [staggerMax] steps.
  static const stagger = Duration(milliseconds: 40);
  static const int staggerMax = 8;

  /// One live-dot breath cycle.
  static const pulse = Duration(milliseconds: 1600);

  /// A row becoming "Now": one scale 1 → 1.08 → 1.
  static const nowPulse = Duration(milliseconds: 600);

  static const Curve curve = Curves.easeOutCubic;

  /// Damping ratio ≈ 0.78, stiffness ≈ 260: a slight overshoot.
  static final SpringDescription emphasisSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 260, ratio: 0.78);

  /// Reduce Motion: critically damped and stiff, so it settles in a few milliseconds.
  static final SpringDescription reducedSpring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 10000, ratio: 1);

  /// [emphasisSpring] over [emphasis], for controller-driven motion.
  static final Curve emphasisCurve = BBSpringCurve(emphasisSpring, emphasis);

  /// Whether the user has asked the OS to reduce motion.
  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) == true;

  /// [d], or zero when the user has asked the OS to reduce motion.
  static Duration of(BuildContext context, Duration d) => reduced(context) ? Duration.zero : d;

  /// The emphasis spring, or a near-instant critically damped one under Reduce Motion.
  static SpringDescription spring(BuildContext context) => reduced(context) ? reducedSpring : emphasisSpring;
}

/// [spring] from 0 to 1 over [duration] as a [Curve], for AnimationController-driven motion.
/// It may overshoot 1 a little on the way; a linear correction lands it exactly on 1 at the end,
/// so the last frame doesn't jump.
class BBSpringCurve extends Curve {
  const BBSpringCurve(this.spring, this.duration);

  final SpringDescription spring;
  final Duration duration;

  @override
  double transformInternal(double t) {
    final seconds = duration.inMicroseconds / Duration.microsecondsPerSecond;
    final sim = SpringSimulation(spring, 0, 1, 0);
    return sim.x(t * seconds) + (1 - sim.x(seconds)) * t;
  }
}

/// Dimmed backdrops behind dialogs and floating cards: neutral black (spec 2026-10-14 §2.1). Dark is heavier, since
/// dark surfaces are already deep and a faint dim would not lift a card off the sheet under it. Every modal card
/// (dialogs, the picker, the small cards that open over the map) uses [strongOf], so they all dim alike.
abstract final class BBScrim {
  static const Color soft = Color(0x33000000); // black, 20 %
  static const Color strong = Color(0x66000000); // black, 40 %
  static const Color softDark = Color(0x59000000); // black, 35 %
  static const Color strongDark = Color(0x99000000); // black, 60 %

  static Color softOf(BuildContext context) => context.bb.isDark ? softDark : soft;
  static Color strongOf(BuildContext context) => context.bb.isDark ? strongDark : strong;
}

@immutable
class BBTokens extends ThemeExtension<BBTokens> {
  const BBTokens({required this.brightness, required this.colors, required this.text});

  final Brightness brightness;
  final BBColors colors;
  final BBText text;

  static final light = BBTokens(
    brightness: Brightness.light,
    colors: BBColors.light,
    text: BBText.of(BBColors.light),
  );

  static final dark = BBTokens(
    brightness: Brightness.dark,
    colors: BBColors.dark,
    text: BBText.of(BBColors.dark),
  );

  bool get isDark => brightness == Brightness.dark;

  /// Focus rings and selection edges: `brand` in dark; the deeper `brandInk` in light, which keeps
  /// every edge well over 3:1 on white and on `brandSoft` (WCAG 1.4.11).
  Color get brandEdge => isDark ? colors.brand : colors.brandInk;

  /// Dark floating layers: a deep black shadow (45–55%). Light: a soft black one (8–14%). Neutral in both.
  List<BoxShadow> get _floatShadow => isDark
      ? const [BoxShadow(color: Color(0x80000000), blurRadius: 24, offset: Offset(0, 8))]
      : const [BoxShadow(color: Color(0x23000000), blurRadius: 16, offset: Offset(0, 4))];

  /// Dark layers catch the light on their top edge: a 1 px `highlight`. Light mode has none.
  Border? get _topEdge => isDark ? Border(top: BorderSide(color: colors.highlight)) : null;

  /// Floating layers: sheets, panels, dialogs, toasts, banners. `surface` (or [color]) with the
  /// float shadow; in dark, the top-edge highlight too.
  BoxDecoration floating({double radius = BBRadius.card, BorderRadius? borderRadius, Color? color}) {
    return BoxDecoration(
      color: color ?? colors.surface,
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
      boxShadow: _floatShadow,
      border: _topEdge,
    );
  }

  /// Buttons and chips floating on the map (bell, gear, location, route chip): `surfaceFloat`,
  /// or the brand fill when [selected].
  BoxDecoration mapControl({double radius = 22, bool selected = false}) =>
      floating(radius: radius, color: selected ? colors.brand : colors.surfaceFloat);

  /// A card: `surface` on a page, `surfaceRaised` on a sheet or panel ([raised]). Light: white with
  /// a faint black shadow. Dark: the top-edge highlight, depth from lightness alone.
  BoxDecoration card({double radius = BBRadius.card, bool raised = false}) {
    return BoxDecoration(
      color: raised ? colors.surfaceRaised : colors.surface,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: isDark ? null : const [BoxShadow(color: Color(0x15000000), blurRadius: 8, offset: Offset(0, 2))],
      border: _topEdge,
    );
  }

  /// A field (text field, Where to?, the When row, segmented track, stepper, chips on a sheet):
  /// `surfaceField` with a 1.5 px `line` outline; [focused], a 2 px [brandEdge] ring; [error], a
  /// `dangerInk` outline. Never `surfaceSunken` (spec §2.2).
  BoxDecoration field({double radius = BBRadius.button, bool focused = false, bool error = false}) {
    return BoxDecoration(
      color: colors.surfaceField,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: error ? colors.dangerInk : (focused ? brandEdge : colors.line),
        width: focused ? 2 : 1.5,
      ),
    );
  }

  @override
  BBTokens copyWith({Brightness? brightness, BBColors? colors, BBText? text}) {
    return BBTokens(
      brightness: brightness ?? this.brightness,
      colors: colors ?? this.colors,
      text: text ?? this.text,
    );
  }

  @override
  BBTokens lerp(covariant BBTokens? other, double t) {
    if (other == null) return this;
    return BBTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      colors: colors.lerp(other.colors, t),
      text: text.lerp(other.text, t),
    );
  }
}

extension BBContext on BuildContext {
  BBTokens get bb => Theme.of(this).extension<BBTokens>()!;
}
