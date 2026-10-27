import '../../domain/models/cod_collection.dart';
import '../../domain/models/cod_collection_page.dart';
import '../../domain/models/cod_collection_query.dart';
import 'cod_collection_dto.dart';

/// Strict mapper for the single snapshot returned by
/// `list_cod_collections`. It never fills totals from the current page.
final class CodCollectionPageDto {
  const CodCollectionPageDto({
    required this.items,
    required this.nextCursor,
    required this.filteredTotal,
    required this.counts,
    required this.outstandingVnd,
    required this.asOf,
  });

  factory CodCollectionPageDto.fromJson(
    Map<String, dynamic> json, {
    CodCollectionQuery? query,
  }) {
    final rawItems = json['items'];
    if (rawItems is! List) {
      throw _invalid('items', 'a JSON array');
    }
    final items = <CodCollection>[];
    final seen = <String>{};
    CodCollection? previous;
    for (final raw in rawItems) {
      if (raw is! Map) throw _invalid('items', 'an array of JSON objects');
      final row = Map<String, dynamic>.from(raw);
      final collection = CodCollectionDto.fromJson(
        row,
        requireOrderCode: true,
      ).toDomain();
      if (!seen.add(collection.orderId.toLowerCase())) {
        throw _invalid('items', 'unique order IDs');
      }
      if (query?.orderId != null &&
          collection.orderId.toLowerCase() != query!.orderId!.toLowerCase()) {
        throw _invalid('items', 'rows matching order_id');
      }
      if (query?.shipperId != null &&
          collection.shipperId?.toLowerCase() !=
              query!.shipperId!.toLowerCase()) {
        throw _invalid('items', 'rows matching shipper_id');
      }
      if (query != null &&
          query.statuses.isNotEmpty &&
          !query.statuses.contains(collection.status)) {
        throw _invalid('items', 'rows matching statuses');
      }
      if (previous != null && !_isBefore(collection, previous)) {
        throw _invalid('items', 'descending created_at/order_id order');
      }
      previous = collection;
      items.add(collection);
    }

    if (query != null && items.length > query.limit) {
      throw _invalid('items', 'no more than the requested limit');
    }

    final nextCursor = _nullableString(json, 'next_cursor');
    final filteredTotal = _integer(json, 'filtered_total', nonNegative: true);
    if (filteredTotal < items.length) {
      throw _invalid('filtered_total', 'at least the page length');
    }
    final countsRaw = json['counts'];
    if (countsRaw is! Map) throw _invalid('counts', 'a JSON object');
    final counts = CodCollectionCounts(
      all: _integer(countsRaw, 'all', nonNegative: true),
      uncollected: _integer(countsRaw, 'uncollected', nonNegative: true),
      collected: _integer(countsRaw, 'collected', nonNegative: true),
      received: _integer(countsRaw, 'received', nonNegative: true),
    );
    if (counts.all != counts.uncollected + counts.collected + counts.received) {
      throw _invalid('counts', 'an exhaustive status total');
    }
    if (query == null || query.statuses.isEmpty) {
      if (filteredTotal != counts.all) {
        throw _invalid('filtered_total', 'the complete scoped count');
      }
    } else {
      final expected = query.statuses.fold<int>(
        0,
        (sum, status) => sum + counts[status],
      );
      if (filteredTotal != expected) {
        throw _invalid('filtered_total', 'the selected status count');
      }
    }
    if (query != null) {
      if (nextCursor != null && items.length != query.limit) {
        throw _invalid('next_cursor', 'a value matching page fullness');
      }
      if (query.cursor == null) {
        final expectedFirstPage = filteredTotal < query.limit
            ? filteredTotal
            : query.limit;
        if (items.length != expectedFirstPage) {
          throw _invalid('items', 'a complete first page for the total');
        }
        if (filteredTotal > items.length && nextCursor == null) {
          throw _invalid('next_cursor', 'a cursor when more rows remain');
        }
        if (filteredTotal == items.length && nextCursor != null) {
          throw _invalid('next_cursor', 'null when the first page is complete');
        }
      }
    }
    final outstanding = _integer(json, 'outstanding_vnd', nonNegative: true);
    final pageOutstanding = items.fold<int>(
      0,
      (sum, item) => sum + item.outstandingAmountVnd,
    );
    if ((counts.collected == 0 && outstanding != 0) ||
        pageOutstanding > outstanding) {
      throw _invalid('outstanding_vnd', 'a full-scope collected total');
    }
    final pageCollectedCount = items
        .where((item) => item.status == CodStatus.collected)
        .length;
    if (query != null &&
        query.cursor == null &&
        items.length == filteredTotal &&
        pageCollectedCount == counts.collected &&
        pageOutstanding != outstanding) {
      throw _invalid('outstanding_vnd', 'the complete first-page total');
    }
    final asOf = _timestamp(json, 'as_of');
    return CodCollectionPageDto(
      items: List.unmodifiable(items),
      nextCursor: nextCursor,
      filteredTotal: filteredTotal,
      counts: counts,
      outstandingVnd: outstanding,
      asOf: asOf,
    );
  }

  final List<CodCollection> items;
  final String? nextCursor;
  final int filteredTotal;
  final CodCollectionCounts counts;
  final int outstandingVnd;
  final DateTime asOf;

  CodCollectionPage toDomain() => CodCollectionPage(
    items: items,
    nextCursor: nextCursor,
    filteredTotal: filteredTotal,
    counts: counts,
    outstandingVnd: outstandingVnd,
    asOf: asOf,
  );
}

bool _isBefore(CodCollection candidate, CodCollection cursor) {
  final time = candidate.createdAt.compareTo(cursor.createdAt);
  if (time != 0) return time < 0;
  return candidate.orderId.toLowerCase().compareTo(
        cursor.orderId.toLowerCase(),
      ) <
      0;
}

String? _nullableString(Map<dynamic, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) return null;
  final value = json[key];
  if (value is! String ||
      value.isEmpty ||
      value != value.trim() ||
      value.runes.length > CodCollectionQuery.maxCursorLength) {
    throw _invalid(key, 'null or a non-blank string');
  }
  return value;
}

int _integer(
  Map<dynamic, dynamic> json,
  String key, {
  required bool nonNegative,
}) {
  final raw = json[key];
  final BigInt parsed;
  if (raw is int) {
    parsed = BigInt.from(raw);
  } else if (raw is String && RegExp(r'^\d+$').hasMatch(raw)) {
    parsed = BigInt.parse(raw);
  } else {
    throw _invalid(key, 'a lossless integer');
  }
  if (parsed > BigInt.parse('9007199254740991') ||
      (nonNegative && parsed.isNegative)) {
    throw _invalid(key, 'a bounded integer');
  }
  return parsed.toInt();
}

DateTime _timestamp(Map<dynamic, dynamic> json, String key) {
  final raw = json[key];
  final match = raw is String
      ? RegExp(
          r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
          r'(?:\.\d+)?(Z|z|[+-]\d{2}:?\d{2})$',
        ).firstMatch(raw)
      : null;
  if (raw is! String || match == null) {
    throw _invalid(key, 'an RFC3339 timestamp with timezone');
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  if (month < 1 || month > 12 || day < 1 || day > _daysInMonth(year, month)) {
    throw _invalid(key, 'a real calendar timestamp');
  }
  if (hour > 23 || minute > 59 || second > 59) {
    throw _invalid(key, 'a real clock timestamp');
  }
  final zone = match.group(7)!;
  if (zone.toUpperCase() != 'Z') {
    final offset = zone.substring(1).replaceAll(':', '');
    if (int.parse(offset.substring(0, 2)) > 23 ||
        int.parse(offset.substring(2, 4)) > 59) {
      throw _invalid(key, 'a valid timezone offset');
    }
  }
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    throw _invalid(key, 'a valid timestamp');
  }
}

int _daysInMonth(int year, int month) {
  const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))) {
    return 29;
  }
  return days[month - 1];
}

FormatException _invalid(String key, String expected) =>
    FormatException('Invalid $key: expected $expected');
