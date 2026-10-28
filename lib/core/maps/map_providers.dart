import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_directions.dart';
import 'map_tile_source.dart';
import 'map_display_adapter.dart';
import 'map_provider_configuration.dart';

final mapProviderConfigurationProvider = Provider<MapProviderConfiguration>(
  (ref) => const MapProviderConfiguration(),
);

final mapDisplayAdapterProvider = Provider.autoDispose<MapDisplayAdapter>(
  (ref) =>
      RasterMapDisplayAdapter(tileSource: ref.watch(mapTileSourceProvider)),
);

final mapDirectionsLauncherProvider = Provider<MapDirectionsLauncher>(
  (ref) => const GoogleMapsDirectionsLauncher(),
);

final mapNavigationAdapterProvider = Provider<MapNavigationAdapter>(
  (ref) => const GoogleMapsDirectionsLauncher(),
);

final mapTileSourceProvider = Provider.autoDispose<MapTileSource>((ref) {
  final config = ref.watch(mapProviderConfigurationProvider);
  if (!config.isValid) {
    throw ArgumentError('Invalid map provider identification');
  }
  final source = OpenStreetMapTileSource(
    tileHost: config.tileHost,
    userAgent: config.userAgent,
  );
  ref.onDispose(source.dispose);
  return source;
});
