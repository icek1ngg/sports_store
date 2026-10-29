import 'package:flutter/widgets.dart';

import 'map_location.dart';
import 'map_tile_source.dart';
import 'saved_destination.dart';
import 'saved_destination_map.dart';

/// Read-only preview seam shared with MH16; no picker or persistence logic.
abstract interface class MapDisplayAdapter {
  Widget buildMap({
    Key? key,
    required MapLocation location,
    int recenterToken = 0,
    double height = 320,
    ValueChanged<Object>? onTileError,
  });
}

final class RasterMapDisplayAdapter implements MapDisplayAdapter {
  const RasterMapDisplayAdapter({required this.tileSource});
  final MapTileSource tileSource;
  @override
  Widget buildMap({
    Key? key,
    required MapLocation location,
    int recenterToken = 0,
    double height = 320,
    ValueChanged<Object>? onTileError,
  }) {
    return SavedDestinationMap(
      key: key,
      destination: SavedDestination(
        latitude: location.latitude,
        longitude: location.longitude,
        address: '',
        label: '',
      ),
      tileSource: tileSource,
      recenterToken: recenterToken,
      height: height,
      onTileError: onTileError,
    );
  }
}
