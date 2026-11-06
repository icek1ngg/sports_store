import '../../domain/models/cod_collection.dart';

/// Strict data-boundary representation of a `cod_collections` row.
class CodCollectionDto {
  const CodCollectionDto({
    required this.orderId,
    this.orderCode,
    this.orderCodeSource,
    this.shipperId,
    required this.status,
    required this.expectedAmountVnd,
    required this.collectedAmountVnd,
    required this.receivedAmountVnd,
    this.collectedBy,
    this.receivedBy,
    this.collectedAt,
    this.handedOverAt,
    this.receivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  final String orderId;
  final String? orderCode;
  final String? orderCodeSource;
  final String? shipperId;
  final CodStatus status;
  final int expectedAmountVnd;
  final int collectedAmountVnd;
  final int receivedAmountVnd;
  final String? collectedBy;
  final String? receivedBy;
  final DateTime? collectedAt;
  final DateTime? handedOverAt;
  final DateTime? receivedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Decodes a Supabase row without coercing malformed values.
  factory CodCollectionDto.fromJson(
    Map<String, dynamic> json, {
    bool requireOrderCode = false,
  }) {
    final statusValue = _readRequiredString(json, 'status');
    final status = CodStatus.fromValue(statusValue);
    final expectedAmount = _readRequiredMoney(
      json,
      'expected_amount_vnd',
      mustBePositive: true,
    );
    final collectedAmount = _readRequiredMoney(json, 'collected_amount_vnd');
    final receivedAmount = _readRequiredMoney(json, 'received_amount_vnd');

    _validateMoneyConstraints(
      status: status,
      expectedAmountVnd: expectedAmount,
      collectedAmountVnd: collectedAmount,
      receivedAmountVnd: receivedAmount,
    );

    final orderId = _readRequiredUuid(json, 'order_id');
    final orderCode = _readOptionalOrderCode(json);
    final orderCodeSource = _readOptionalOrderCodeSource(json);
    if (requireOrderCode &&
        (orderCode != orderId || orderCodeSource != 'order_uuid')) {
      throw _invalid('order_code', 'the order UUID with source order_uuid');
    }
    return CodCollectionDto(
      orderId: orderId,
      orderCode: orderCode,
      orderCodeSource: orderCodeSource,
      shipperId: _readNullableUuid(json, 'shipper_id'),
      status: status,
      expectedAmountVnd: expectedAmount,
      collectedAmountVnd: collectedAmount,
      receivedAmountVnd: receivedAmount,
      collectedBy: _readNullableUuid(json, 'collected_by'),
      receivedBy: _readNullableUuid(json, 'received_by'),
      collectedAt: _readNullableTimestamp(json, 'collected_at'),
      handedOverAt: _readNullableTimestamp(json, 'handed_over_at'),
      receivedAt: _readNullableTimestamp(json, 'received_at'),
      createdAt: _readRequiredTimestamp(json, 'created_at'),
      updatedAt: _readRequiredTimestamp(json, 'updated_at'),
    );
  }

  CodCollection toDomain() {
    return CodCollection(
      orderId: orderId,
      orderCode: orderCode ?? orderId,
      orderCodeSource: orderCodeSource ?? 'order_uuid',
      shipperId: shipperId,
      status: status,
      expectedAmountVnd: expectedAmountVnd,
      collectedAmountVnd: collectedAmountVnd,
      receivedAmountVnd: receivedAmountVnd,
      collectedBy: collectedBy,
      receivedBy: receivedBy,
      collectedAt: collectedAt,
      handedOverAt: handedOverAt,
      receivedAt: receivedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

String? _readOptionalOrderCode(Map<String, dynamic> json) {
  if (!json.containsKey('order_code') || json['order_code'] == null) {
    return null;
  }
  if (json['order_code'] is! String ||
      (json['order_code'] as String).trim().isEmpty) {
    throw _invalid('order_code', 'null or a non-blank string');
  }
  return json['order_code'] as String;
}

String? _readOptionalOrderCodeSource(Map<String, dynamic> json) {
  if (!json.containsKey('order_code_source') ||
      json['order_code_source'] == null) {
    return null;
  }
  if (json['order_code_source'] is! String ||
      (json['order_code_source'] as String).trim().isEmpty) {
    throw _invalid('order_code_source', 'null or a non-blank string');
  }
  return json['order_code_source'] as String;
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _integerPattern = RegExp(r'^-?\d+$');
final RegExp _timestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
  r'(?:\.(\d{1,6}))?(Z|z|[+-]\d{2}:?\d{2})$',
);
final BigInt _maxSafeInteger = BigInt.parse('9007199254740991');

String _readRequiredString(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] is! String) {
    throw _invalid(key, 'a non-null string');
  }
  final value = json[key] as String;
  if (value.trim().isEmpty) {
    throw _invalid(key, 'a non-blank string');
  }
  return value;
}

String _readRequiredUuid(Map<String, dynamic> json, String key) {
  final value = _readRequiredString(json, key);
  _checkUuid(value, key);
  return value;
}

String? _readNullableUuid(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  if (json[key] is! String) {
    throw _invalid(key, 'null or a UUID');
  }
  final value = json[key] as String;
  _checkUuid(value, key);
  return value;
}

int _readRequiredMoney(
  Map<String, dynamic> json,
  String key, {
  bool mustBePositive = false,
}) {
  if (!json.containsKey(key) || json[key] == null) {
    throw _invalid(key, 'a non-negative integer');
  }

  final raw = json[key];
  final BigInt value;
  if (raw is int) {
    value = BigInt.from(raw);
  } else if (raw is String && _integerPattern.hasMatch(raw)) {
    try {
      value = BigInt.parse(raw);
    } on FormatException {
      throw _invalid(key, 'a non-negative integer');
    }
  } else {
    throw _invalid(key, 'a non-negative integer or lossless integer string');
  }

  if (value.isNegative || value > _maxSafeInteger) {
    throw _invalid(
      key,
      'a non-negative integer within the JavaScript safe range',
    );
  }
  if (mustBePositive && value == BigInt.zero) {
    throw _invalid(key, 'a positive integer');
  }
  return value.toInt();
}

DateTime _readRequiredTimestamp(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    throw _invalid(key, 'an RFC3339 timestamp with timezone');
  }
  return _parseTimestamp(json[key], key);
}

DateTime? _readNullableTimestamp(Map<String, dynamic> json, String key) {
  if (!json.containsKey(key) || json[key] == null) {
    return null;
  }
  return _parseTimestamp(json[key], key);
}

DateTime _parseTimestamp(Object? raw, String key) {
  if (raw is! String) {
    throw _invalid(key, 'null or an RFC3339 timestamp with timezone');
  }
  final match = _timestampPattern.firstMatch(raw);
  if (match == null) {
    throw _invalid(key, 'an RFC3339 timestamp with timezone');
  }

  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  if (month < 1 ||
      month > 12 ||
      day < 1 ||
      day > _daysInMonth(year, month) ||
      hour > 23 ||
      minute > 59 ||
      second > 59) {
    throw _invalid(key, 'a real calendar timestamp');
  }

  final zone = match.group(8)!;
  if (zone.toUpperCase() != 'Z') {
    final offset = zone.substring(1).replaceAll(':', '');
    final offsetHour = int.parse(offset.substring(0, 2));
    final offsetMinute = int.parse(offset.substring(2, 4));
    if (offsetHour > 23 || offsetMinute > 59) {
      throw _invalid(key, 'a valid timezone offset');
    }
  }

  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    throw _invalid(key, 'a valid timestamp');
  }
}

void _checkUuid(String value, String key) {
  if (!_uuidPattern.hasMatch(value)) {
    throw _invalid(key, 'a UUID');
  }
}

void _validateMoneyConstraints({
  required CodStatus status,
  required int expectedAmountVnd,
  required int collectedAmountVnd,
  required int receivedAmountVnd,
}) {
  if (expectedAmountVnd <= 0) {
    throw _invalid('expected_amount_vnd', 'a positive integer');
  }
  if (collectedAmountVnd > expectedAmountVnd) {
    throw _invalid('collected_amount_vnd', 'no more than expected_amount_vnd');
  }
  if (receivedAmountVnd > collectedAmountVnd) {
    throw _invalid('received_amount_vnd', 'no more than collected_amount_vnd');
  }

  final collectedMatchesStatus = switch (status) {
    CodStatus.uncollected => collectedAmountVnd == 0,
    CodStatus.collected ||
    CodStatus.received => collectedAmountVnd == expectedAmountVnd,
  };
  if (!collectedMatchesStatus) {
    throw _invalid('collected_amount_vnd', 'an amount matching status');
  }

  final receivedMatchesStatus = switch (status) {
    CodStatus.uncollected || CodStatus.collected => receivedAmountVnd == 0,
    CodStatus.received => receivedAmountVnd == expectedAmountVnd,
  };
  if (!receivedMatchesStatus) {
    throw _invalid('received_amount_vnd', 'an amount matching status');
  }
}

int _daysInMonth(int year, int month) {
  const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) {
    return 29;
  }
  return days[month - 1];
}

bool _isLeapYear(int year) {
  return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
}

FormatException _invalid(String key, String expected) {
  return FormatException('Invalid $key: expected $expected');
}
