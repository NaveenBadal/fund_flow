import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// The glyph on a ledger row.
///
/// A merchant has no logo the app can fetch — the data came out of an SMS —
/// so the identity is built from the name itself: its initials on a tint
/// derived from the category. That gives every row a stable, recognisable mark
/// without a network request, and it means the colour on the row matches the
/// colour of that category in the donut above it.
class FluxAvatar extends StatelessWidget {
  const FluxAvatar({
    super.key,
    required this.name,
    required this.tint,
    this.size = 40,
    this.icon,
  });

  final String name;
  final Color tint;
  final double size;

  /// Replaces the initials, for rows that represent a thing rather than a
  /// merchant (an income deposit, a transfer).
  final IconData? icon;

  String get _initials {
    final words = name
        .trim()
        .split(RegExp(r'[\s\-_/]+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final word = words.first;
      return word.length == 1
          ? word.toUpperCase()
          : word.substring(0, 2).toUpperCase();
    }
    return '${words.first[0]}${words[1][0]}'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: tint.withValues(alpha: palette.isDark ? 0.20 : 0.13),
          shape: FluxRadius.shape(size / 2.6),
        ),
        child: Center(
          child: icon != null
              ? Icon(icon, size: size * 0.46, color: tint)
              : Text(
                  _initials,
                  style: FluxType.label.copyWith(
                    color: tint,
                    fontSize: size * 0.33,
                  ),
                ),
        ),
      ),
    );
  }
}
