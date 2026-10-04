import 'package:flutter/material.dart';

/// Colour roles for one brightness (spec §4.1, contrast-amended).
/// Raw colour values live only here and in route_palette.dart.
@immutable
class BBColors {
  const BBColors({
    required this.bg,
    required this.surface,
    required this.surfaceSunken,
    required this.line,
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

  final Color bg;
  final Color surface;
  final Color surfaceSunken;
  final Color line;
  final Color ink;
  final Color muted;
  final Color brand;
  final Color onBrand;
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
    bg: Color(0xFFF7F2EA),
    surface: Color(0xFFFFFFFF),
    surfaceSunken: Color(0xFFEFE7DA),
    line: Color(0xFFECE4D8),
    ink: Color(0xFF1C2A3A),
    muted: Color(0xFF5A6674),
    brand: Color(0xFF3C79AE),
    onBrand: Color(0xFFFFFFFF),
    brandInk: Color(0xFF2C5F8E),
    brandSoft: Color(0xFFDCE8F4),
    live: Color(0xFF2BA36B),
    liveInk: Color(0xFF1B7048),
    liveSoft: Color(0xFFDDF1E6),
    soon: Color(0xFFD9480F),
    warnBg: Color(0xFFFDEBD3),
    warnInk: Color(0xFF8A4B08),
    dangerBg: Color(0xFFFBD9D6),
    dangerInk: Color(0xFF9B1C1C),
  );

  static const dark = BBColors(
    bg: Color(0xFF0F1720),
    surface: Color(0xFF18222E),
    surfaceSunken: Color(0xFF121B25),
    line: Color(0xFF243140),
    ink: Color(0xFFF2EDE4),
    muted: Color(0xFF8E9AA8),
    brand: Color(0xFF6FA6DA),
    onBrand: Color(0xFF0F1720),
    brandInk: Color(0xFF8DBBE6),
    brandSoft: Color(0xFF1D3348),
    live: Color(0xFF4CC38A),
    liveInk: Color(0xFF4CC38A),
    liveSoft: Color(0xFF16332A),
    soon: Color(0xFFFF8A5B),
    warnBg: Color(0xFF3A2A14),
    warnInk: Color(0xFFF5C27A),
    dangerBg: Color(0xFF3A1A1A),
    dangerInk: Color(0xFFF5A3A3),
  );

  BBColors lerp(BBColors other, double t) {
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return BBColors(
      bg: l(bg, other.bg),
      surface: l(surface, other.surface),
      surfaceSunken: l(surfaceSunken, other.surfaceSunken),
      line: l(line, other.line),
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
/// shows Flutter's "missing Material" debug underline.
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

abstract final class BBMotion {
  static const standard = Duration(milliseconds: 200);
  static const press = Duration(milliseconds: 120);
  static const sheet = Duration(milliseconds: 300);
  static const Curve curve = Curves.easeOutCubic;

  /// [d], or zero when the user has asked the OS to reduce motion.
  static Duration of(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
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

  /// Floating elements: nav bar, chips, sheets, dialogs, toasts. The one
  /// shadow in light mode; a hairline border instead in dark mode.
  BoxDecoration floating({double radius = BBRadius.card, BorderRadius? borderRadius}) {
    return BoxDecoration(
      color: colors.surface,
      borderRadius: borderRadius ?? BorderRadius.circular(radius),
      boxShadow: isDark
          ? null
          : const [BoxShadow(color: Color(0x241C2A3A), blurRadius: 16, offset: Offset(0, 4))],
      border: isDark ? Border.all(color: colors.line) : null,
    );
  }

  /// Flat in-page surface (cards in lists).
  BoxDecoration card({double radius = BBRadius.card}) {
    return BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(radius),
      border: isDark ? Border.all(color: colors.line) : null,
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
