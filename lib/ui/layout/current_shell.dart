import 'package:flutter/material.dart';

import '../components/current_mark.dart';
import '../foundation/current_colors.dart';

enum RootDestination { ask, activity, you }

class CurrentShell extends StatelessWidget {
  const CurrentShell({
    super.key,
    required this.destination,
    required this.onDestinationChanged,
    required this.child,
  });
  final RootDestination destination;
  final ValueChanged<RootDestination> onDestinationChanged;
  final Widget child;

  static const _items = [
    (RootDestination.ask, Icons.chat_bubble_outline_rounded, 'Ask'),
    (RootDestination.activity, Icons.receipt_long_outlined, 'Activity'),
    (RootDestination.you, Icons.person_outline_rounded, 'You'),
  ];

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final scale = MediaQuery.textScalerOf(context).scale(1);
      if (box.maxWidth >= 760) {
        return Scaffold(
          body: Row(
            children: [
              Container(
                width: 88,
                decoration: BoxDecoration(
                  color: context.current.surface,
                  border: Border(
                    right: BorderSide(color: context.current.rule),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 26),
                        child: CurrentMark(size: 32),
                      ),
                      for (final item in _items)
                        _SideItem(
                          item: item,
                          selected: destination == item.$1,
                          onTap: () => onDestinationChanged(item.$1),
                        ),
                    ],
                  ),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        );
      }
      return Scaffold(
        body: child,
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: context.current.surface,
            border: Border(top: BorderSide(color: context.current.rule)),
          ),
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.fromLTRB(12, 4, 12, 7),
            child: SizedBox(
              height: 68 + ((scale - 1).clamp(0, 1) * 32),
              child: Row(
                children: [
                  for (final item in _items)
                    Expanded(
                      child: _BottomItem(
                        item: item,
                        selected: destination == item.$1,
                        onTap: () => onDestinationChanged(item.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _BottomItem extends StatelessWidget {
  const _BottomItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final (RootDestination, IconData, String) item;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.$3,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            height: 2,
            width: selected ? 34 : 12,
            decoration: BoxDecoration(
              color: selected
                  ? context.current.intelligence
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 7),
          Icon(
            item.$2,
            size: 21,
            color: selected
                ? context.current.intelligence
                : context.current.muted,
          ),
          const SizedBox(height: 3),
          Text(
            item.$3,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: selected ? context.current.ink : context.current.muted,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    ),
  );
}

class _SideItem extends StatelessWidget {
  const _SideItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });
  final (RootDestination, IconData, String) item;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: item.$3,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 72,
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 2,
              height: selected ? 36 : 12,
              color: selected
                  ? context.current.intelligence
                  : Colors.transparent,
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.$2,
                    size: 22,
                    color: selected
                        ? context.current.intelligence
                        : context.current.muted,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    item.$3,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: selected
                          ? context.current.ink
                          : context.current.muted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
