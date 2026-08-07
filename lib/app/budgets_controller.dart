import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/budget.dart';
import 'app_controller.dart';

/// Budgets, kept in their own controller rather than folded into [AppState].
///
/// The app controller is already the one place that owns importing, the agent
/// loop, preferences and the ledger, and every feature added to it makes the
/// working parts harder to change safely. A new capability that needs no import
/// or agent state gets its own notifier over the same store.
class BudgetsController extends AsyncNotifier<List<CategoryBudget>> {
  @override
  Future<List<CategoryBudget>> build() => ref.read(storeProvider).budgets();

  Future<void> setLimit({
    required String category,
    required int limitMinor,
    required String currency,
  }) async {
    // A zero or negative limit is a removal, not a budget of nothing: a ring
    // measuring spend against zero is over budget the moment it is created.
    if (limitMinor <= 0) return remove(category);
    await ref
        .read(storeProvider)
        .saveBudget(
          CategoryBudget(
            category: category,
            limitMinor: limitMinor,
            currency: currency,
            createdAt: DateTime.now(),
          ),
        );
    state = AsyncData(await ref.read(storeProvider).budgets());
  }

  Future<void> remove(String category) async {
    await ref.read(storeProvider).deleteBudget(category);
    state = AsyncData(await ref.read(storeProvider).budgets());
  }
}

final budgetsProvider =
    AsyncNotifierProvider<BudgetsController, List<CategoryBudget>>(
      BudgetsController.new,
    );
