import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/ff_theme.dart';
import 'ff_pressable.dart';

/// A sheet: a page that arrives from below and is dismissed rather than
/// navigated away from. Used for anything you fill in and finish.
Future<T?> showFFSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .35),
  builder: (sheetContext) => ClipRRect(
    borderRadius: const BorderRadius.vertical(
      top: Radius.circular(FFRadius.sheet),
    ),
    child: ColoredBox(
      color: sheetContext.ff.elevated,
      child: builder(sheetContext),
    ),
  ),
);

/// The header a sheet wears: cancel on the left, the commitment on the right,
/// and the subject in the middle. Nothing about what it does is hidden.
class FFSheetScaffold extends StatelessWidget {
  const FFSheetScaffold({
    super.key,
    required this.title,
    required this.child,
    this.leading,
    this.trailing,
    this.onCancel,
    this.scrollable = true,
    this.maxHeightFraction = .92,
  });

  final String title;
  final Widget child;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onCancel;
  final bool scrollable;
  final double maxHeightFraction;

  @override
  Widget build(BuildContext context) {
    final c = context.ff;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFraction,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 6),
            Container(
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: c.tertiaryLabel,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            SizedBox(
              height: 46,
              child: Stack(
                children: [
                  Center(child: Text(title, style: FFText.headline)),
                  Align(
                    alignment: Alignment.centerLeft,
                    child:
                        leading ??
                        FFSheetAction(
                          label: 'Cancel',
                          onTap:
                              onCancel ?? () => Navigator.of(context).pop(),
                        ),
                  ),
                  if (trailing != null)
                    Align(alignment: Alignment.centerRight, child: trailing!),
                ],
              ),
            ),
            const FFSeparator(),
            Flexible(
              child: scrollable
                  ? SingleChildScrollView(
                      padding: EdgeInsets.only(
                        bottom:
                            FFSpace.xxl + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: child,
                    )
                  : child,
            ),
          ],
        ),
      ),
    );
  }
}

class FFSheetAction extends StatelessWidget {
  const FFSheetAction({
    super.key,
    required this.label,
    required this.onTap,
    this.emphasis = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => FFPressable(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FFSpace.gutter,
        vertical: FFSpace.md,
      ),
      child: Text(
        label,
        style: FFText.body.copyWith(
          color: onTap == null ? context.ff.quaternaryLabel : context.ff.tint,
          fontWeight: emphasis ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    ),
  );
}

/// One choice in an alert or action sheet.
class FFAction {
  const FFAction(
    this.label, {
    this.destructive = false,
    this.preferred = false,
    this.value,
  });

  final String label;
  final bool destructive;

  /// Rendered semibold — the answer the sheet expects.
  final bool preferred;
  final Object? value;
}

/// A short, centred question with two or three answers.
///
/// Deliberately not a page: an alert interrupts, so it must be readable in one
/// glance and answerable without scrolling.
Future<int?> showFFAlert(
  BuildContext context, {
  required String title,
  String? message,
  required List<FFAction> actions,
}) {
  HapticFeedback.mediumImpact();
  return showDialog<int>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: .28),
    builder: (dialog) {
      final c = dialog.ff;
      return Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(FFRadius.alert),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              width: 274,
              color: c.elevated.withValues(alpha: .92),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      FFSpace.lg,
                      FFSpace.xl,
                      FFSpace.lg,
                      FFSpace.lg,
                    ),
                    child: Column(
                      children: [
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: FFText.headline,
                        ),
                        if (message != null) ...[
                          const SizedBox(height: 5),
                          Text(
                            message,
                            textAlign: TextAlign.center,
                            style: FFText.footnote.copyWith(color: c.label),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const FFSeparator(),
                  for (var i = 0; i < actions.length; i++) ...[
                    if (i != 0) const FFSeparator(),
                    FFPressable(
                      highlight: true,
                      onTap: () => Navigator.of(dialog).pop(i),
                      child: SizedBox(
                        height: 44,
                        width: double.infinity,
                        child: Center(
                          child: Text(
                            actions[i].label,
                            style: FFText.body.copyWith(
                              color: actions[i].destructive ? c.red : c.tint,
                              fontWeight: actions[i].preferred
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Ask before doing something that cannot be taken back.
Future<bool> ffConfirm(
  BuildContext context, {
  required String title,
  required String message,
  required String confirm,
  String cancel = 'Cancel',
  bool destructive = true,
}) async {
  final choice = await showFFAlert(
    context,
    title: title,
    message: message,
    actions: [
      FFAction(cancel, preferred: true),
      FFAction(confirm, destructive: destructive),
    ],
  );
  return choice == 1;
}

/// A list of alternatives, anchored to the bottom edge where a thumb is.
Future<int?> showFFActionSheet(
  BuildContext context, {
  String? title,
  String? message,
  required List<FFAction> actions,
  String cancel = 'Cancel',
}) => showModalBottomSheet<int>(
  context: context,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black.withValues(alpha: .28),
  isScrollControlled: true,
  builder: (sheet) {
    final c = sheet.ff;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(FFSpace.sm, 0, FFSpace.sm, FFSpace.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(FFRadius.alert),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: ColoredBox(
                color: c.elevated.withValues(alpha: .92),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (title != null || message != null) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FFSpace.lg,
                          vertical: FFSpace.lg,
                        ),
                        child: Column(
                          children: [
                            if (title != null)
                              Text(
                                title,
                                textAlign: TextAlign.center,
                                style: FFText.footnote.copyWith(
                                  color: c.secondaryLabel,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            if (message != null) ...[
                              if (title != null) const SizedBox(height: 4),
                              Text(
                                message,
                                textAlign: TextAlign.center,
                                style: FFText.footnote.copyWith(
                                  color: c.secondaryLabel,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const FFSeparator(),
                    ],
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i != 0) const FFSeparator(),
                      FFPressable(
                        highlight: true,
                        onTap: () => Navigator.of(sheet).pop(i),
                        child: SizedBox(
                          height: 56,
                          width: double.infinity,
                          child: Center(
                            child: Text(
                              actions[i].label,
                              style: FFText.title3.copyWith(
                                fontWeight: actions[i].preferred
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: actions[i].destructive ? c.red : c.tint,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: FFSpace.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(FFRadius.alert),
            child: FFPressable(
              highlight: true,
              onTap: () => Navigator.of(sheet).pop(),
              child: Container(
                height: 56,
                width: double.infinity,
                color: c.elevated,
                child: Center(
                  child: Text(
                    cancel,
                    style: FFText.title3.copyWith(
                      fontWeight: FontWeight.w600,
                      color: c.tint,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  },
);

/// Pick one of a list. A sheet rather than an inline expansion, because the
/// list is usually longer than the row that opened it.
Future<T?> showFFPicker<T>(
  BuildContext context, {
  required String title,
  required T current,
  required List<(T, String)> options,
  String? footer,
}) => showFFSheet<T>(
  context,
  builder: (sheet) => FFSheetScaffold(
    title: title,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i != 0) const FFSeparator(indent: FFSpace.lg),
          FFPressable(
            highlight: true,
            onTap: () => Navigator.of(sheet).pop(options[i].$1),
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(horizontal: FFSpace.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(options[i].$2, style: FFText.body),
                  ),
                  if (options[i].$1 == current)
                    Icon(
                      Icons.check_rounded,
                      size: 20,
                      color: sheet.ff.tint,
                    ),
                ],
              ),
            ),
          ),
        ],
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              FFSpace.lg,
              FFSpace.lg,
              FFSpace.lg,
              0,
            ),
            child: Text(
              footer,
              style: FFText.footnote.copyWith(color: sheet.ff.secondaryLabel),
            ),
          ),
      ],
    ),
  ),
);
