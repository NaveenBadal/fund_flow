import 'package:flutter/material.dart';
import '../tokens/precision_tokens.dart';
import '../widgets/precision_components.dart';

class AskScreen extends StatefulWidget {
  const AskScreen({super.key});

  @override
  State<AskScreen> createState() => _AskScreenState();
}

class _AskScreenState extends State<AskScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.1, end: 0.4).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? PrecisionTokens.backgroundDark : PrecisionTokens.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrecisionTokens.space24),
              child: PrecisionHeader(title: 'Ask', subtitle: 'Intelligence active.'),
            ),
            Expanded(
              child: Center(
                child: AnimatedBuilder(
                  animation: _glowAnimation,
                  builder: (context, child) {
                    return Container(
                      width: 1,
                      height: 120,
                      decoration: BoxDecoration(
                        color: PrecisionTokens.accentIntelligence.withOpacity(0.8),
                        boxShadow: [
                          BoxShadow(
                            color: PrecisionTokens.accentIntelligence.withOpacity(_glowAnimation.value),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(PrecisionTokens.space16),
              decoration: BoxDecoration(
                border: Border(
                  top: isDark ? PrecisionTokens.borderSideDark : PrecisionTokens.borderSideLight,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: theme.textTheme.bodyLarge,
                      decoration: InputDecoration(
                        hintText: 'Command or query...',
                        hintStyle: theme.textTheme.bodyLarge?.copyWith(
                          color: isDark ? PrecisionTokens.textTertiaryDark : PrecisionTokens.textTertiaryLight,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: PrecisionTokens.space8, vertical: PrecisionTokens.space12),
                      ),
                    ),
                  ),
                  const SizedBox(width: PrecisionTokens.space8),
                  Container(
                    decoration: BoxDecoration(
                      color: isDark ? PrecisionTokens.surfaceElevatedDark : PrecisionTokens.surfaceElevatedLight,
                      borderRadius: PrecisionTokens.borderRadius8,
                    ),
                    padding: const EdgeInsets.all(PrecisionTokens.space8),
                    child: Icon(
                      Icons.arrow_upward_rounded,
                      color: isDark ? PrecisionTokens.textPrimaryDark : PrecisionTokens.textPrimaryLight,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
