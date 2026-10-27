import '../../domain/models/delivery_task_query.dart';
import '../../domain/models/delivery_task.dart';
import 'delivery_task_dto.dart';
import 'dto_readers.dart';

/// Strict mapper for the JSON object returned by `list_my_delivery_tasks`.
///
/// Only the approved task projection is delegated to [DeliveryTaskDto].  No
/// order or return-request rows are accepted here, so a backend shape change
/// fails closed instead of becoming a broad read.
final class DeliveryTaskPageDto {
  const DeliveryTaskPageDto({
    required this.items,
    required this.nextCursor,
    required this.filteredTotal,
    required this.counts,
    required this.asOf,
  });

  factory DeliveryTaskPageDto.fromJson(
    Map<String, dynamic> json, {
    DeliveryTaskQuery? query,
  }) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw DeliveryDtoReaders.invalid('items', 'a JSON array');
    }
    final items = <DeliveryTaskDto>[];
    final ids = <String>{};
    for (final rawItem in rawItems) {
      if (rawItem is! Map) {
        throw DeliveryDtoReaders.invalid('items', 'an array of JSON objects');
      }
      final item = DeliveryTaskDto.fromJson(Map<String, dynamic>.from(rawItem));
      if (query?.kind != null && item.kind != query!.kind) {
        throw DeliveryDtoReaders.invalid(
          'items',
          'tasks matching the requested kind',
        );
      }
      if (query?.stateGroup != null &&
          !_matchesGroup(item.status, query!.stateGroup!)) {
        throw DeliveryDtoReaders.invalid(
          'items',
          'tasks matching the requested state group',
        );
      }
      if (!ids.add(item.taskId.toLowerCase())) {
        throw DeliveryDtoReaders.invalid('items', 'unique task IDs');
      }
      items.add(item);
    }

    final nextCursor = DeliveryDtoReaders.readNullableString(
      json,
      'next_cursor',
      nonBlank: false,
    );
    if (nextCursor != null) {
      if (nextCursor.trim().isEmpty ||
          nextCursor.runes.length > DeliveryTaskQuery.maxCursorLength) {
        throw DeliveryDtoReaders.invalid(
          'next_cursor',
          'a bounded non-empty opaque cursor',
        );
      }
    }

    final filteredTotal = DeliveryDtoReaders.readRequiredInteger(
      json,
      'filtered_total',
    );
    final counts = _readCounts(json['counts']);
    final asOf = DeliveryDtoReaders.readNullableTimestamp(json, 'as_of');
    if (asOf == null) {
      throw DeliveryDtoReaders.invalid(
        'as_of',
        'an RFC3339 timestamp with timezone',
      );
    }

    if (filteredTotal < items.length) {
      throw DeliveryDtoReaders.invalid(
        'filtered_total',
        'a value at least as large as the page length',
      );
    }
    if (query == null) {
      // Without the request context we cannot infer a page size or distinguish
      // a later cursor page. A non-empty total therefore cannot be represented
      // by an empty first page.
      if (items.isEmpty && filteredTotal > 0) {
        throw DeliveryDtoReaders.invalid(
          'items',
          'a non-empty page when filtered_total is positive',
        );
      }
    } else {
      if (items.length > query.limit) {
        throw DeliveryDtoReaders.invalid(
          'items',
          'at most the requested page limit',
        );
      }
      if (nextCursor != null && items.isEmpty) {
        throw DeliveryDtoReaders.invalid(
          'next_cursor',
          'null when the page is empty',
        );
      }
      if (nextCursor != null && filteredTotal <= items.length) {
        throw DeliveryDtoReaders.invalid(
          'next_cursor',
          'a cursor only when more filtered rows exist',
        );
      }
      if (query.cursor == null) {
        final expectedLength = filteredTotal < query.limit
            ? filteredTotal
            : query.limit;
        if (items.length != expectedLength) {
          throw DeliveryDtoReaders.invalid(
            'items',
            'the expected first-page length',
          );
        }
        final shouldHaveNextCursor = filteredTotal > items.length;
        if ((nextCursor != null) != shouldHaveNextCursor) {
          throw DeliveryDtoReaders.invalid(
            'next_cursor',
            'a cursor exactly when the first page has more rows',
          );
        }
      } else if (nextCursor != null && items.length != query.limit) {
        throw DeliveryDtoReaders.invalid(
          'items',
          'a full page when next_cursor is present',
        );
      }
    }
    if (query == null) {
      if (filteredTotal != counts.total) {
        throw DeliveryDtoReaders.invalid(
          'filtered_total',
          'the total represented by counts when no state filter is supplied',
        );
      }
    } else {
      final expected = switch (query.stateGroup) {
        null => counts.total,
        DeliveryTaskStateGroup.waiting => counts.waiting,
        DeliveryTaskStateGroup.inTransit => counts.inTransit,
        DeliveryTaskStateGroup.completed => counts.completed,
      };
      if (filteredTotal != expected) {
        throw DeliveryDtoReaders.invalid(
          'filtered_total',
          'the selected state-group count',
        );
      }
    }

    return DeliveryTaskPageDto(
      items: List.unmodifiable(items),
      nextCursor: nextCursor,
      filteredTotal: filteredTotal,
      counts: counts,
      asOf: asOf,
    );
  }

  final List<DeliveryTaskDto> items;
  final String? nextCursor;
  final int filteredTotal;
  final DeliveryTaskCounts counts;
  final DateTime asOf;

  DeliveryTaskPage toDomain() => DeliveryTaskPage(
    items: items.map((item) => item.toDomain()).toList(growable: false),
    nextCursor: nextCursor,
    filteredTotal: filteredTotal,
    counts: counts,
    asOf: asOf,
  );

  static DeliveryTaskCounts _readCounts(Object? raw) {
    if (raw is! Map) {
      throw DeliveryDtoReaders.invalid('counts', 'a JSON object');
    }
    final map = Map<String, dynamic>.from(raw);
    return DeliveryTaskCounts(
      waiting: _readCount(map, 'waiting'),
      inTransit: _readCount(map, 'in_transit'),
      completed: _readCount(map, 'completed'),
      ungrouped: _readCount(map, 'ungrouped'),
    );
  }

  static int _readCount(Map<String, dynamic> map, String key) {
    final value = DeliveryDtoReaders.readRequiredInteger(map, key);
    if (value < 0) {
      throw DeliveryDtoReaders.invalid(key, 'a non-negative integer');
    }
    return value;
  }

  static bool _matchesGroup(
    DeliveryTaskStatus status,
    DeliveryTaskStateGroup group,
  ) {
    return switch (group) {
      DeliveryTaskStateGroup.waiting =>
        status == DeliveryTaskStatus.assigned ||
            status == DeliveryTaskStatus.accepted,
      DeliveryTaskStateGroup.inTransit =>
        status == DeliveryTaskStatus.inTransit,
      DeliveryTaskStateGroup.completed =>
        status == DeliveryTaskStatus.delivered ||
            status == DeliveryTaskStatus.returnedToStore,
    };
  }
}
