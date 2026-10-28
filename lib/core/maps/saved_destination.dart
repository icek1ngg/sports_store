/// A destination snapshot saved on a delivery task.
///
/// This model deliberately has no dependency on a map SDK or a delivery
/// feature.  It represents the server-owned snapshot that a map provider may
/// render.  A map screen must never manufacture a coordinate from an address.
final class SavedDestination {
  const SavedDestination({
    required this.latitude,
    required this.longitude,
    required this.address,
    required this.label,
    this.phone,
  });

  final double latitude;
  final double longitude;
  final String address;
  final String label;
  final String? phone;

  /// Valid for geographic coordinates, including the poles.
  bool get hasValidCoordinates =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  /// Valid for the Web Mercator projection used by OSM raster tiles.
  ///
  /// The domain model may still carry a polar coordinate, but the map must
  /// show its address fallback rather than pretending a tile exists there.
  bool get isRenderableOnWebMercator =>
      hasValidCoordinates &&
      latitude >= -85.05112878 &&
      latitude <= 85.05112878;

  bool get hasDisplayContent =>
      label.trim().isNotEmpty && address.trim().isNotEmpty;

  @override
  bool operator ==(Object other) {
    return other is SavedDestination &&
        latitude == other.latitude &&
        longitude == other.longitude &&
        address == other.address &&
        label == other.label &&
        phone == other.phone;
  }

  @override
  int get hashCode => Object.hash(latitude, longitude, address, label, phone);
}
