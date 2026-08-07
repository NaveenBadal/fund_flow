import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../design/flux.dart';

const double kFluxNavBarHeight = 60;

@immutable
class FluxNavItem {
  const FluxNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.gradient = false,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;

  /// Paints the active glyph with the AI gradient. Reserved for Ask — it is
  /// the one destination where something is generated rather than looked up,
  /// and the gradient is the only place in the app that says so.
  final bool gradient;
}

/// The tab bar: frosted, with the active label carrying the weight.
///
/// The indicator is the icon and label themselves rather than a pill or a bar.
/// Three destinations do not need a marker to be countable, and a moving pill
/// competes with the content scrolling underneath the glass.
class FluxNavBar extends StatelessWidget {
  const FluxNavBar({
    super.key,
    required this.index,
    required this.items,
    required this.onChanged,
  });

  final int index;
  final List<FluxNavItem> items;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return FluxGlass(
      opacity: 0.8,
      border: Border(top: BorderSide(color: palette.line, width: 1)),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: kFluxNavBarHeight,
          child: Row(
            children: [
              for (var slot = 0; slot < items.length; slot++)
                Expanded(
                  child: _NavButton(
                    item: items[slot],
                    active: slot == index,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onChanged(slot);
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final FluxNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final color = active ? palette.text : palette.textFaint;

    Widget glyph = Icon(
      active ? item.activeIcon : item.icon,
      size: 24,
      color: color,
    );
    if (active && item.gradient) {
      glyph = ShaderMask(
        shaderCallback: (bounds) => FluxPalette.ai.createShader(bounds),
        blendMode: BlendMode.srcIn,
        child: glyph,
      );
    }

    return Semantics(
      selected: active,
      button: true,
      label: item.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: active ? 1 : 0.94,
              duration: FluxMotion.duration(context, FluxMotion.quick),
              curve: FluxMotion.overshoot,
              child: glyph,
            ),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: FluxMotion.duration(context, FluxMotion.quick),
              style: FluxType.caption.copyWith(
                color: color,
                fontSize: 11,
                fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                fontVariations: [FontVariation('wght', active ? 620 : 500)],
              ),
              child: Text(item.label),
            ),
          ],
        ),
      ),
    );
  }
}
