import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../services/finance_repository.dart';
import '../budget/budget_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../goals/goals_screen.dart';
import '../more/more_screen.dart';
import '../transactions/transactions_screen.dart';

/// Root shell: bottom navigation over the five main destinations.
///
/// The pages are rebuilt when demo mode flips or a write succeeds, so every tab
/// reloads from the same data source instead of keeping stale demo rows.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: demoModeListenable,
      builder: (context, _) {
        final mode = demoModeEnabled ? 'demo' : 'live';
        final key = mode;
        final pages = <Widget>[
          DashboardScreen(key: ValueKey('dashboard-$key')),
          TransactionsTab(key: ValueKey('transactions-$key')),
          BudgetTab(key: ValueKey('budget-$key')),
          GoalsTab(key: ValueKey('goals-$key')),
          MoreScreen(key: ValueKey('more-$key')),
        ];

        return Scaffold(
          extendBody: true,
          body: IndexedStack(index: _index, children: pages),
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: const BoxDecoration(color: AppColors.surface),
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home, color: AppColors.accent),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(
                      Icons.receipt_long,
                      color: AppColors.accent,
                    ),
                    label: 'Transactions',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.pie_chart_outline),
                    selectedIcon: Icon(
                      Icons.pie_chart,
                      color: AppColors.accent,
                    ),
                    label: 'Budget',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.flag_outlined),
                    selectedIcon: Icon(Icons.flag, color: AppColors.accent),
                    label: 'Goals',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.menu),
                    selectedIcon: Icon(Icons.menu, color: AppColors.accent),
                    label: 'More',
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
