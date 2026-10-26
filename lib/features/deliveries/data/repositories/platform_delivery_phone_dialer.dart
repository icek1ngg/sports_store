import 'package:url_launcher/url_launcher.dart';

import '../../domain/repositories/delivery_phone_dialer.dart';

final class PlatformDeliveryPhoneDialer implements DeliveryPhoneDialer {
  const PlatformDeliveryPhoneDialer();

  @override
  Future<DialerOpenOutcome> openDialer(Uri telephoneUri) async {
    if (telephoneUri.scheme != 'tel' ||
        telephoneUri.hasAuthority ||
        telephoneUri.hasQuery ||
        telephoneUri.hasFragment ||
        !RegExp(r'^\+?[0-9]{8,15}$').hasMatch(telephoneUri.path)) {
      return DialerOpenOutcome.failed;
    }
    try {
      return await launchUrl(telephoneUri, mode: LaunchMode.externalApplication)
          ? DialerOpenOutcome.opened
          : DialerOpenOutcome.unavailable;
    } catch (_) {
      return DialerOpenOutcome.failed;
    }
  }
}
