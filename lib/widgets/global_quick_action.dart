import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/expense_provider.dart';
import '../screens/action_inbox_screen.dart';
import '../screens/settings_screen.dart';
import 'expense_form_sheet.dart';

class GlobalQuickActionButton extends ConsumerWidget {
  const GlobalQuickActionButton({super.key, this.small = false});

  final bool small;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncing = ref.watch(syncProvider).isActive;
    final button = small
        ? FloatingActionButton.small(
            heroTag: 'global-quick-action-small',
            tooltip: 'Quick action',
            onPressed: syncing ? null : () => _show(context, ref),
            child: syncing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
          )
        : FloatingActionButton(
            heroTag: 'global-quick-action',
            tooltip: 'Quick action',
            onPressed: syncing ? null : () => _show(context, ref),
            child: syncing
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
          );
    return button;
  }

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF090D16),
          borderRadius: BorderRadius.vertical(top: Radius.circular(36)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.add_circle_outline_rounded,
                      color: Color(0xFFC7FF4A),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'CAUSE A CHANGE',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ListTile(
                  textColor: Colors.white,
                  iconColor: const Color(0xFFC7FF4A),
                  leading: const Icon(Icons.gesture_rounded),
                  title: const Text('Teach Flow a movement'),
                  subtitle: const Text(
                    'Create a memory manually',
                    style: TextStyle(color: Colors.white38),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _add(context, ref);
                  },
                ),
                ListTile(
                  textColor: Colors.white,
                  iconColor: const Color(0xFF65EAD1),
                  leading: const Icon(Icons.bolt_rounded),
                  title: const Text('Sense bank signals now'),
                  subtitle: const Text(
                    'Understand new movements',
                    style: TextStyle(color: Colors.white38),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ref.read(syncProvider.notifier).sync();
                  },
                ),
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.white70,
                  leading: const Icon(Icons.inbox_outlined),
                  title: const Text('Review interventions'),
                  subtitle: const Text(
                    'Decisions that change outcomes',
                    style: TextStyle(color: Colors.white38),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const ActionInboxScreen(),
                      ),
                    );
                  },
                ),
                ListTile(
                  textColor: Colors.white,
                  iconColor: Colors.white70,
                  leading: const Icon(Icons.tune_rounded),
                  title: const Text('Alter Flow DNA'),
                  subtitle: const Text(
                    'Privacy, memory, and intelligence',
                    style: TextStyle(color: Colors.white38),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => ExpenseFormSheet(
        onSave: (value) async {
          await ref.read(expenseListProvider.notifier).addExpense(value);
          if (sheetContext.mounted) Navigator.pop(sheetContext);
        },
      ),
    );
  }
}

extension on SyncState {
  bool get isActive =>
      phase == SyncPhase.requestingPermissions ||
      phase == SyncPhase.fetchingSms ||
      phase == SyncPhase.analyzing;
}
