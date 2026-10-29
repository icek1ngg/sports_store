/// Provider choice explicitly approved by the user for Web/Android demo.
/// Contains public identification only; no server credentials or API keys.
final class MapProviderConfiguration {
  const MapProviderConfiguration({
    this.userAgent = const String.fromEnvironment(
      'MAP_USER_AGENT',
      defaultValue:
          'sports_store/0.1 (+https://github.com/icek1ngg/sports_store)',
    ),
  });
  final String userAgent;
  String get tileHost => 'tile.openstreetmap.org';
  bool get isValid =>
      userAgent.trim().startsWith('sports_store/') &&
      !userAgent.contains('\r') &&
      !userAgent.contains('\n');
}
