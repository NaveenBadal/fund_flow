import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/ff_theme.dart';
import 'ff_pressable.dart';

/// A page.
///
/// The title starts large, inside the content, and scrolls away with it. Once
/// it has gone the bar picks the title up small and centred, and a hairline
/// appears to separate the now-blurred bar from what is passing beneath it.
///
/// This is the single most recognisable piece of the language being copied,
/// and it is behaviour rather than decoration: the heading is part of the
/// document until the document needs the room.
class FFScreen extends StatefulWidget {
  const FFScreen({
    super.key,
    required this.title,
    this.slivers = const [],
    this.child,
    this.large = true,
    this.leading,
    this.trailing = const [],
    this.backLabel,
    this.grouped = true,
    this.subtitle,
    this.belowTitle,
    this.bottom,
    this.controller,
    this.padBottom = true,
    this.extraBottom = 0,
  });

  final String title;

  /// Scrolling content. Ignored when [child] is given.
  final List<Widget> slivers;

  /// Non-scrolling content, laid out below the bar.
  final Widget? child;

  /// Whether the title begins large in the content.
  final bool large;

  final Widget? leading;
  final List<Widget> trailing;
  final String? backLabel;

  /// Grouped pages sit on the grouped background; plain ones on the base.
  final bool grouped;

  /// A quiet line under the large title.
  final String? subtitle;

  /// Pinned directly beneath the large title — a search field, say.
  final Widget? belowTitle;

  /// Pinned above the bottom edge, over the content.
  final Widget? bottom;

  final ScrollController? controller;
  final bool padBottom;

  /// Extra room at the end of the scroll, for anything pinned over it.
  final double extraBottom;

  @override
  State<FFScreen> createState() => _FFScreenState();
}

class _FFScreenState extends State<FFScreen> {
  final _collapsed = ValueNotifier(0.0);

  @override
  void dispose() {
    _collapsed.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification note) {
    if (note.depth != 0 || note.metrics.axis != Axis.vertical) return false;
    // Fully collapsed once the large title has cleared the bar. Fading over a
    // short distance rather than snapping keeps the swap from reading as a
    // glitch when someone scrolls slowly.
    final value = (note.metrics.pixels / 38).clamp(0.0, 1.0);
    if ((value - _collapsed.value).abs() > .01 ||
        value == 0 ||
        value == 1 && _collapsed.value != 1) {
      _collapsed.value = value;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final top = MediaQuery.paddingOf(context).top;
    final barHeight = top + _kBarHeight;

    Widget content;
    if (widget.child != null) {
      content = Padding(
        padding: EdgeInsets.only(top: barHeight),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.large) _largeTitle(context),
            if (widget.belowTitle != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFSpace.gutter,
                  0,
                  FFSpace.gutter,
                  FFSpace.sm,
                ),
                child: widget.belowTitle!,
              ),
            Expanded(child: widget.child!),
          ],
        ),
      );
    } else {
      content = CustomScrollView(
        controller: widget.controller,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        slivers: [
          SliverToBoxAdapter(
            // Without a large title there is nothing between the bar and the
            // first card, and content pressed against a hairline reads as
            // clipped rather than as the top of the page.
            child: SizedBox(
              height: barHeight + (widget.large ? 0 : FFSpace.lg),
            ),
          ),
          if (widget.large) SliverToBoxAdapter(child: _largeTitle(context)),
          if (widget.belowTitle != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  FFSpace.gutter,
                  0,
                  FFSpace.gutter,
                  FFSpace.md,
                ),
                child: widget.belowTitle!,
              ),
            ),
          ...widget.slivers,
          if (widget.padBottom)
            SliverToBoxAdapter(
              child: SizedBox(
                height:
                    FFSpace.xxl +
                    widget.extraBottom +
                    MediaQuery.paddingOf(context).bottom,
              ),
            ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: widget.grouped ? c.groupedBackground : c.background,
      body: Stack(
        children: [
          Positioned.fill(
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: content,
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ValueListenableBuilder<double>(
              valueListenable: _collapsed,
              builder: (context, value, _) => FFNavBar(
                title: widget.title,
                collapsed: widget.large ? value : 1,
                showTitle: widget.large ? value > .5 : true,
                leading: widget.leading,
                trailing: widget.trailing,
                backLabel: widget.backLabel,
              ),
            ),
          ),
          if (widget.bottom != null)
            Positioned(left: 0, right: 0, bottom: 0, child: widget.bottom!),
        ],
      ),
    );
  }

  Widget _largeTitle(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      FFSpace.gutter,
      FFSpace.xs,
      FFSpace.gutter,
      widget.subtitle == null ? FFSpace.md : FFSpace.sm,
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: FFText.largeTitle),
        if (widget.subtitle != null) ...[
          const SizedBox(height: FFSpace.xs),
          Text(
            widget.subtitle!,
            style: FFText.subhead.copyWith(color: context.ff.secondaryLabel),
          ),
        ],
      ],
    ),
  );
}

const double _kBarHeight = 44;

/// The bar itself: translucent, hairline-edged, and empty until it is needed.
class FFNavBar extends StatelessWidget {
  const FFNavBar({
    super.key,
    required this.title,
    this.collapsed = 1,
    this.showTitle = true,
    this.leading,
    this.trailing = const [],
    this.backLabel,
    this.transparent = false,
  });

  final String title;

  /// 0 — sitting over unscrolled content. 1 — content is passing beneath.
  final double collapsed;
  final bool showTitle;
  final Widget? leading;
  final List<Widget> trailing;
  final String? backLabel;
  final bool transparent;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    final top = MediaQuery.paddingOf(context).top;
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final wash = transparent ? 0.0 : collapsed;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22 * wash, sigmaY: 22 * wash),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.chrome.withValues(alpha: c.chrome.a * wash),
            border: Border(
              bottom: BorderSide(
                color: c.opaqueSeparator.withValues(alpha: wash),
                width: 1 / MediaQuery.devicePixelRatioOf(context),
              ),
            ),
          ),
          child: SizedBox(
            height: top + _kBarHeight,
            child: Padding(
              padding: EdgeInsets.only(top: top),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedOpacity(
                          duration: Duration(
                            milliseconds: context.ffStill ? 0 : 140,
                          ),
                          opacity: showTitle ? 1 : 0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 76),
                            child: Text(
                              title,
                              maxLines: 1,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: FFText.headline,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child:
                        leading ??
                        (canPop
                            ? FFBackButton(label: backLabel)
                            : const SizedBox(width: FFSpace.gutter)),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: FFSpace.sm),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: trailing,
                      ),
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

class FFBackButton extends StatelessWidget {
  const FFBackButton({super.key, this.label, this.onTap});

  final String? label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => FFPressable(
    onTap: onTap ?? () => Navigator.maybePop(context),
    semanticLabel: 'Back',
    child: SizedBox(
      height: _kBarHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: FFSpace.sm, right: FFSpace.md),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: context.ff.tint),
            if (label != null) ...[
              const SizedBox(width: 5),
              Text(
                label!,
                style: FFText.body.copyWith(color: context.ff.tint),
              ),
            ],
          ],
        ),
      ),
    ),
  );
}

/// A tappable glyph in a nav bar. Tinted, because it is an action.
class FFBarButton extends StatelessWidget {
  const FFBarButton({
    super.key,
    this.icon,
    this.label,
    required this.onTap,
    this.tooltip,
    this.emphasis = false,
  }) : assert(icon != null || label != null);

  final IconData? icon;
  final String? label;
  final VoidCallback? onTap;
  final String? tooltip;

  /// Semibold, for the one action a page is really about.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final tint = onTap == null ? context.ff.quaternaryLabel : context.ff.tint;
    return FFPressable(
      onTap: onTap,
      semanticLabel: tooltip ?? label,
      child: SizedBox(
        height: _kBarHeight,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: label == null ? 10 : 8),
          child: Center(
            child: label != null
                ? Text(
                    label!,
                    style: FFText.body.copyWith(
                      color: tint,
                      fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
                    ),
                  )
                : Icon(icon, size: 23, color: tint),
          ),
        ),
      ),
    );
  }
}
