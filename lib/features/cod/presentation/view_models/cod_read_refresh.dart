import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'cod_providers.dart';
import 'shipper_cod_view_model.dart';

/// Call only after a real write ACK + authoritative result. Missing write APIs
/// must not use this hook to simulate collection or reconciliation.
void refreshCodReadsAfterConfirmedWrite(Ref ref) {
  invalidateLegacyCodReads(ref);
  ref.invalidate(shipperCodViewModelProvider);
}
