import 'package:flutter/material.dart'
    show Icons, showModalBottomSheet, showDialog;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/flux_theme.dart';
import 'flux_button.dart';
import 'flux_surface.dart';

/// A sheet: one thing to fill in and finish.
///
/// Sheets are never used for navigation or for settings hierarchies — a stack
/// of sheets loses the sense of where you are, and the app used to do exactly
/// that. If it has children, it is a page.
Future<T?> showFluxSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool dismissible = true,
}) {
  HapticFeedback.lightImpact();
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    isDismissible: dismissible,
    enableDrag: dismissible,
    useSafeArea: true,
    backgroundColor: const Color(0x00000000),
    builder: (context) => Padding(
      // The sheet rides above the keyboard rather than being covered by it.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: _SheetSurface(child: builder(context)),
    ),
  );
}

class _SheetSurface extends StatelessWidget {
  const _SheetSurface({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: palette.surfaceRaised,
        shape: FluxRadius.sheetShape,
        shadows: FluxElevation.floating(palette),
      ),
      child: ClipPath(
        clipper: const ShapeBorderClipper(
          shape: RoundedSuperellipseBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(FluxRadius.sheet),
            ),
          ),
        ),
        child: child,
      ),
    );
  }
}

/// The inside of a sheet: grabber, title row, scrolling body, pinned actions.
class FluxSheetBody extends StatelessWidget {
  const FluxSheetBody({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions,
    this.trailing,
    this.scrollable = true,
  });

  final String title;
  final String? subtitle;
  final Widget child;

  /// Pinned at the bottom. A sheet exists to finish something, so its primary
  /// action never scrolls out of reach.
  final Widget? actions;
  final Widget? trailing;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final palette = context.flux;
    final body = Padding(
      padding: const EdgeInsets.fromLTRB(
        FluxSpace.x5,
        0,
        FluxSpace.x5,
        FluxSpace.x5,
      ),
      child: child,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: FluxSpace.x3),
        Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: ShapeDecoration(
              color: palette.lineStrong,
              shape: const StadiumBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            FluxSpace.x5,
            FluxSpace.x4,
            FluxSpace.x3,
            FluxSpace.x4,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: FluxType.title.copyWith(color: palette.text),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: FluxType.caption.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
        if (scrollable)
          Flexible(
            child: SingleChildScrollView(padding: EdgeInsets.zero, child: body),
          )
        else
          body,
        if (actions != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FluxSpace.x5,
              0,
              FluxSpace.x5,
              FluxSpace.x5,
            ),
            child: actions!,
          ),
        SizedBox(height: MediaQuery.paddingOf(context).bottom),
      ],
    );
  }
}

/// A confirmation for something that cannot be undone.
///
/// Returns true only on an explicit press of the destructive action; a barrier
/// tap or a back gesture always resolves to false, never to "yes".
Future<bool> fluxConfirm({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Delete',
  bool destructive = true,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: context.flux.scrim,
    builder: (context) {
      final palette = context.flux;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FluxSpace.x8),
          child: FluxCard(
            raised: true,
            radius: FluxRadius.lg,
            padding: const EdgeInsets.all(FluxSpace.x6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: FluxType.subtitle.copyWith(color: palette.text),
                ),
                const SizedBox(height: FluxSpace.x2),
                Text(
                  message,
                  style: FluxType.body.copyWith(color: palette.textMuted),
                ),
                const SizedBox(height: FluxSpace.x6),
                FluxButton(
                  label: confirmLabel,
                  kind: destructive
                      ? FluxButtonKind.danger
                      : FluxButtonKind.primary,
                  onPressed: () {
                    HapticFeedback.heavyImpact();
                    Navigator.of(context).pop(true);
                  },
                ),
                const SizedBox(height: FluxSpace.x2),
                FluxButton(
                  label: 'Cancel',
                  kind: FluxButtonKind.ghost,
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

/// A single-choice picker sheet.
Future<T?> showFluxPicker<T>({
  required BuildContext context,
  required String title,
  required List<(T, String)> options,
  T? selected,
}) => showFluxSheet<T>(
  context: context,
  builder: (context) {
    final palette = context.flux;
    return FluxSheetBody(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final option in options)
            FluxPressableRow(
              onTap: () => Navigator.of(context).pop(option.$1),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: FluxSpace.x3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.$2,
                        style: FluxType.body.copyWith(color: palette.text),
                      ),
                    ),
                    if (option.$1 == selected)
                      Icon(Icons.check_rounded, size: 18, color: palette.iris),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  },
);

/// A full-bleed tappable row for use inside sheets.
class FluxPressableRow extends StatelessWidget {
  const FluxPressableRow({super.key, required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            onTap!();
          },
    child: child,
  );
}
