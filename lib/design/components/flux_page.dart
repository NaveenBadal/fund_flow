import 'package:flutter/material.dart'
    show FlexibleSpaceBar, Icons, RefreshIndicator, SliverAppBar;
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';
import 'flux_button.dart';
import 'flux_surface.dart';

/// The standard page: a large title that collapses into glass chrome as the
/// content scrolls under it.
///
/// The hairline under the header fades in only once something has actually
/// scrolled beneath it. A border that is always drawn reads as a fixed
/// division of the screen; one that appears on scroll explains that there is
/// more content above.
class FluxPage extends StatefulWidget {
  const FluxPage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.leading,
    this.headerBottom,
    this.headerBottomHeight = 0,
    this.floatingAction,
    this.bottomInset = 0,
    this.controller,
    this.onRefresh,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;
  final Widget? leading;

  /// Pinned under the title — a search field, a filter row.
  final Widget? headerBottom;
  final double headerBottomHeight;
  final Widget? floatingAction;

  /// Extra bottom padding so content clears the tab bar or a composer.
  final double bottomInset;
  final ScrollController? controller;
  final Future<void> Function()? onRefresh;

  @override
  State<FluxPage> createState() => _FluxPageState();
}

class _FluxPageState extends State<FluxPage> {
  late final ScrollController _controller =
      widget.controller ?? ScrollController();
  final _scrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    final under = _controller.hasClients && _controller.offset > 4;
    if (under != _scrolled.value) _scrolled.value = under;
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    if (widget.controller == null) _controller.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final top = MediaQuery.paddingOf(context).top;

    final scroll = CustomScrollView(
      controller: _controller,
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: const Color(0x00000000),
          surfaceTintColor: const Color(0x00000000),
          elevation: 0,
          scrolledUnderElevation: 0,
          automaticallyImplyLeading: false,
          leading: widget.leading,
          leadingWidth: widget.leading == null ? 0 : FluxSpace.tap + 12,
          toolbarHeight: 52,
          expandedHeight: 108 + widget.headerBottomHeight,
          collapsedHeight: 52 + widget.headerBottomHeight,
          actions: [
            ...widget.actions,
            const SizedBox(width: FluxSpace.x2),
          ],
          flexibleSpace: ValueListenableBuilder<bool>(
            valueListenable: _scrolled,
            builder: (context, scrolled, _) => AnimatedOpacity(
              duration: FluxMotion.duration(context, FluxMotion.quick),
              opacity: 1,
              child: FluxGlass(
                opacity: scrolled ? 0.78 : 0,
                blur: scrolled ? 24 : 0,
                border: Border(
                  bottom: BorderSide(
                    color: scrolled ? palette.line : const Color(0x00000000),
                    width: 1,
                  ),
                ),
                child: FlexibleSpaceBar(
                  expandedTitleScale: 1.5,
                  titlePadding: EdgeInsets.only(
                    left: FluxSpace.page,
                    right: FluxSpace.page,
                    bottom: 14 + widget.headerBottomHeight,
                  ),
                  title: Text(
                    widget.title,
                    style: FluxType.title.copyWith(color: palette.text),
                    maxLines: 1,
                  ),
                ),
              ),
            ),
          ),
          bottom: widget.headerBottom == null
              ? null
              : PreferredSize(
                  preferredSize: Size.fromHeight(widget.headerBottomHeight),
                  child: widget.headerBottom!,
                ),
        ),
        ...widget.slivers,
        SliverToBoxAdapter(
          child: SizedBox(
            height:
                widget.bottomInset +
                FluxSpace.x8 +
                MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );

    // The page paints its own background. A pushed route sits above the shell,
    // so without this it is transparent and shows the black window behind it —
    // which happens to look right in dark mode and leaves dark text on black in
    // light mode.
    return ColoredBox(
      color: palette.background,
      child: Stack(
        children: [
          Positioned.fill(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: Padding(
                padding: EdgeInsets.only(top: top),
                child: widget.onRefresh == null
                    ? scroll
                    : RefreshIndicator(
                        onRefresh: widget.onRefresh!,
                        color: palette.iris,
                        backgroundColor: palette.surface,
                        displacement: 24,
                        child: scroll,
                      ),
              ),
            ),
          ),
          if (widget.floatingAction != null)
            Positioned(
              right: FluxSpace.page,
              bottom: widget.bottomInset + FluxSpace.x4,
              child: widget.floatingAction!,
            ),
        ],
      ),
    );
  }
}

/// A pushed page: a back affordance and a small title, no large-title collapse.
///
/// Detail pages are entered from something specific and stay in context, so
/// they do not need the large title that establishes where you are.
class FluxDetailPage extends StatelessWidget {
  const FluxDetailPage({
    super.key,
    required this.title,
    required this.slivers,
    this.actions = const [],
    this.bottomBar,
    this.onRefresh,
  });

  final String title;
  final List<Widget> slivers;
  final List<Widget> actions;

  /// Pinned actions at the bottom, for pages whose whole purpose is one
  /// decision (approve, save, delete).
  final Widget? bottomBar;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return Stack(
      children: [
        Positioned.fill(
          child: FluxPage(
            title: title,
            actions: actions,
            onRefresh: onRefresh,
            leading: Padding(
              padding: const EdgeInsets.only(left: FluxSpace.x2),
              child: FluxIconButton(
                icon: Icons.arrow_back_rounded,
                tooltip: 'Back',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            bottomInset: bottomBar == null ? 0 : 88,
            slivers: slivers,
          ),
        ),
        if (bottomBar != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FluxGlass(
              border: Border(top: BorderSide(color: palette.line, width: 1)),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    FluxSpace.page,
                    FluxSpace.x3,
                    FluxSpace.page,
                    FluxSpace.x3,
                  ),
                  child: bottomBar!,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Standard page padding for a box-shaped sliver child.
class FluxSliverPadding extends StatelessWidget {
  const FluxSliverPadding({super.key, required this.child, this.top = 0});
  final Widget child;
  final double top;

  @override
  Widget build(BuildContext context) => SliverPadding(
    padding: EdgeInsets.only(
      left: FluxSpace.page,
      right: FluxSpace.page,
      top: top,
    ),
    sliver: SliverToBoxAdapter(child: child),
  );
}
