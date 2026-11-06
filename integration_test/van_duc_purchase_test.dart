import 'package:integration_test/integration_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/features/checkout/data/repositories/pending_placement_store.dart';
import 'package:sports_store/features/checkout/domain/models/placement_request.dart';
import 'package:uuid/uuid.dart';

import '../test/scenarios/van_duc_purchase_scenario.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  runVanDucPurchaseScenario();
  testWidgets('Android lưu và khôi phục yêu cầu bằng kho mã hóa thật', (
    tester,
  ) async {
    final userId = const Uuid().v4();
    final request = PlacementRequest(
      requestId: const Uuid().v4(),
      items: [PlacementItem(variantId: const Uuid().v4(), quantity: 1)],
      recipientName: '[TEST] Yêu cầu cục bộ',
      recipientPhone: '0900000000',
      addressDetail: '[TEST] Hà Nội',
      latitude: 21.0285,
      longitude: 105.8542,
    );
    final store = SecurePendingPlacementStore();
    try {
      await store.write(userId, request);
      final restored = await SecurePendingPlacementStore().read(userId);
      expect(restored?.request.fingerprint, request.fingerprint);
      expect(await store.read(const Uuid().v4()), isNull);
    } finally {
      await store.clear(userId);
    }
  });
}
