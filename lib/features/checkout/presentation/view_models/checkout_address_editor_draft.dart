/// In-memory editor state retained by the checkout page during session rechecks.
/// It is separate from the confirmed order payload and is never persisted.
class CheckoutAddressEditorDraft {
  const CheckoutAddressEditorDraft({
    required this.query,
    required this.detail,
    required this.selectedLabel,
    required this.latitude,
    required this.longitude,
    required this.confirmed,
    required this.adjusted,
  });

  final String query;
  final String detail;
  final String? selectedLabel;
  final double? latitude;
  final double? longitude;
  final bool confirmed;
  final bool adjusted;
}
