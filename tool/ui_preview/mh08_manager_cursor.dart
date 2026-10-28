import 'dart:convert';

import 'package:sports_store/core/errors/app_failure.dart';
import 'package:sports_store/features/orders/domain/models/order_query.dart';

/// Opaque demo cursor codec bound to normalized query and session revision.
class Mh08ManagerCursor {
  static String? normalizeSearch(String? value) {
    if (value == null) return null;
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'\s+'),
      ' ',
    );
    return normalized.isEmpty ? null : normalized;
  }

  String encode(OrderQuery query, int offset, int generation) {
    final signature = _signature(query, generation);
    final payload = {
      'v': 1,
      'generation': generation,
      'signature': signature,
      'offset': offset,
      'limit': query.limit,
      'search': normalizeSearch(query.search),
      'statuses': query.statuses.map((status) => status.wireValue).toList(),
    };
    return base64Url
        .encode(utf8.encode(jsonEncode(payload)))
        .replaceAll('=', '');
  }

  int decode(OrderQuery query, int generation) {
    final cursor = query.cursor;
    if (cursor == null) return 0;
    try {
      final decoded = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(cursor))),
      );
      if (decoded is! Map || decoded['v'] != 1) _invalidCursor();
      final statuses = decoded['statuses'];
      final expected = query.statuses
          .map((status) => status.wireValue)
          .toList();
      if (decoded['generation'] != generation ||
          decoded['signature'] != _signature(query, generation) ||
          decoded['limit'] != query.limit ||
          decoded['search'] != normalizeSearch(query.search) ||
          statuses is! List ||
          statuses.length != expected.length ||
          !List.generate(
            expected.length,
            (index) => statuses[index] == expected[index],
          ).every((value) => value)) {
        _invalidCursor();
      }
      final offset = decoded['offset'];
      if (offset is! int || offset < 0) _invalidCursor();
      return offset;
    } on AppFailure {
      rethrow;
    } catch (_) {
      _invalidCursor();
    }
  }

  String _signature(OrderQuery query, int generation) {
    final input = [
      generation,
      query.limit,
      normalizeSearch(query.search) ?? '',
      ...query.statuses.map((status) => status.wireValue),
    ].join('|');
    var hash = 2166136261;
    for (final codeUnit in input.codeUnits) {
      hash = ((hash ^ codeUnit) * 16777619) & 0x7fffffff;
    }
    return hash.toRadixString(16);
  }

  Never _invalidCursor() =>
      throw const AppFailure(code: AppFailure.invalidCursor);
}
