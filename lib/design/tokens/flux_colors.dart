import 'package:flutter/widgets.dart';

/// Every colour Flux draws with, as one role set expressed twice.
///
/// Light and dark are two values of the same roles, so a screen picks a role
/// and never a literal. Two earlier attempts at this app drifted because
/// screens reached for hex values locally; a role set is the only thing that
/// keeps forty surfaces looking like one product.
///
/// Two decisions here are load-bearing and easy to undo by accident:
///
/// * The background is never pure black. `#000000` collapses the distance
///   between the background and the first surface, and dark elevation in Flux
///   is expressed by stepping surfaces rather than by shadows, which are
///   invisible on dark. Pure black would leave nothing to step from.
/// * [outflow] is the primary text colour, not red. Spending money is the
///   normal operation of a spend tracker, and painting it as a warning makes
///   an ordinary week look like a crisis. Colour is reserved for money
///   arriving, for something that needs a person, and for damage.
@immutable
class FluxPalette {
  const FluxPalette({
    required this.isDark,
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHighest,
    required this.line,
    required this.lineStrong,
    required this.text,
    required this.textMuted,
    required this.textFaint,
    required this.iris,
    required this.irisPressed,
    required this.irisSoft,
    required this.onIris,
    required this.income,
    required this.attention,
    required this.attentionSoft,
    required this.danger,
    required this.dangerSoft,
    required this.highlight,
    required this.scrim,
    required this.shadow,
    required this.categorical,
  });

  final bool isDark;

  /// Page background — the lowest layer.
  final Color background;

  /// Cards and grouped rows sitting on [background].
  final Color surface;

  /// Sheets, and anything sitting on [surface].
  final Color surfaceRaised;

  /// Chips, fills and pressed states on top of [surfaceRaised].
  final Color surfaceHighest;

  /// Hairline separators inside lists.
  final Color line;

  /// Borders that must read as an edge rather than a separation.
  final Color lineStrong;

  final Color text;
  final Color textMuted;
  final Color textFaint;

  /// The only hue that means "interactive" or "the app is working".
  final Color iris;
  final Color irisPressed;

  /// Iris at fill strength, for selected chips and tinted containers.
  final Color irisSoft;
  final Color onIris;

  /// Money arriving.
  final Color income;

  /// Something needs a person: review, over budget, unusual charge.
  final Color attention;
  final Color attentionSoft;

  /// Destructive or broken. Never used for ordinary spending.
  final Color danger;
  final Color dangerSoft;

  /// The 1px inner top edge that gives dark surfaces their lift.
  final Color highlight;

  final Color scrim;
  final Color shadow;

  /// The eight categorical chart hues, in a fixed order.
  ///
  /// The *order* is the colour-blindness safety mechanism, not a cosmetic
  /// choice: adjacent slots are what land next to each other in a stacked bar
  /// or a donut, so the sequence was validated rather than picked. A first
  /// hand-tuned set failed — clay against amber came out ΔE 2.0 under
  /// deuteranopia, and the slate slot read as grey — which is why these are
  /// the hues and the sequence that passed both modes:
  ///
  ///   light  worst adjacent CVD ΔE 9.1, normal-vision ΔE 19.6
  ///   dark   worst adjacent CVD ΔE 8.4, normal-vision ΔE 19.3
  ///
  /// Three light-mode hues (aqua, yellow, magenta) sit under 3:1 against a
  /// white surface, so every chart that uses them carries a visible direct
  /// label — the donut names its slices, the breakdown labels its rows. Do not
  /// add a chart that relies on those fills alone.
  ///
  /// Dark is not a brightened copy of light: each hue is stepped for the dark
  /// surface and the set was validated again there.
  final List<Color> categorical;

  /// For categories that are not spending at all, and for everything past the
  /// eight slots. Grey by intent — folding an overflow category into a neutral
  /// is correct, generating a ninth hue is not.
  Color get neutralCategory =>
      isDark ? const Color(0xFF9AA4B2) : const Color(0xFF6B7280);

  /// Money leaving. Deliberately the text colour: see the class comment.
  Color get outflow => text;

  Color moneyColor({required bool incoming}) => incoming ? income : outflow;

  /// Which slot each known category owns.
  ///
  /// Fixed per category rather than derived from rank, so filtering a chart
  /// down to three categories does not repaint them — Food is the same colour
  /// in the donut, in the breakdown, and on the glyph of every row, in every
  /// filtered state. Transfer is neutral because moving money between your own
  /// accounts is not spending, and giving it a hue puts it in visual
  /// competition with categories that are.
  static const Map<String, int> _categorySlots = {
    'food': 0,
    'groceries': 1,
    'transport': 2,
    'shopping': 3,
    'bills': 4,
    'health': 5,
    'entertainment': 6,
    'subscriptions': 7,
    // Income categories reuse the slots: a chart is either spending or income,
    // never both, so the two sets never collide inside one chart.
    'salary': 0,
    'income': 1,
    'refund': 2,
    'cashback': 3,
    'interest': 4,
    'business': 5,
  };

  Color forCategory(String category) {
    final slot = _categorySlots[category.trim().toLowerCase()];
    return slot == null ? neutralCategory : categorical[slot];
  }

  static const dark = FluxPalette(
    isDark: true,
    background: Color(0xFF0A0A0F),
    surface: Color(0xFF131319),
    surfaceRaised: Color(0xFF1B1B22),
    surfaceHighest: Color(0xFF24242C),
    line: Color(0x14FFFFFF),
    lineStrong: Color(0x24FFFFFF),
    text: Color(0xFFF5F5F7),
    textMuted: Color(0xFFA0A0AB),
    textFaint: Color(0xFF6E6E78),
    iris: Color(0xFF7B7BEB),
    irisPressed: Color(0xFF9797F2),
    irisSoft: Color(0x2E5B5BD6),
    onIris: Color(0xFF0A0A0F),
    income: Color(0xFF34D399),
    attention: Color(0xFFFBBF24),
    attentionSoft: Color(0x24FBBF24),
    danger: Color(0xFFF87171),
    dangerSoft: Color(0x24F87171),
    highlight: Color(0x0FFFFFFF),
    scrim: Color(0x99000000),
    shadow: Color(0x00000000),
    categorical: [
      Color(0xFF9085E9), // violet
      Color(0xFFD95926), // orange
      Color(0xFF199E70), // aqua
      Color(0xFFC98500), // yellow
      Color(0xFFD55181), // magenta
      Color(0xFF008300), // green
      Color(0xFF3987E5), // blue
      Color(0xFFE66767), // red
    ],
  );

  static const light = FluxPalette(
    isDark: false,
    background: Color(0xFFFAFAFC),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceHighest: Color(0xFFF2F2F7),
    line: Color(0x140A0A0F),
    lineStrong: Color(0x1F0A0A0F),
    text: Color(0xFF0A0A0F),
    textMuted: Color(0xFF5C5C66),
    textFaint: Color(0xFF8E8E98),
    iris: Color(0xFF5B5BD6),
    irisPressed: Color(0xFF4A48C4),
    irisSoft: Color(0x1F5B5BD6),
    onIris: Color(0xFFFFFFFF),
    income: Color(0xFF0E8F5F),
    attention: Color(0xFFB45309),
    attentionSoft: Color(0x1FB45309),
    danger: Color(0xFFC6293B),
    dangerSoft: Color(0x1FC6293B),
    highlight: Color(0x00000000),
    scrim: Color(0x66000000),
    shadow: Color(0x140A0A0F),
    categorical: [
      Color(0xFF4A3AA7), // violet
      Color(0xFFEB6834), // orange
      Color(0xFF1BAF7A), // aqua
      Color(0xFFEDA100), // yellow
      Color(0xFFE87BA4), // magenta
      Color(0xFF008300), // green
      Color(0xFF2A78D6), // blue
      Color(0xFFE34948), // red
    ],
  );

  /// The one gradient in the app. Only ever on agent affordances — the
  /// composer's focus edge, the thinking sweep, the active Ask tab.
  static const List<Color> aiGradient = [
    Color(0xFF5B5BD6),
    Color(0xFF7C5CE6),
    Color(0xFF22A6C3),
  ];

  static LinearGradient get ai => const LinearGradient(
    colors: aiGradient,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
