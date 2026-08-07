import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';

/// A money figure.
///
/// Takes an already-formatted string rather than minor units and a currency
/// code: grouping and symbol placement are domain rules (Indian grouping is
/// 2-2-3, not 3-3-3), and `lib/design` deliberately knows nothing about the
/// app's domain so the system stays portable.
///
/// [incoming] only chooses the colour. Outgoing money is ink-coloured, never
/// red — see [FluxPalette].
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.text, {
    super.key,
    this.incoming = false,
    this.style,
    this.signed = false,
    this.muted = false,
    this.color,
  });

  final String text;
  final bool incoming;
  final TextStyle? style;

  /// Prefixes `+` or `−` (a true minus, not a hyphen — a hyphen sits too high
  /// and too short next to tabular digits).
  final bool signed;
  final bool muted;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final resolved =
        color ??
        (muted
            ? palette.textMuted
            : (incoming ? palette.income : palette.outflow));
    final prefix = signed ? (incoming ? '+' : '−') : '';
    return Text(
      '$prefix$text',
      style: (style ?? FluxType.moneyRow).copyWith(color: resolved),
      maxLines: 1,
    );
  }
}

/// A money figure whose digits roll when the value changes.
///
/// Only used for the one hero figure on Home. The roll is what makes a refresh
/// feel like the number moved rather than like the screen was replaced, and
/// tabular figures are what keep it from jittering sideways while it moves.
class MoneyOdometer extends StatelessWidget {
  const MoneyOdometer(
    this.text, {
    super.key,
    this.style,
    this.color,
    this.prefix = '',
  });

  final String text;
  final TextStyle? style;
  final Color? color;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final resolved = (style ?? FluxType.moneyHero).copyWith(
      color: color ?? palette.text,
    );
    final characters = '$prefix$text'.split('');
    if (FluxMotion.reduced(context)) {
      return Text('$prefix$text', style: resolved, maxLines: 1);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (var index = 0; index < characters.length; index++)
          _Digit(
            character: characters[index],
            style: resolved,
            // Staggering by position makes the roll read left-to-right like a
            // mechanical counter instead of every digit flipping at once.
            delay: Duration(milliseconds: 40 * index),
          ),
      ],
    );
  }
}

class _Digit extends StatefulWidget {
  const _Digit({
    required this.character,
    required this.style,
    required this.delay,
  });

  final String character;
  final TextStyle style;
  final Duration delay;

  @override
  State<_Digit> createState() => _DigitState();
}

class _DigitState extends State<_Digit> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    value: 1,
  );
  late String _shown = widget.character;
  String? _previous;

  @override
  void didUpdateWidget(_Digit oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character == widget.character) return;
    _previous = _shown;
    _shown = widget.character;
    _controller.value = 0;
    Future<void>.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Text(_shown, style: widget.style, maxLines: 1);
    if (_previous == null) return text;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeOutCubic.transform(_controller.value);
        return ClipRect(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Opacity(
                opacity: 1 - t,
                child: Transform.translate(
                  offset: Offset(0, -t * widget.style.fontSize! * 0.7),
                  child: Text(_previous!, style: widget.style, maxLines: 1),
                ),
              ),
              Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, (1 - t) * widget.style.fontSize! * 0.7),
                  child: text,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
