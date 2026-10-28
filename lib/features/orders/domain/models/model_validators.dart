import '../../../../core/errors/unsupported_data_exception.dart';

export '../../../../core/errors/unsupported_data_exception.dart'
    show InvalidDomainArgumentException;

String validateUuidValue(String value, {String field = 'id'}) {
  final parts = value.split('-');
  final valid =
      parts.length == 5 &&
      parts[0].length == 8 &&
      parts[1].length == 4 &&
      parts[2].length == 4 &&
      parts[3].length == 4 &&
      parts[4].length == 12 &&
      RegExp(r'^[0-9a-fA-F-]+$').hasMatch(value);
  if (!valid) {
    throw InvalidDomainArgumentException('$field must be a UUID.');
  }
  return value.toLowerCase();
}

String validateNonBlank(String value, {required String field}) {
  if (value.trim().isEmpty) {
    throw InvalidDomainArgumentException('$field must not be blank.');
  }
  return value;
}

/// Trims the exact Unicode White_Space set agreed by the receipt fingerprint
/// contract.  Dart's default [String.trim] is intentionally not used because
/// the contract includes U+0085 and names every accepted boundary code point.
String contractTrim(String value) {
  final runes = value.runes.toList();
  var start = 0;
  var end = runes.length;
  while (start < end && _contractWhitespace.contains(runes[start])) {
    start++;
  }
  while (end > start && _contractWhitespace.contains(runes[end - 1])) {
    end--;
  }
  return String.fromCharCodes(runes.sublist(start, end));
}

const _contractWhitespace = <int>{
  0x0009,
  0x000A,
  0x000B,
  0x000C,
  0x000D,
  0x0020,
  0x0085,
  0x00A0,
  0x1680,
  0x2000,
  0x2001,
  0x2002,
  0x2003,
  0x2004,
  0x2005,
  0x2006,
  0x2007,
  0x2008,
  0x2009,
  0x200A,
  0x2028,
  0x2029,
  0x202F,
  0x205F,
  0x3000,
};

int validateNonNegativeInt(int value, {required String field}) {
  if (value < 0) {
    throw InvalidDomainArgumentException('$field must be non-negative.');
  }
  return value;
}

int validatePositiveInt(int value, {required String field}) {
  if (value <= 0) {
    throw InvalidDomainArgumentException('$field must be positive.');
  }
  return value;
}

double validateCoordinate(
  double value, {
  required String field,
  required double min,
  required double max,
}) {
  if (!value.isFinite || value < min || value > max) {
    throw InvalidDomainArgumentException('$field is outside its valid range.');
  }
  return value;
}

DateTime validateUtc(DateTime value, {required String field}) {
  if (!value.isUtc) {
    throw InvalidDomainArgumentException('$field must be UTC.');
  }
  return value;
}

Map<String, Object?> freezeObject(Map<String, Object?> value) {
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    result[entry.key] = _freeze(entry.value);
  }
  return Map<String, Object?>.unmodifiable(result);
}

Object? _freeze(Object? value) {
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw InvalidDomainArgumentException('Object keys must be strings.');
      }
      result[entry.key as String] = _freeze(entry.value);
    }
    return Map<String, Object?>.unmodifiable(result);
  }
  if (value is List) return List<Object?>.unmodifiable(value.map(_freeze));
  return value;
}
