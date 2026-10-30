import 'dart:io' show Platform;

/// WealthSync app configuration.
class Config {
  static const String _override = String.fromEnvironment('API_BASE');

  /// Base URL of the WealthSync API.
  ///
  /// Override at build time without editing code:
  ///   flutter run --dart-define=API_BASE=http://192.168.1.10:8000
  ///
  /// Defaults:
  ///   - Android emulator: 10.0.2.2 maps to the host machine
  ///   - iOS simulator / desktop: localhost works
  ///   - Physical device: use your computer's LAN IP.
  static String get apiBaseUrl {
    if (_override.isNotEmpty) return _override;
    if (Platform.isAndroid) return 'http://10.0.2.2:8000';
    return 'http://127.0.0.1:8000';
  }
}
