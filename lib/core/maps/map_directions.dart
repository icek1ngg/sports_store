import 'package:url_launcher/url_launcher.dart';

import 'saved_destination.dart';

/// Result of handing a destination to an external directions application.
enum MapDirectionsOutcome { opened, unavailable, failed, invalidDestination }

abstract interface class MapDirectionsLauncher {
  Future<MapDirectionsOutcome> openDirections(SavedDestination destination);
}

/// Opens a provider-owned directions URL instead of embedding a route engine.
///
/// Google Maps documents this URL format as a cross-platform Maps URL.  It
/// does not require a Maps API key because the app is only launching the
/// external web/app experience, not calling a Google Maps API.
final class GoogleMapsDirectionsLauncher implements MapDirectionsLauncher {
  const GoogleMapsDirectionsLauncher({this.launchUrlOverride});

  /// Injectable for deterministic tests and platform adapters.
  final Future<bool> Function(Uri uri)? launchUrlOverride;

  Uri directionsUri(SavedDestination destination) {
    return Uri.https('www.google.com', '/maps/dir/', <String, String>{
      'api': '1',
      'destination': '${destination.latitude},${destination.longitude}',
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

    final uri = directionsUri(destination);
    try {
      final opened = launchUrlOverride == null
          ? await launchUrl(uri, mode: LaunchMode.externalApplication)
          : await launchUrlOverride!(uri);
      return opened
          ? MapDirectionsOutcome.opened
          : MapDirectionsOutcome.unavailable;
    } catch (_) {
      return MapDirectionsOutcome.failed;
    }
  }
}
