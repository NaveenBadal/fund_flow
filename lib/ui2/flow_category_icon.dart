import 'package:flutter/material.dart';

import 'tokens/flow_palette.dart';

/// An icon and a colour for a category name.
///
/// A ledger of nothing but text reads as a spreadsheet. A tinted avatar per
/// row is what lets the eye find "the food one" without reading, and the
/// colour ties a row to the same category's slice in a chart.
///
/// Keyed loosely: the model and hand corrections both produce category names,
/// and "Dining" should still find the fork even though the canonical label is
/// "Food". Anything unmatched falls back to a neutral receipt so a row is
/// never left blank.
abstract final class FlowCategoryIcon {
  static const _icons = <String, IconData>{
    'food': Icons.restaurant_rounded,
    'dining': Icons.restaurant_rounded,
    'groceries': Icons.local_grocery_store_rounded,
    'grocery': Icons.local_grocery_store_rounded,
    'transport': Icons.directions_car_rounded,
    'travel': Icons.flight_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'bills': Icons.receipt_long_rounded,
    'utilities': Icons.bolt_rounded,
    'health': Icons.favorite_rounded,
    'medical': Icons.local_hospital_rounded,
    'entertainment': Icons.movie_rounded,
    'subscriptions': Icons.autorenew_rounded,
    'subscription': Icons.autorenew_rounded,
    'transfer': Icons.swap_horiz_rounded,
    'income': Icons.savings_rounded,
    'salary': Icons.payments_rounded,
    'rent': Icons.home_rounded,
    'education': Icons.school_rounded,
    'insurance': Icons.shield_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'other': Icons.receipt_rounded,
  };

  /// Fixed slot per common category, so the everyday ones get distinct hues
  /// rather than whatever a hash happens to collide on — hashing alone put
  /// Food, Health, Insurance and Subscriptions on nearly the same red.
  static const _slots = <String, int>{
    'food': 3, // amber
    'dining': 3,
    'groceries': 2, // emerald
    'transport': 1, // cyan
    'shopping': 0, // indigo
    'bills': 5, // slate
    'health': 4, // rose
    'medical': 4,
    'entertainment': 2,
    'subscriptions': 0,
    'transfer': 5,
    'insurance': 1,
  };

  /// A stable colour for [category], drawn from the validated series palette
  /// so a category is the same hue here and in every chart. Known categories
  /// take a fixed slot; anything the model invents is hashed into one so it
  /// still gets a consistent colour rather than defaulting to slot zero.
  static Color color(String category, FlowColors flow) {
    final key = category.trim().toLowerCase();
    if (key.isEmpty) return flow.inkFaint;
    final slot = _slots[key];
    if (slot != null) return flow.seriesAt(slot);
    var hash = 0;
    for (final unit in key.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return flow.seriesAt(hash % flow.series.length);
  }

  static IconData icon(String category) {
    final key = category.trim().toLowerCase();
    return _icons[key] ?? Icons.receipt_rounded;
  }
}

/// The round, tinted category mark used on transaction rows.
class FlowCategoryAvatar extends StatelessWidget {
  const FlowCategoryAvatar({super.key, required this.category, this.size = 38});

  final String category;
  final double size;

  @override
  Widget build(BuildContext context) {
    final flow = context.flow;
    final tint = FlowCategoryIcon.color(category, flow);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: .16),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Icon(
        FlowCategoryIcon.icon(category),
        size: size * .5,
        color: tint,
      ),
    );
  }
}
