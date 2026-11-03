import '../../domain/models/delivery_task.dart';
import '../../domain/models/delivery_task_details.dart';
import 'delivery_task_dto.dart';
import 'delivery_task_item_dto.dart';
import 'dto_readers.dart';

/// DTO for the authorized single-snapshot delivery detail response.
///
/// The RPC deliberately returns one approved task projection and its approved
/// item projections. The history RPC opts into readable terminal snapshots;
/// the legacy/map RPC keeps the masked history contract. This mapper rejects
/// shape changes at the data boundary so a detail read cannot accidentally
/// start accepting order, return, catalog, bank, video, or storage data.
class DeliveryTaskDetailsDto {
  DeliveryTaskDetailsDto({
    required this.task,
    required List<DeliveryTaskItemDto> items,
    required this.notes,
    required this.notesSource,
    required this.asOf,
    this.cod,
    this.canRetry = false,
  }) : items = List.unmodifiable(items);

  factory DeliveryTaskDetailsDto.fromJson(
    Map<String, dynamic> json, {
    required String requestedTaskId,
    bool allowMissingDestinationCoordinates = false,
    bool allowReadableHistory = false,
  }) {
    DeliveryDtoReaders.checkUuid(requestedTaskId, 'task_id');
    _checkKeys(json, _responseKeys, 'detail response');

    final rawTask = json['task'];
    if (rawTask is! Map) {
      throw DeliveryDtoReaders.invalid('task', 'an object');
    }
    final taskJson = _asStringMap(rawTask, 'task');
    _checkKeys(taskJson, _taskKeys, 'task');
    final task = DeliveryTaskDto.fromJson(
      taskJson,
      allowMissingDestinationCoordinates: allowMissingDestinationCoordinates,
      allowReadableHistory: allowReadableHistory,
    );
    if (task.taskId.toLowerCase() != requestedTaskId.toLowerCase()) {
      throw DeliveryDtoReaders.invalid('task_id', 'the requested task UUID');
    }

    final rawItems = json['items'];
    if (rawItems is! List) {
      throw DeliveryDtoReaders.invalid('items', 'an array');
    }
    final items = <DeliveryTaskItemDto>[];
    final itemIds = <String>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        throw DeliveryDtoReaders.invalid('items', 'an array of objects');
      }
      final itemJson = _asStringMap(rawItem, 'item');
      _checkKeys(itemJson, _itemKeys, 'item');
      final item = DeliveryTaskItemDto.fromJson(
        itemJson,
        allowReturnMetadata:
            task.kind == DeliveryTaskKind.redelivery &&
            (task.scope == DeliverySnapshotScope.current ||
                task.scope == DeliverySnapshotScope.history) &&
            task.itemSource == DeliveryItemSource.returnPlan,
        allowRedeliveryPlan:
            task.kind == DeliveryTaskKind.redelivery &&
            task.itemSource == DeliveryItemSource.returnPlan,
      );
      if (item.itemSource != task.itemSource ||
          !itemIds.add(item.itemId.toLowerCase())) {
        throw DeliveryDtoReaders.invalid(
          'items',
          'unique rows matching the task item source',
        );
      }
      items.add(item);
    }

    // Restricted tasks and redelivery tasks without an approved item source
    // intentionally expose no item rows. An empty list is a privacy boundary,
    // not a missing-data signal to be filled by reading another table.
    final itemsMustBeEmpty =
        task.scope == DeliverySnapshotScope.restricted ||
        task.itemSource == DeliveryItemSource.unavailable ||
        task.itemSource == DeliveryItemSource.unavailableRedeliveryPlan;
    if (itemsMustBeEmpty && items.isNotEmpty) {
      throw DeliveryDtoReaders.invalid(
        'items',
        'an empty array for this task scope/source',
      );
    }

    if (!json.containsKey('notes') || json['notes'] != null) {
      throw DeliveryDtoReaders.invalid('notes', 'null in the current schema');
    }
    final notesSource = DeliveryNotesSource.fromValue(
      DeliveryDtoReaders.readRequiredString(
        json,
        'notes_source',
        nonBlank: false,
      ),
    );
    final asOf = DeliveryDtoReaders.readNullableTimestamp(json, 'as_of');
    if (asOf == null || !asOf.isUtc) {
      throw DeliveryDtoReaders.invalid(
        'as_of',
        'a required UTC RFC3339 timestamp',
      );
    }

    final cod = _readCod(json['cod']);
    final canRetry = _readCanRetry(json['capabilities']);

    return DeliveryTaskDetailsDto(
      task: task,
      items: items,
      notes: null,
      notesSource: notesSource,
      asOf: asOf,
      cod: cod,
      canRetry: canRetry,
    );
  }

  final DeliveryTaskDto task;
  final List<DeliveryTaskItemDto> items;
  final String? notes;
  final DeliveryNotesSource notesSource;
  final DateTime asOf;
  final DeliveryCodSnapshot? cod;
  final bool canRetry;

  DeliveryTaskDetails toDomain() => DeliveryTaskDetails(
    task: task.toDomain(),
    items: items.map((item) => item.toDomain()).toList(growable: false),
    notes: notes,
    notesSource: notesSource,
    asOf: asOf,
    cod: cod,
    canRetry: canRetry,
  );

  static const _responseKeys = {
    'task',
    'items',
    'notes',
    'notes_source',
    'as_of',
    'cod',
    'capabilities',
  };

  static const _taskKeys = {
    'task_id',
    'kind',
    'status',
    'attempt_number',
    'snapshot_scope',
    'order_id',
    'return_request_id',
    'amount_to_collect_vnd',
    'destination_name',
    'destination_phone',
    'destination_address',
    'destination_latitude',
    'destination_longitude',
    'assigned_at',
    'accepted_at',
    'started_at',
    'completed_at',
    'item_source',
  };

  static const _itemKeys = {
    'image_url',
    'item_id',
    'item_source',
    'product_name',
    'variant_label',
    'attributes',
    'quantity',
    'quantity_collected',
    'unit_price_vnd',
    'line_total_vnd',
  };

  static Map<String, dynamic> _asStringMap(Object raw, String key) {
    try {
      return Map<String, dynamic>.from(raw as Map);
    } on TypeError {
      throw DeliveryDtoReaders.invalid(key, 'an object with string keys');
    }
  }

  static void _checkKeys(
    Map<String, dynamic> json,
    Set<String> allowed,
    String key,
  ) {
    if (json.keys.any((entry) => !allowed.contains(entry))) {
      throw DeliveryDtoReaders.invalid(
        key,
        'only the approved projection fields',
      );
    }
  }

  static DeliveryCodSnapshot? _readCod(Object? raw) {
    if (raw == null) return null;
    if (raw is! Map) {
      throw DeliveryDtoReaders.invalid('cod', 'an object or null');
    }
    final map = _asStringMap(raw, 'cod');
    const keys = {
      'status',
      'expected_amount_vnd',
      'collected_amount_vnd',
      'received_amount_vnd',
      'collected_at',
      'handed_over_at',
      'received_at',
    };
    if (map.keys.any((key) => !keys.contains(key))) {
      throw DeliveryDtoReaders.invalid('cod', 'only the approved COD fields');
    }
    final expected = DeliveryDtoReaders.readRequiredInteger(
      map,
      'expected_amount_vnd',
    );
    final collected = DeliveryDtoReaders.readRequiredInteger(
      map,
      'collected_amount_vnd',
    );
    final received = DeliveryDtoReaders.readRequiredInteger(
      map,
      'received_amount_vnd',
    );
    if (expected < 0 ||
        collected < 0 ||
        received < 0 ||
        collected > expected ||
        received > collected) {
      throw DeliveryDtoReaders.invalid(
        'cod',
        'consistent non-negative amounts',
      );
    }
    return DeliveryCodSnapshot(
      status: DeliveryCodStatus.fromValue(
        DeliveryDtoReaders.readRequiredString(map, 'status', nonBlank: false),
      ),
      expectedAmountVnd: expected,
      collectedAmountVnd: collected,
      receivedAmountVnd: received,
      collectedAt: DeliveryDtoReaders.readNullableTimestamp(
        map,
        'collected_at',
      ),
      handedOverAt: DeliveryDtoReaders.readNullableTimestamp(
        map,
        'handed_over_at',
      ),
      receivedAt: DeliveryDtoReaders.readNullableTimestamp(map, 'received_at'),
    );
  }

  static bool _readCanRetry(Object? raw) {
    if (raw == null) return false;
    if (raw is! Map) {
      throw DeliveryDtoReaders.invalid('capabilities', 'an object or null');
    }
    final map = _asStringMap(raw, 'capabilities');
    if (map.keys.any((key) => key != 'can_retry')) {
      throw DeliveryDtoReaders.invalid(
        'capabilities',
        'only the approved capability fields',
      );
    }
    final value = map['can_retry'];
    if (value is! bool) {
      throw DeliveryDtoReaders.invalid('can_retry', 'a boolean');
    }
    return value;
  }
}
