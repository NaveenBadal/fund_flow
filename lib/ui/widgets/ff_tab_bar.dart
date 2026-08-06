import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ff_theme.dart';
import 'ff_pressable.dart';

const double kFFTabBarHeight = 49;

class FFTab {
  const FFTab({required this.label, required this.icon, required this.active});
  final String label;
  final IconData icon;

  /// The filled counterpart, shown when this tab is the one you are on.
  final IconData active;
}

/// The tab bar. Translucent, so content is visibly continuing beneath it
/// rather than ending at an opaque strip.
class FFTabBar extends StatelessWidget {
  const FFTabBar({
    super.key,
    required this.tabs,
    required this.index,
    required this.onChanged,
    this.badges = const {},
  });

  final List<FFTab> tabs;
  final int index;
  final ValueChanged<int> onChanged;

  /// Tab index to a count worth interrupting someone about.
  final Map<int, int> badges;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.chrome,
            border: Border(
              top: BorderSide(
                color: c.opaqueSeparator,
                width: 1 / MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
          child: SizedBox(
            height: kFFTabBarHeight + bottom,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottom),
              child: Row(
                children: [
                  for (var i = 0; i < tabs.length; i++)
                    Expanded(
                      child: _TabItem(
                        tab: tabs[i],
                        selected: i == index,
                        badge: badges[i],
                        onTap: () {
                          if (i == index) return;
                          HapticFeedback.selectionClick();
                          onChanged(i);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.tab,
    required this.selected,
    required this.onTap,
    this.badge,
  });

  final FFTab tab;
  final bool selected;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final color = selected ? c.tint : c.secondaryLabel;
    return FFPressable(
      onTap: onTap,
      selected: selected,
      semanticLabel: tab.label,
      dim: .5,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            height: 26,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(selected ? tab.active : tab.icon, size: 25, color: color),
                if (badge != null && badge! > 0)
                  Positioned(
                    right: -7,
                    top: -3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: c.red,
                        borderRadius: BorderRadius.circular(FFRadius.pill),
                      ),
                      child: Text(
                        badge! > 99 ? '99+' : '$badge',
                        textAlign: TextAlign.center,
                        style: FFText.caption2.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            tab.label,
            style: FFText.caption2.copyWith(
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
