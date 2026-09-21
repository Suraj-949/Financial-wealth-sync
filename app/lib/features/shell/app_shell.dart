import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../budget/budget_screen.dart';
import '../dashboard/dashboard_screen.dart';
import '../goals/goals_screen.dart';
import '../more/more_screen.dart';
import '../transactions/transactions_screen.dart';

/// Root shell: bottom navigation over the five main destinations.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _pages = [
    DashboardScreen(),
    TransactionsTab(),
    BudgetTab(),
    GoalsTab(),
    MoreScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: IndexedStack(index: _index, children: _pages),
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
                selectedIcon: Icon(Icons.receipt_long, color: AppColors.accent),
                label: 'Transactions',
              ),
              NavigationDestination(
                icon: Icon(Icons.pie_chart_outline),
                selectedIcon: Icon(Icons.pie_chart, color: AppColors.accent),
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
  }
}