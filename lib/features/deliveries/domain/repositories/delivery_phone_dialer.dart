/// Dialer contract used by MH11.
/// An implementation must open the phone composer, never place an automatic call.
enum DialerOpenOutcome { opened, unavailable, failed }

abstract interface class DeliveryPhoneDialer {
  /// Only a validated `tel:` URI with a plain phone number may be passed.
  Future<DialerOpenOutcome> openDialer(Uri telephoneUri);
}
