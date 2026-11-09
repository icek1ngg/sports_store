/// A real place returned by an address provider, before server service-area
/// validation. Coordinates do not imply that delivery is available here.
class AddressSuggestion {
  const AddressSuggestion({
    required this.id,
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  final String id;
  final String label;
  final double latitude;
  final double longitude;
}
