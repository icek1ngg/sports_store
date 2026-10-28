import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/maps/map_directions.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/core/maps/saved_destination.dart';
import 'package:sports_store/core/maps/map_provider_configuration.dart';
import 'package:sports_store/core/maps/map_location.dart';

void main() {
  test(
    'MH16 navigation seam needs coordinates only, no recipient data',
    () async {
      Uri? uri;
      final MapNavigationAdapter adapter = GoogleMapsDirectionsLauncher(
        launchUrlOverride: (value) async {
          uri = value;
          return true;
        },
      );
      expect(
        await adapter.openLocation(
          const MapLocation(latitude: 21, longitude: 105),
        ),
        MapDirectionsOutcome.opened,
      );
      expect(uri?.queryParameters, {'api': '1', 'destination': '21.0,105.0'});
      expect(
        await adapter.openLocation(
          const MapLocation(latitude: double.infinity, longitude: 105),
        ),
        MapDirectionsOutcome.invalidDestination,
      );
    },
  );
  test('approved configuration contains public identification and no key', () {
    const config = MapProviderConfiguration();
    expect(config.tileHost, 'tile.openstreetmap.org');
    expect(config.isValid, isTrue);
    expect(
      const MapProviderConfiguration(userAgent: 'bad\r\nheader').isValid,
      isFalse,
    );
    final source = OpenStreetMapTileSource();
    expect(
      source.attributionUri,
      Uri.parse('https://www.openstreetmap.org/copyright'),
    );
    source.dispose();
  });
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
      expect(openedUri?.queryParameters.keys.toSet(), {'api', 'destination'});
      expect(openedUri.toString(), isNot(contains(destination.phone!)));
      expect(openedUri.toString(), isNot(contains('Hà Nội')));
    },
  );

  test('external launcher exceptions return failed, never opened', () async {
    final launcher = GoogleMapsDirectionsLauncher(
      launchUrlOverride: (_) async =>
          throw StateError('Test platform unavailable'),
    );
    expect(
      await launcher.openDirections(destination),
      MapDirectionsOutcome.failed,
    );
  });

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
