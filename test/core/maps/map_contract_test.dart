import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/maps/map_directions.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/core/maps/saved_destination.dart';

void main() {
  const destination = SavedDestination(
    latitude: 21.028511,
    longitude: 105.804817,
    label: 'Người nhận',
    address: 'Hà Nội',
    phone: '0900000000',
  );

  test(
    'saved destination preserves server coordinates and validates map range',
    () {
      expect(destination.hasValidCoordinates, isTrue);
      expect(destination.isRenderableOnWebMercator, isTrue);
      expect(
        const SavedDestination(
          latitude: 90,
          longitude: 105,
          label: 'Người nhận',
          address: 'Địa chỉ',
        ).hasValidCoordinates,
        isTrue,
      );
      expect(
        const SavedDestination(
          latitude: 90,
          longitude: 105,
          label: 'Người nhận',
          address: 'Địa chỉ',
        ).isRenderableOnWebMercator,
        isFalse,
      );
    },
  );

  test(
    'OSM tile source creates the documented HTTPS URL and wraps longitude',
    () async {
      final source = OpenStreetMapTileSource();
      addTearDown(source.dispose);

      final uri = source.tileUri(zoom: 3, x: -1, y: 2);
      expect(uri.scheme, 'https');
      expect(uri.host, 'tile.openstreetmap.org');
      expect(uri.path, '/3/7/2.png');
      expect(source.attribution, contains('OpenStreetMap'));
    },
  );

  test(
    'directions URL contains only coordinates and the required api flag',
    () async {
      Uri? openedUri;
      final launcher = GoogleMapsDirectionsLauncher(
        launchUrlOverride: (uri) async {
          openedUri = uri;
          return true;
        },
      );

      final outcome = await launcher.openDirections(destination);

      expect(outcome, MapDirectionsOutcome.opened);
      expect(openedUri?.scheme, 'https');
      expect(openedUri?.host, 'www.google.com');
      expect(openedUri?.path, '/maps/dir/');
      expect(openedUri?.queryParameters['api'], '1');
      expect(openedUri?.queryParameters['destination'], '21.028511,105.804817');
      expect(openedUri.toString(), isNot(contains('Hà Nội')));
    },
  );

  test(
    'directions launcher returns unavailable and invalid outcomes honestly',
    () async {
      final unavailable = GoogleMapsDirectionsLauncher(
        launchUrlOverride: (_) async => false,
      );
      expect(
        await unavailable.openDirections(destination),
        MapDirectionsOutcome.unavailable,
      );
      expect(
        await unavailable.openDirections(
          const SavedDestination(
            latitude: 21,
            longitude: 105,
            label: '',
            address: 'Địa chỉ',
          ),
        ),
        MapDirectionsOutcome.invalidDestination,
      );
    },
  );
}
