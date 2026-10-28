import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'map_directions.dart';
import 'map_tile_source.dart';

final mapDirectionsLauncherProvider = Provider<MapDirectionsLauncher>(
  (ref) => const GoogleMapsDirectionsLauncher(),
);

final mapTileSourceProvider = Provider.autoDispose<MapTileSource>((ref) {
  final source = OpenStreetMapTileSource();
  ref.onDispose(source.dispose);
  return source;
});
