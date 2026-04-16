import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/custom_category.dart';
import '../providers/expense_provider.dart';

class CustomCategoriesScreen extends ConsumerWidget {
  const CustomCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(customCategoryListProvider);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Custom Categories')),
      body: categoriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (categories) {
          if (categories.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(Icons.category_rounded, size: 40, color: scheme.primary),
                    ),
                    const SizedBox(height: 20),
                    Text('No custom categories',
                        style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('Tap + to add one',
                        style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final cat = categories[i];
              return _CategoryTile(
                category: cat,
                onEdit: () => _showEditDialog(context, ref, cat),
                onDelete: () => _confirmDelete(context, ref, cat),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEditDialog(context, ref, null),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Category'),
      ),
    );
  }

  Future<void> _showEditDialog(BuildContext context, WidgetRef ref, CustomCategory? existing) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CategoryEditSheet(existing: existing),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CustomCategory cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete category?'),
        content: Text('Remove "${cat.name}"? Existing expenses will keep this category label.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true && cat.id != null) {
      await ref.read(customCategoryListProvider.notifier).remove(cat.id!);
    }
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.onEdit, required this.onDelete});

  final CustomCategory category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = category.color;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(category.iconData, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  category.name,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.delete_outline, color: scheme.error),
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryEditSheet extends ConsumerStatefulWidget {
  const _CategoryEditSheet({this.existing});

  final CustomCategory? existing;

  @override
  ConsumerState<_CategoryEditSheet> createState() => _CategoryEditSheetState();
}

class _CategoryEditSheetState extends ConsumerState<_CategoryEditSheet> {
  late TextEditingController _nameCtrl;
  late Color _selectedColor;
  late IconData _selectedIcon;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _selectedColor = widget.existing?.color ?? CustomCategory.presetColors.first;
    _selectedIcon = widget.existing?.iconData ?? CustomCategory.presetIcons.first;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final colorHex = _selectedColor.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();
    final iconHex = _selectedIcon.codePoint.toRadixString(16).toUpperCase();

    final cat = CustomCategory(
      id: widget.existing?.id,
      name: name,
      iconCodepoint: iconHex,
      colorValue: colorHex,
    );

    await ref.read(customCategoryListProvider.notifier).upsert(cat);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isEditing ? 'Edit Category' : 'New Category',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Category name',
              prefixIcon: Icon(Icons.label_outline_rounded),
              filled: true,
            ),
          ),
          const SizedBox(height: 20),
          Text('Color', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: CustomCategory.presetColors.map((c) {
              final selected = _selectedColor.r == c.r && _selectedColor.g == c.g && _selectedColor.b == c.b && _selectedColor.a == c.a;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = c),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(10),
                    border: selected ? Border.all(color: scheme.onSurface, width: 3) : null,
                    boxShadow: selected
                        ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 8, spreadRadius: 1)]
                        : null,
                  ),
                  child: selected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Icon', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: CustomCategory.presetIcons.map((icon) {
              final selected = _selectedIcon.codePoint == icon.codePoint;
              return GestureDetector(
                onTap: () => setState(() => _selectedIcon = icon),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: selected
                        ? _selectedColor.withValues(alpha: 0.2)
                        : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                    border: selected ? Border.all(color: _selectedColor, width: 2) : null,
                  ),
                  child: Icon(icon, color: selected ? _selectedColor : scheme.onSurfaceVariant, size: 22),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: const Icon(Icons.save_outlined),
              label: Text(isEditing ? 'Update' : 'Create'),
              onPressed: _save,
            ),
          ),
        ],
      ),
    );
  }
}
