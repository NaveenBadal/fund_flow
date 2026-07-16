import 'package:flutter/material.dart';

class CommandScaffold extends StatefulWidget {
  const CommandScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.eyebrow,
    this.actions = const [],
    this.floatingActionButton,
  });

  final String title;
  final String? eyebrow;
  final List<Widget> actions;
  final List<Widget> slivers;
  final Widget? floatingActionButton;

  @override
  State<CommandScaffold> createState() => _CommandScaffoldState();
}

class _CommandScaffoldState extends State<CommandScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _atmosphere = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();

  @override
  void dispose() {
    _atmosphere.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      floatingActionButton: widget.floatingActionButton,
      body: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: _atmosphere,
                builder: (_, _) => CustomPaint(
                  painter: _FlowAtmospherePainter(
                    phase: _atmosphere.value,
                    color: scheme.primary,
                    dark: Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
            ),
          ),
          CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 12, 30),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (Navigator.of(context).canPop()) ...[
                          IconButton(
                            onPressed: Navigator.of(context).pop,
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: scheme.primary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      (widget.eyebrow ?? 'FLOW SPACE')
                                          .toUpperCase(),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: scheme.primary,
                                            fontWeight: FontWeight.w800,
                                            letterSpacing: 1.6,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 11),
                              Text(
                                widget.title,
                                style: Theme.of(context).textTheme.headlineLarge
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: -1.4,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        ...widget.actions,
                      ],
                    ),
                  ),
                ),
              ),
              ...widget.slivers,
              SliverToBoxAdapter(
                child: SizedBox(
                  height: Navigator.of(context).canPop() ? 40 : 130,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FlowAtmospherePainter extends CustomPainter {
  const _FlowAtmospherePainter({
    required this.phase,
    required this.color,
    required this.dark,
  });
  final double phase;
  final Color color;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width * (.82 + phase * .03), size.height * .08);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: dark ? .11 : .08),
          color.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: size.width * .72));
    canvas.drawRect(Offset.zero & size, glow);
    final thread = Paint()
      ..color = color.withValues(alpha: dark ? .07 : .05)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final path = Path()..moveTo(-20, size.height * .36);
    path.cubicTo(
      size.width * .25,
      size.height * (.28 + phase * .03),
      size.width * .68,
      size.height * .46,
      size.width + 30,
      size.height * .30,
    );
    canvas.drawPath(path, thread);
  }

  @override
  bool shouldRepaint(covariant _FlowAtmospherePainter old) =>
      old.phase != phase;
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.title, {super.key, this.action, this.onAction});
  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 34, 20, 14),
    child: Row(
      children: [
        Expanded(
          child: Row(
            children: [
              Text(
                '◆',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 8,
                ),
              ),
              const SizedBox(width: 9),
              Flexible(
                child: Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.15,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.caption,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: .62),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(7),
          topRight: Radius.circular(28),
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(7),
        ),
        border: Border.all(color: scheme.primary.withValues(alpha: .16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 19, color: accent),
          const Spacer(),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          if (caption != null) ...[
            const SizedBox(height: 4),
            Text(
              caption!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class StatePanel extends StatelessWidget {
  const StatePanel({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(36),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 18),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          _friendlyMessage(message),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        if (action != null) ...[const SizedBox(height: 20), action!],
      ],
    ),
  );

  String _friendlyMessage(String raw) {
    final technical =
        raw.contains('Exception') ||
        raw.contains('DatabaseException') ||
        raw.contains('SocketException') ||
        raw.contains('StackTrace');
    return technical
        ? 'Something interrupted this view. Your data is safe; please try again.'
        : raw;
  }
}
