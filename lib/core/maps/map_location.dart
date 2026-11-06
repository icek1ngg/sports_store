/// Coordinate only, not proof of authorization or Hanoi service eligibility.
final class MapLocation {
  const MapLocation({required this.latitude, required this.longitude});
  final double latitude, longitude;
  bool get isValid =>
      latitude.isFinite &&
      longitude.isFinite &&
      latitude.abs() <= 90 &&
      longitude.abs() <= 180;
  bool get canDisplay => isValid && latitude.abs() <= 85.05112878;
  @override
  bool operator ==(Object other) =>
      other is MapLocation &&
      latitude == other.latitude &&
      longitude == other.longitude;
  @override
  int get hashCode => Object.hash(latitude, longitude);
}
