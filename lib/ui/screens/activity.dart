import 'package:flutter/material.dart';
import '../tokens/precision_tokens.dart';
import '../widgets/precision_components.dart';

class ActivityScreen extends StatelessWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Dummy data for the preview
    final transactions = [
      {'merchant': 'Apple Store', 'amount': '- \$99.00', 'date': 'Today, 2:45 PM', 'in': false},
      {'merchant': 'Whole Foods', 'amount': '- \$45.20', 'date': 'Today, 10:12 AM', 'in': false},
      {'merchant': 'Salary Deposit', 'amount': '+ \$3,200.00', 'date': 'Yesterday', 'in': true},
      {'merchant': 'Uber', 'amount': '- \$12.50', 'date': 'Yesterday', 'in': false},
      {'merchant': 'Netflix', 'amount': '- \$15.99', 'date': 'Aug 4', 'in': false},
      {'merchant': 'Coffee Shop', 'amount': '- \$4.50', 'date': 'Aug 4', 'in': false},
    ];

    return Scaffold(
      backgroundColor: isDark ? PrecisionTokens.backgroundDark : PrecisionTokens.backgroundLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(PrecisionTokens.space24),
              child: PrecisionHeader(title: 'Activity', subtitle: 'Ledger'),
            ),
            const PrecisionDivider(),
            Expanded(
              child: ListView.separated(
                itemCount: transactions.length,
                separatorBuilder: (context, index) => const PrecisionDivider(),
                itemBuilder: (context, index) {
                  final tx = transactions[index];
                  final isMoneyIn = tx['in'] as bool;
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: PrecisionTokens.space24, 
                      vertical: PrecisionTokens.space16,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx['merchant'] as String,
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: PrecisionTokens.space4),
                            Text(
                              tx['date'] as String,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                        Text(
                          tx['amount'] as String,
                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace', // Tabular figures
                            fontWeight: FontWeight.w600,
                            color: isMoneyIn 
                                ? PrecisionTokens.accentMoneyIn 
                                : (isDark ? PrecisionTokens.textPrimaryDark : PrecisionTokens.textPrimaryLight),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
