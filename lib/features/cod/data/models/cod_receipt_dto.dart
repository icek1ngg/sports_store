import '../../domain/models/cod_receipt.dart';

/// Strict response-boundary mapper for `confirm_cod_received`.
///
/// A JSON object is not considered a receipt merely because it has the
/// expected keys. Every identifier, amount, state and timestamp is checked,
/// and mutable identity/amount fields are compared with the command and the
/// server-managed manager identity before conversion to the domain model.
final class CodReceiptDto {
  const CodReceiptDto({
    required this.orderId,
    required this.status,
    required this.receivedAmountVnd,
    required this.receivedBy,
    required this.receivedAt,
    required this.handedOverAt,
    required this.eventId,
    required this.notificationId,
  });

  final String orderId;
  final CodReceiptStatus status;
  final int receivedAmountVnd;
  final String receivedBy;
  final DateTime receivedAt;
  final DateTime handedOverAt;
  final String eventId;
  final String notificationId;

  factory CodReceiptDto.fromJson(
    Map<String, dynamic> json, {
    required CodReceiptCommand command,
    required String managerId,
  }) {
    command.validate();
    _checkUuid(managerId, 'managerId');

    final orderId = _readRequiredUuid(json, 'order_id');
    if (!_sameUuid(orderId, command.orderId)) {
      throw const FormatException('Invalid order_id: does not match request');
    }

    final statusValue = _readRequiredString(json, 'status');
    final status = CodReceiptStatus.fromValue(statusValue);
    final receivedAmountVnd = _readRequiredMoney(json, 'received_amount_vnd');
    if (receivedAmountVnd != command.receivedAmountVnd) {
      throw const FormatException(
        'Invalid received_amount_vnd: does not match request',
      );
    }

    final receivedBy = _readRequiredUuid(json, 'received_by');
    if (!_sameUuid(receivedBy, managerId)) {
      throw const FormatException(
        'Invalid received_by: does not match current manager',
      );
    }

    final receivedAt = _readRequiredTimestamp(json, 'received_at');
    final handedOverAt = _readRequiredTimestamp(json, 'handed_over_at');
    if (receivedAt != handedOverAt) {
      throw const FormatException(
        'Invalid handed_over_at: must equal received_at',
      );
    }

    return CodReceiptDto(
      orderId: orderId,
      status: status,
      receivedAmountVnd: receivedAmountVnd,
      receivedBy: receivedBy,
      receivedAt: receivedAt,
      handedOverAt: handedOverAt,
      eventId: _readRequiredUuid(json, 'event_id'),
      notificationId: _readRequiredUuid(json, 'notification_id'),
    );
  }

  CodReceipt toDomain() => CodReceipt(
    orderId: orderId,
    status: status,
    receivedAmountVnd: receivedAmountVnd,
    receivedBy: receivedBy,
    receivedAt: receivedAt,
    handedOverAt: handedOverAt,
    eventId: eventId,
    notificationId: notificationId,
  );
}

final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);
final RegExp _integerPattern = RegExp(r'^\d+$');
final RegExp _timestampPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
  r'(?:\.(\d{1,6}))?(Z|z|[+-]\d{2}:?\d{2})$',
);
final BigInt _maxSafeInteger = BigInt.parse('9007199254740991');

String _readRequiredString(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String || raw.trim().isEmpty) {
    throw FormatException('Invalid $key: expected a non-blank string');
  }
  return raw;
}

String _readRequiredUuid(Map<String, dynamic> json, String key) {
  final value = _readRequiredString(json, key);
  _checkUuid(value, key);
  return value;
}

int _readRequiredMoney(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final BigInt value;
  if (raw is int) {
    value = BigInt.from(raw);
  } else if (raw is String && _integerPattern.hasMatch(raw)) {
    try {
      value = BigInt.parse(raw);
    } on FormatException {
      throw FormatException('Invalid $key: expected a safe integer');
    }
  } else {
    throw FormatException('Invalid $key: expected a safe integer');
  }
  if (value <= BigInt.zero || value > _maxSafeInteger) {
    throw FormatException('Invalid $key: expected a positive safe integer');
  }
  return value.toInt();
}

DateTime _readRequiredTimestamp(Map<String, dynamic> json, String key) {
  final raw = json[key];
  if (raw is! String) {
    throw FormatException('Invalid $key: expected an RFC3339 timestamp');
  }
  final match = _timestampPattern.firstMatch(raw);
  if (match == null) {
    throw FormatException('Invalid $key: expected an RFC3339 timestamp');
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
    throw FormatException('Invalid $key: expected a real timestamp');
  }

  final zone = match.group(8)!;
  if (zone.toUpperCase() != 'Z') {
    final offset = zone.substring(1).replaceAll(':', '');
    final offsetHour = int.parse(offset.substring(0, 2));
    final offsetMinute = int.parse(offset.substring(2, 4));
    if (offsetHour > 23 || offsetMinute > 59) {
      throw FormatException('Invalid $key: expected a valid timezone offset');
    }
  }
  try {
    return DateTime.parse(raw).toUtc();
  } on FormatException {
    throw FormatException('Invalid $key: expected a valid timestamp');
  }
}

void _checkUuid(String value, String key) {
  if (!_uuidPattern.hasMatch(value)) {
    throw FormatException('Invalid $key: expected a UUID');
  }
}

bool _sameUuid(String left, String right) =>
    left.toLowerCase() == right.toLowerCase();

int _daysInMonth(int year, int month) {
  const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2 && _isLeapYear(year)) return 29;
  return days[month - 1];
}

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
