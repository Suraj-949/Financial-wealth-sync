/// WealthSync app configuration.
class Config {
  /// Base URL of the WealthSync ML API.
  ///
  /// Override at build time without editing code:
  ///   flutter run --dart-define=API_BASE=http://192.168.1.10:8000
  ///
  /// Defaults:
  ///   - Android emulator: 10.0.2.2 maps to the host machine
  ///   - iOS simulator: localhost works
  ///   - Physical device: use your computer's LAN IP.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE',
    defaultValue: 'http://10.0.2.2:8000',
  );
}