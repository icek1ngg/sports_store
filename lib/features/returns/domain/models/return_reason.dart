/// Return reasons accepted by `public.return_reason` (see
/// `docs/business_states.md`). Wire values must stay identical to the enum.
enum ReturnReason {
  defective('defective'),
  wrongItem('wrong_item'),
  missingItems('missing_items');

  const ReturnReason(this.wireValue);

  final String wireValue;

  static ReturnReason fromWire(String value) {
    for (final reason in values) {
      if (reason.wireValue == value) return reason;
    }
    throw ArgumentError.value(value, 'value', 'Unknown return reason');
  }
}
