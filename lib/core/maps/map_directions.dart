import 'package:url_launcher/url_launcher.dart';

import 'saved_destination.dart';
import 'map_location.dart';

/// Result of handing a destination to an external directions application.
enum MapDirectionsOutcome { opened, unavailable, failed, invalidDestination }

abstract interface class MapDirectionsLauncher {
  Future<MapDirectionsOutcome> openDirections(SavedDestination destination);
}

/// Coordinate-only handoff for consumers such as MH16's future picker.
/// Does not authorize delivery data or validate Hanoi eligibility.
abstract interface class MapNavigationAdapter {
  Future<MapDirectionsOutcome> openLocation(MapLocation location);
}

/// Opens a provider-owned directions URL instead of embedding a route engine.
///
/// Google Maps documents this URL format as a cross-platform Maps URL.  It
/// does not require a Maps API key because the app is only launching the
/// external web/app experience, not calling a Google Maps API.
final class GoogleMapsDirectionsLauncher
    implements MapDirectionsLauncher, MapNavigationAdapter {
  const GoogleMapsDirectionsLauncher({this.launchUrlOverride});

  /// Injectable for deterministic tests and platform adapters.
  final Future<bool> Function(Uri uri)? launchUrlOverride;

  Uri directionsUri(SavedDestination destination) {
    return locationUri(destination.location);
  }

  Uri locationUri(MapLocation location) {
    return Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'destination': '${location.latitude},${location.longitude}',
    });
  }

  @override
  Future<MapDirectionsOutcome> openDirections(
    SavedDestination destination,
  ) async {
    if (!destination.isRenderableOnWebMercator ||
        !destination.hasDisplayContent) {
      return MapDirectionsOutcome.invalidDestination;
    }

    return openLocation(destination.location);
  }

  @override
  Future<MapDirectionsOutcome> openLocation(MapLocation location) async {
    if (!location.isValid) return MapDirectionsOutcome.invalidDestination;
    final uri = locationUri(location);
    try {
      final opened = launchUrlOverride == null
          ? await launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
              webOnlyWindowName: '_self',
            )
          : await launchUrlOverride!(uri);
      return opened
          ? MapDirectionsOutcome.opened
          : MapDirectionsOutcome.unavailable;
    } catch (_) {
      return MapDirectionsOutcome.failed;
    }
  }
}
