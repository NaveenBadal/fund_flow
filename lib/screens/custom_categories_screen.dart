import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/custom_category.dart';
import '../providers/expense_provider.dart';
import '../flow_os/foundation/flow_color.dart';
import '../flow_os/primitives/coordinate_label.dart';
import '../flow_os/primitives/cut_surface.dart';
import '../flow_os/primitives/loom_mark.dart';
import '../theme/app_tokens.dart';
import '../widgets/ui/flow_ui.dart';

class CustomCategoriesScreen extends ConsumerWidget {
  const CustomCategoriesScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(customCategoryListProvider);
    final width = MediaQuery.sizeOf(context).width;
    final inset = width > AppBreakpoint.contentMax + 40
        ? (width - AppBreakpoint.contentMax) / 2
        : AppSpacing.page;
    final singleColumn =
        width < 420 || MediaQuery.textScalerOf(context).scale(1) > 1.3;
    return FlowScaffold(
      eyebrow: 'Personalize how transactions are grouped',
      title: 'Categories',
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(inset, 0, inset, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Built-in categories cover the essentials. Add only distinctions that improve what Flow can explain.',
                ),
                const SizedBox(height: 18),
                _CategoryCommand(onTap: () => _open(context)),
              ],
            ),
          ),
        ),
        async.when(
          loading: () => const SliverFillRemaining(
            child: Center(child: Icon(Icons.hourglass_top_rounded, size: 32)),
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
                  padding: EdgeInsets.fromLTRB(inset, 0, inset, 100),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: singleColumn ? 1 : 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: singleColumn ? 2.25 : 1.35,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _CategoryCell(
                        index: index,
                        item: item,
                        horizontal: singleColumn,
                        onTap: () => _open(context, item),
                        onDelete: () => _delete(context, ref, item),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  void _open(BuildContext context, [CustomCategory? category]) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        showDragHandle: false,
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
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            child: CutSurface(
              accent: FlowColor.coral,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CoordinateLabel(
                    'Classification / destructive',
                    color: FlowColor.coral,
                    line: true,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Remove ${category.name}?',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Existing movements keep their current label.',
                    style: TextStyle(color: FlowColor.quiet(context)),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _CategoryPort(
                          label: 'KEEP',
                          color: FlowColor.proof,
                          onTap: () => Navigator.pop(context, false),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _CategoryPort(
                          label: 'REMOVE',
                          color: FlowColor.coral,
                          onTap: () => Navigator.pop(context, true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
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
    required this.index,
    required this.item,
    required this.horizontal,
    required this.onTap,
    required this.onDelete,
  });
  final int index;
  final CustomCategory item;
  final bool horizontal;
  final VoidCallback onTap, onDelete;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    onLongPress: onDelete,
    child: CutSurface(
      color: item.color.withValues(alpha: .09),
      accent: item.color,
      padding: const EdgeInsets.all(18),
      child: horizontal
          ? Row(
              children: [
                _CategoryIcon(item: item),
                const SizedBox(width: AppSpacing.lg),
                Expanded(child: _CategoryLabel(item: item)),
                IconButton(
                  tooltip: 'Delete ${item.name}',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _CategoryIcon(item: item),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Delete ${item.name}',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                const Spacer(),
                _CategoryLabel(item: item),
              ],
            ),
    ),
  );
}

class _CategoryIcon extends StatelessWidget {
  const _CategoryIcon({required this.item});
  final CustomCategory item;

  @override
  Widget build(BuildContext context) => Container(
    width: 42,
    height: 42,
    color: item.color,
    child: Icon(item.iconData, color: Colors.white, size: 20),
  );
}

class _CategoryLabel extends StatelessWidget {
  const _CategoryLabel({required this.item});
  final CustomCategory item;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        item.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      Text(
        'AI CLASSIFICATION · CUSTOM',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: FlowColor.quiet(context),
          letterSpacing: .6,
        ),
      ),
    ],
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
  Widget build(BuildContext context) => ColoredBox(
    color: FlowColor.canvas(context),
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        22,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 28,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CoordinateLabel('AI / classification node', line: true),
            const SizedBox(height: 16),
            Row(
              children: [
                Container(
                  width: 54,
                  height: 54,
                  color: _color,
                  child: Icon(_icon, color: Colors.white),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Text(
                    widget.category == null
                        ? 'Create category'
                        : 'Edit category',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            CutSurface(
              accent: _color,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CoordinateLabel('Node name'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _name,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration.collapsed(
                      hintText: 'Category name',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const CoordinateLabel('Signal color', line: true),
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
                      color: color,
                      child: color == _color
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 18,
                            )
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const CoordinateLabel('Recognition symbol', line: true),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final icon in CustomCategory.presetIcons)
                  InkWell(
                    onTap: () => setState(() => _icon = icon),
                    child: Container(
                      width: 44,
                      height: 44,
                      color: icon.codePoint == _icon.codePoint
                          ? _color.withValues(alpha: .18)
                          : FlowColor.raised(context),
                      child: Icon(
                        icon,
                        color: icon.codePoint == _icon.codePoint
                            ? _color
                            : FlowColor.quiet(context),
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 24),
            _CategoryPort(
              label: 'COMMIT CLASSIFICATION',
              color: FlowColor.proof,
              onTap: _save,
            ),
          ],
        ),
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

class _CategoryCommand extends StatelessWidget {
  const _CategoryCommand({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: CutSurface(
      color: FlowColor.loom.withValues(alpha: .14),
      accent: FlowColor.proof,
      child: Row(
        children: [
          const LoomMark(size: 32),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TEACH FLOW A CLASS',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    letterSpacing: .7,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Add only when AI needs a new distinction',
                  style: TextStyle(
                    color: FlowColor.quiet(context),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const Icon(Icons.add, color: FlowColor.proof),
        ],
      ),
    ),
  );
}

class _CategoryPort extends StatelessWidget {
  const _CategoryPort({
    required this.label,
    required this.color,
    required this.onTap,
  });
  final String label;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      child: CutSurface(
        accent: color,
        color: color.withValues(alpha: .12),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
              fontSize: 11,
              letterSpacing: .7,
            ),
          ),
        ),
      ),
    ),
  );
}
