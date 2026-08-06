import 'package:flutter/material.dart';
import '../tokens/precision_tokens.dart';
import 'ask.dart';
import 'activity.dart';
import 'you.dart';

class PrecisionShell extends StatefulWidget {
  const PrecisionShell({super.key});

  @override
  State<PrecisionShell> createState() => _PrecisionShellState();
}

class _PrecisionShellState extends State<PrecisionShell> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const AskScreen(),
    const ActivityScreen(),
    const YouScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: isDark ? PrecisionTokens.backgroundDark : PrecisionTokens.backgroundLight,
          border: Border(
            top: isDark ? PrecisionTokens.borderSideDark : PrecisionTokens.borderSideLight,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: PrecisionTokens.space16, vertical: PrecisionTokens.space8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _NavItem(
                  icon: Icons.chat_bubble_outline_rounded,
                  label: 'Ask',
                  isSelected: _currentIndex == 0,
                  onTap: () => setState(() => _currentIndex = 0),
                ),
                _NavItem(
                  icon: Icons.list_alt_rounded,
                  label: 'Activity',
                  isSelected: _currentIndex == 1,
                  onTap: () => setState(() => _currentIndex = 1),
                ),
                _NavItem(
                  icon: Icons.person_outline_rounded,
                  label: 'You',
                  isSelected: _currentIndex == 2,
                  onTap: () => setState(() => _currentIndex = 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final color = isSelected
        ? (isDark ? PrecisionTokens.textPrimaryDark : PrecisionTokens.textPrimaryLight)
        : (isDark ? PrecisionTokens.textSecondaryDark : PrecisionTokens.textSecondaryLight);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: PrecisionTokens.space4),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
