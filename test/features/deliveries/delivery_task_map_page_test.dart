import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/maps/map_tile_source.dart';
import 'package:sports_store/features/deliveries/data/models/delivery_task_dto.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_providers.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_details.dart';
import 'package:sports_store/features/deliveries/domain/models/delivery_task_query.dart';
import 'package:sports_store/features/deliveries/domain/repositories/delivery_repository.dart';
import 'package:sports_store/features/deliveries/data/repositories/operational_read_access.dart';
import 'package:sports_store/features/deliveries/presentation/pages/delivery_task_map_page.dart';
import 'package:sports_store/features/deliveries/presentation/view_models/delivery_providers.dart';
import 'package:sports_store/core/maps/map_providers.dart';

import 'fixtures/delivery_dtos.dart';

/// Fake tile source used to prove MH18 retains the authorized address when the
/// external tile provider is unavailable. It is not production map data.
final class _FailingTileSource implements MapTileSource {
  @override
  String get attribution => '© OpenStreetMap contributors';

  @override
  Future<void> dispose() async {}

  @override
  Future<Uint8List> loadTile(Uri uri) =>
      Future<Uint8List>.error(StateError('fake tile outage'));

  @override
  Uri tileUri({required int zoom, required int x, required int y}) =>
      Uri.parse('https://tiles.invalid/$zoom/$x/$y.png');
}

final class _FakeRepository implements DeliveryRepository {
  @override
  Future<DeliveryTaskDetails> getTaskDetails(String taskId) async {
    return DeliveryTaskDetails(
      task: DeliveryTaskDto.fromJson(currentTaskDto(task: taskId)).toDomain(),
      items: const [],
    );
  }

  @override
  Future<DeliveryTaskSnapshot> getTask(String taskId) =>
      Future.error(UnimplementedError());

  @override
  Future<List<DeliveryTaskSnapshot>> listTasks() =>
      Future.error(UnimplementedError());

  @override
  Future<DeliveryTaskPage> queryTasks(DeliveryTaskQuery query) =>
      Future.error(UnimplementedError());
}

void main() {
  testWidgets(
    'renders authorized destination and keeps address on tile outage',
    (tester) async {
      final sessions = StreamController<OperationalSession>.broadcast();
      addTearDown(sessions.close);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            deliveryRepositoryProvider.overrideWithValue(_FakeRepository()),
            mapTileSourceProvider.overrideWithValue(_FailingTileSource()),
            operationalSessionProvider.overrideWith((ref) => sessions.stream),
          ],
          child: const MaterialApp(home: DeliveryTaskMapPage(taskId: taskId)),
        ),
      );
      sessions.add(
        const OperationalSession(userId: 'shipper-a', generation: 1),
      );
      await tester.pump();
      for (var index = 0; index < 10; index++) {
        await tester.pump(const Duration(milliseconds: 20));
      }

      expect(find.byKey(const ValueKey('mh18-address')), findsOneWidget);
      expect(find.text('Hà Nội'), findsWidgets);
      expect(find.byKey(const ValueKey('mh18-directions')), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off_outlined), findsWidgets);
    },
  );
}
