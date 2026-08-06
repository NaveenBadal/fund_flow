import 'package:flutter/cupertino.dart' show NoDefaultCupertinoThemeData;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The palette.
///
/// Roles, not colours. Every surface in the app names what it is — a grouped
/// background, a secondary label, a separator — so light and dark are two
/// values of one idea rather than two designs kept in sync by hand.
///
/// The scale follows Apple's system palette because it is the most carefully
/// tuned set of neutrals in wide use: the greys are not desaturated blacks,
/// they carry a faint blue cast that keeps large fields from looking muddy.
@immutable
class FFColors extends ThemeExtension<FFColors> {
  const FFColors({
    required this.background,
    required this.groupedBackground,
    required this.card,
    required this.elevated,
    required this.label,
    required this.secondaryLabel,
    required this.tertiaryLabel,
    required this.quaternaryLabel,
    required this.separator,
    required this.opaqueSeparator,
    required this.fill,
    required this.secondaryFill,
    required this.tint,
    required this.onTint,
    required this.green,
    required this.red,
    required this.orange,
    required this.greenFill,
    required this.redFill,
    required this.orangeFill,
    required this.chrome,
  });

  /// Behind plain, ungrouped content.
  final Color background;

  /// Behind grouped lists. In light this is the grey the cards sit on; in
  /// dark it inverts — the page goes black and the cards lift to grey.
  final Color groupedBackground;

  /// An inset group, or any raised block of content.
  final Color card;

  /// Sheets and popovers, which sit above cards.
  final Color elevated;

  final Color label;
  final Color secondaryLabel;
  final Color tertiaryLabel;
  final Color quaternaryLabel;

  /// Hairline between rows. Translucent so it darkens whatever it crosses.
  final Color separator;

  /// Hairline that must stay visible over a blurred bar.
  final Color opaqueSeparator;

  /// Fill behind search fields, segmented controls, unselected chips.
  final Color fill;
  final Color secondaryFill;

  /// The one interactive colour. Anything tinted is something you can press.
  final Color tint;
  final Color onTint;

  /// Reserved for money and state, and darkened in light mode so they pass
  /// contrast as *text*. Green is never a button.
  final Color green;
  final Color red;
  final Color orange;

  /// The same three at full saturation, for shapes rather than text — a glyph
  /// tile, a chart bar, a badge. White sits legibly on all of them, and
  /// darkening them the way text needs would make them look muddy.
  final Color greenFill;
  final Color redFill;
  final Color orangeFill;

  /// The translucent wash behind nav bars and the tab bar.
  final Color chrome;

  static const light = FFColors(
    background: Color(0xffffffff),
    groupedBackground: Color(0xfff2f2f7),
    card: Color(0xffffffff),
    elevated: Color(0xffffffff),
    label: Color(0xff000000),
    secondaryLabel: Color(0x993c3c43),
    tertiaryLabel: Color(0x4d3c3c43),
    quaternaryLabel: Color(0x2e3c3c43),
    separator: Color(0x4a3c3c43),
    opaqueSeparator: Color(0xffc6c6c8),
    fill: Color(0x1f787880),
    secondaryFill: Color(0x14787880),
    tint: Color(0xff007aff),
    onTint: Color(0xffffffff),
    green: Color(0xff248a3d),
    red: Color(0xffd70015),
    orange: Color(0xffc93400),
    greenFill: Color(0xff34c759),
    redFill: Color(0xffff3b30),
    orangeFill: Color(0xffff9500),
    chrome: Color(0xf2f9f9f9),
  );

  static const dark = FFColors(
    background: Color(0xff000000),
    groupedBackground: Color(0xff000000),
    card: Color(0xff1c1c1e),
    elevated: Color(0xff1c1c1e),
    label: Color(0xffffffff),
    secondaryLabel: Color(0x99ebebf5),
    tertiaryLabel: Color(0x4debebf5),
    quaternaryLabel: Color(0x29ebebf5),
    separator: Color(0xa6545458),
    opaqueSeparator: Color(0xff38383a),
    fill: Color(0x5c787880),
    secondaryFill: Color(0x3d787880),
    tint: Color(0xff0a84ff),
    onTint: Color(0xffffffff),
    green: Color(0xff30d158),
    red: Color(0xffff453a),
    orange: Color(0xffff9f0a),
    greenFill: Color(0xff30d158),
    redFill: Color(0xffff453a),
    orangeFill: Color(0xffff9f0a),
    chrome: Color(0xf21d1d1d),
  );

  @override
  FFColors copyWith() => this;

  @override
  FFColors lerp(covariant FFColors? other, double t) =>
      t < .5 ? this : (other ?? this);
}

/// The type ramp.
///
/// Sizes and tracking follow the SF ramp, set in Inter. Optical tracking is
/// what makes large type read as designed rather than merely large: SF tightens
/// as it grows, and copying only the sizes is what makes a knock-off obvious.
abstract final class FFText {
  static const _family = 'Inter';

  static TextStyle _s(
    double size,
    FontWeight weight,
    double tracking, {
    double height = 1.3,
  }) => TextStyle(
    fontFamily: _family,
    fontSize: size,
    fontWeight: weight,
    letterSpacing: tracking,
    height: height,
  );

  /// Money, and nothing else.
  static final money = _s(44, FontWeight.w700, -1.4, height: 1.05);
  static final moneyLarge = _s(56, FontWeight.w700, -2, height: 1.02);

  static final largeTitle = _s(34, FontWeight.w700, -.7, height: 1.15);
  static final title1 = _s(28, FontWeight.w700, -.5, height: 1.2);
  static final title2 = _s(22, FontWeight.w700, -.4, height: 1.25);
  static final title3 = _s(20, FontWeight.w600, -.35, height: 1.25);
  static final headline = _s(17, FontWeight.w600, -.25, height: 1.3);
  static final body = _s(17, FontWeight.w400, -.25, height: 1.4);
  static final callout = _s(16, FontWeight.w400, -.2, height: 1.35);
  static final subhead = _s(15, FontWeight.w400, -.15, height: 1.35);
  static final footnote = _s(13, FontWeight.w400, -.05, height: 1.35);
  static final caption = _s(12, FontWeight.w400, 0, height: 1.3);
  static final caption2 = _s(11, FontWeight.w500, .05, height: 1.25);

  /// Figures that must line up in a column.
  static const tabular = [FontFeature.tabularFigures()];
}

/// Spacing scale. Multiples of four, with 16 as the page gutter iOS uses.
abstract final class FFSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double huge = 44;

  /// Horizontal page inset. Grouped content aligns to this everywhere.
  static const double gutter = 16;
}

abstract final class FFRadius {
  /// Inset group cards.
  static const double group = 12;

  /// Buttons and fields.
  static const double control = 12;

  /// Sheets.
  static const double sheet = 16;

  /// Alerts.
  static const double alert = 14;

  /// Anything capsule-shaped.
  static const double pill = 999;
}

extension FFContext on BuildContext {
  FFColors get ff => Theme.of(this).extension<FFColors>()!;
  bool get ffDark => Theme.of(this).brightness == Brightness.dark;

  /// Whether the person has asked the system to cut animation.
  bool get ffStill => MediaQuery.maybeOf(this)?.disableAnimations ?? false;
}

abstract final class FFTheme {
  static ThemeData light() => _make(Brightness.light, FFColors.light);
  static ThemeData dark() => _make(Brightness.dark, FFColors.dark);

  static ThemeData _make(Brightness brightness, FFColors c) {
    final text = TextTheme(
      displayLarge: FFText.money,
      displayMedium: FFText.largeTitle,
      displaySmall: FFText.title1,
      headlineLarge: FFText.title1,
      headlineMedium: FFText.title2,
      headlineSmall: FFText.title3,
      titleLarge: FFText.title3,
      titleMedium: FFText.headline,
      titleSmall: FFText.subhead.copyWith(fontWeight: FontWeight.w600),
      bodyLarge: FFText.body,
      bodyMedium: FFText.callout,
      bodySmall: FFText.footnote,
      labelLarge: FFText.headline,
      labelMedium: FFText.footnote.copyWith(fontWeight: FontWeight.w600),
      labelSmall: FFText.caption2,
    ).apply(bodyColor: c.label, displayColor: c.label);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: c.groupedBackground,
      canvasColor: c.background,
      textTheme: text,
      // Nothing in this interface ripples. Apple's press feedback is a
      // short opacity dip on the element itself, applied by FFPressable.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      dividerColor: c.separator,
      dividerTheme: DividerThemeData(color: c.separator, space: 0, thickness: 0),
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: c.tint,
            brightness: brightness,
          ).copyWith(
            primary: c.tint,
            onPrimary: c.onTint,
            surface: c.background,
            onSurface: c.label,
            error: c.red,
            outline: c.separator,
          ),
      iconTheme: IconThemeData(color: c.label, size: 22),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: c.tint,
        selectionColor: c.tint.withValues(alpha: .28),
        selectionHandleColor: c.tint,
      ),
      cupertinoOverrideTheme: NoDefaultCupertinoThemeData(
        brightness: brightness,
        primaryColor: c.tint,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        systemOverlayStyle: brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.tint,
        linearTrackColor: c.fill,
        circularTrackColor: Colors.transparent,
        linearMinHeight: 4,
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FFPageTransition(),
          TargetPlatform.iOS: FFPageTransition(),
          TargetPlatform.macOS: FFPageTransition(),
        },
      ),
      extensions: [c],
    );
  }
}

/// The push someone expects: the new page slides in from the trailing edge
/// while the old one drifts a third of the way out under a dimming veil.
class FFPageTransition extends PageTransitionsBuilder {
  const FFPageTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondary,
    Widget child,
  ) {
    if (context.ffStill) return child;
    const curve = Curves.fastEaseInToSlowEaseOut;
    final enter = CurvedAnimation(parent: animation, curve: curve);
    final exit = CurvedAnimation(parent: secondary, curve: curve);
    return SlideTransition(
      position: Tween(
        begin: Offset.zero,
        end: const Offset(-.28, 0),
      ).animate(exit),
      child: DecoratedBoxTransition(
        position: DecorationPosition.foreground,
        decoration: DecorationTween(
          begin: const BoxDecoration(color: Color(0x00000000)),
          end: const BoxDecoration(color: Color(0x26000000)),
        ).animate(exit),
        child: SlideTransition(
          position: Tween(
            begin: const Offset(1, 0),
            end: Offset.zero,
          ).animate(enter),
          child: child,
        ),
      ),
    );
  }
}
