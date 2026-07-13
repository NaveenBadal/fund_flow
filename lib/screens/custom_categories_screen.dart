import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_category.dart';
import '../providers/expense_provider.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/command_ui.dart';

class CustomCategoriesScreen extends ConsumerWidget {
  const CustomCategoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customCategoryListProvider);
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New category'),
      ),
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Category library')),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 18),
              child: Text(
                'Built-in categories cover the essentials. Add only the distinctions that change how you understand your spending.',
              ),
            ),
          ),
          async.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => SliverFillRemaining(
              child: StatePanel(
                icon: Icons.category_outlined,
                title: 'Library unavailable',
                message: '$error',
              ),
            ),
            data: (items) => items.isEmpty
                ? const SliverFillRemaining(
                    hasScrollBody: false,
                    child: StatePanel(
                      icon: Icons.category_rounded,
                      title: 'No custom categories',
                      message:
                          'Your built-in category system is ready. Add one only when you need more detail.',
                    ),
                  )
                : SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
                    sliver: SliverGrid.builder(
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 1.35,
                          ),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        return _CategoryCell(
                          item: item,
                          onTap: () => _open(context, item),
                          onDelete: () => _delete(context, ref, item),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, [CustomCategory? category]) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _CategorySheet(category: category),
      );
  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    CustomCategory category,
  ) async {
    final yes =
        await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Delete ${category.name}?'),
            content: const Text('Existing movements keep their current label.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (yes && category.id != null) {
      await ref.read(customCategoryListProvider.notifier).remove(category.id!);
    }
  }
}

class _CategoryCell extends StatelessWidget {
  const _CategoryCell({
    required this.item,
    required this.onTap,
    required this.onDelete,
  });
  final CustomCategory item;
  final VoidCallback onTap, onDelete;
  @override
  Widget build(BuildContext context) => Material(
    color: item.color.withValues(alpha: .11),
    borderRadius: AppRadius.all(AppRadius.lg),
    child: InkWell(
      borderRadius: AppRadius.all(AppRadius.lg),
      onTap: onTap,
      onLongPress: onDelete,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: item.color,
                borderRadius: AppRadius.all(14),
              ),
              child: Icon(item.iconData, color: Colors.white, size: 20),
            ),
            const Spacer(),
            Text(
              item.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              'Hold to remove',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CategorySheet extends ConsumerStatefulWidget {
  const _CategorySheet({this.category});
  final CustomCategory? category;
  @override
  ConsumerState<_CategorySheet> createState() => _CategorySheetState();
}

class _CategorySheetState extends ConsumerState<_CategorySheet> {
  late final TextEditingController _name;
  late Color _color;
  late IconData _icon;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _color = widget.category?.color ?? CustomCategory.presetColors.first;
    _icon = widget.category?.iconData ?? CustomCategory.presetIcons.first;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 28,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: AppRadius.all(18),
                ),
                child: Icon(_icon, color: Colors.white),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Text(
                  widget.category == null ? 'Create category' : 'Edit category',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Category name'),
          ),
          const SizedBox(height: 20),
          Text(
            'COLOR',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final color in CustomCategory.presetColors)
                GestureDetector(
                  onTap: () => setState(() => _color = color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: color == _color
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3,
                            )
                          : null,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'SYMBOL',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final icon in CustomCategory.presetIcons)
                InkWell(
                  borderRadius: AppRadius.all(13),
                  onTap: () => setState(() => _icon = icon),
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: icon.codePoint == _icon.codePoint
                          ? _color.withValues(alpha: .18)
                          : Theme.of(
                              context,
                            ).colorScheme.surfaceContainerHighest,
                      borderRadius: AppRadius.all(13),
                    ),
                    child: Icon(
                      icon,
                      color: icon.codePoint == _icon.codePoint
                          ? _color
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _save,
              child: const Text('Save category'),
            ),
          ),
        ],
      ),
    ),
  );
  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    await ref
        .read(customCategoryListProvider.notifier)
        .upsert(
          CustomCategory(
            id: widget.category?.id,
            name: name,
            iconCodepoint: _icon.codePoint.toRadixString(16).toUpperCase(),
            colorValue: _color
                .toARGB32()
                .toRadixString(16)
                .padLeft(8, '0')
                .toUpperCase(),
          ),
        );
    if (mounted) Navigator.pop(context);
  }
}
