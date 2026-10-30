import 'package:flutter/material.dart';

import 'app/app.dart';
import 'services/finance_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadDemoModePreference();
  await loadUserIdentity();
  runApp(const WealthSyncApp());
}
