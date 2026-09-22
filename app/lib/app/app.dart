import 'package:flutter/material.dart';

import '../screens/shell/app_shell.dart';
import 'theme.dart';

/// Root application widget. Kept thin on purpose — everything the app renders
/// lives one level under `lib/screens/`.
class WealthSyncApp extends StatelessWidget {
  const WealthSyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WealthSync',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AppShell(),
    );
  }
}