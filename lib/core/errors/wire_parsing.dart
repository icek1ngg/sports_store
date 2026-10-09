import 'unsupported_data_exception.dart';

/// Returns a required map field, distinguishing a missing key from a nullable
/// key whose value is explicitly null.
Object? requiredField(Map<String, Object?> map, String key) {
  if (!map.containsKey(key)) {
    throw UnsupportedDataException.missing(key);
  }
  return map[key];
}

Object? nullableField(Map<String, Object?> map, String key) {
  return requiredField(map, key);
}

String requiredString(
  Map<String, Object?> map,
  String key, {
  bool nonBlank = false,
}) {
  final value = requiredField(map, key);
  if (value is! String || (nonBlank && value.trim().isEmpty)) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: nonBlank ? 'non-blank string' : 'string',
    );
  }
  return value;
}

String? nullableString(
  Map<String, Object?> map,
  String key, {
  bool nonBlank = false,
}) {
  final value = requiredField(map, key);
  if (value == null) return null;
  if (value is! String || (nonBlank && value.trim().isEmpty)) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: nonBlank ? 'null or non-blank string' : 'null or string',
    );
  }
  return value;
}

int requiredInt(Map<String, Object?> map, String key, {int? min, int? max}) {
  final value = requiredField(map, key);
  if (value is! int ||
      (min != null && value < min) ||
      (max != null && value > max)) {
    final range = [
      if (min != null) '>= $min',
      if (max != null) '<= $max',
    ].join(' and ');
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: range.isEmpty ? 'integer' : 'integer $range',
    );
  }
  return value;
}

int? nullableInt(Map<String, Object?> map, String key, {int? min, int? max}) {
  final value = requiredField(map, key);
  if (value == null) return null;
  if (value is! int ||
      (min != null && value < min) ||
      (max != null && value > max)) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'null or integer',
    );
  }
  return value;
}

double requiredFiniteDouble(
  Map<String, Object?> map,
  String key, {
  double? min,
  double? max,
}) {
  final value = requiredField(map, key);
  if (value is! num) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'finite JSON number',
    );
  }
  final result = value.toDouble();
  if (!result.isFinite ||
      (min != null && result < min) ||
      (max != null && result > max)) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'finite number in range',
    );
  }
  return result;
}

double? nullableFiniteDouble(
  Map<String, Object?> map,
  String key, {
  double? min,
  double? max,
}) {
  final value = requiredField(map, key);
  if (value == null) return null;
  if (value is! num) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'null or finite JSON number',
    );
  }
  final result = value.toDouble();
  if (!result.isFinite ||
      (min != null && result < min) ||
      (max != null && result > max)) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'null or finite number in range',
    );
  }
  return result;
}

bool requiredBool(Map<String, Object?> map, String key) {
  final value = requiredField(map, key);
  if (value is! bool) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'boolean',
    );
  }
  return value;
}

Map<String, Object?> requiredObject(Map<String, Object?> map, String key) {
  final value = requiredField(map, key);
  if (value is! Map) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'object',
    );
  }
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'object with string keys',
    );
  }
}

Map<String, Object?>? nullableObject(Map<String, Object?> map, String key) {
  final value = requiredField(map, key);
  if (value == null) return null;
  if (value is! Map) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'null or object',
    );
  }
  try {
    return Map<String, Object?>.from(value);
  } on TypeError {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'null or object with string keys',
    );
  }
}

List<Object?> requiredList(Map<String, Object?> map, String key) {
  final value = requiredField(map, key);
  if (value is! List) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'array',
    );
  }
  return List<Object?>.from(value);
}

String requiredUuid(Map<String, Object?> map, String key) {
  final value = requiredString(map, key);
  if (!_isUuid(value)) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'UUID',
    );
  }
  return value.toLowerCase();
}

String? nullableUuid(Map<String, Object?> map, String key) {
  final value = requiredField(map, key);
  if (value == null) return null;
  if (value is! String || !_isUuid(value)) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'null or UUID',
    );
  }
  return value.toLowerCase();
}

DateTime requiredUtcTimestamp(Map<String, Object?> map, String key) {
  final value = requiredString(map, key);
  return parseUtcTimestamp(value, path: key);
}

DateTime? nullableUtcTimestamp(Map<String, Object?> map, String key) {
  final value = requiredField(map, key);
  if (value == null) return null;
  if (value is! String) {
    throw UnsupportedDataException.invalid(
      path: key,
      rawValue: value,
      expected: 'null or ISO-8601 timestamp with offset',
    );
  }
  return parseUtcTimestamp(value, path: key);
}

DateTime parseUtcTimestamp(String value, {String path = 'timestamp'}) {
  // DateTime.parse accepts a few non-ISO forms and normalizes out-of-range
  // calendar components (for example, February 30).  Wire timestamps are
  // server-defined business facts, so validate the lexical form and compare
  // every parsed component before returning a UTC value.
  final match = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.(\d{1,6}))?(Z|z|[+-]\d{2}:\d{2})$',
  ).firstMatch(value);
  if (match == null) {
    throw UnsupportedDataException.invalid(
      path: path,
      rawValue: value,
      expected: 'ISO-8601 timestamp with explicit UTC offset',
    );
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.parse(match.group(6)!);
  final fraction = match.group(7);
  final microsecond = fraction == null
      ? 0
      : int.parse(fraction.padRight(6, '0'));
  final offset = match.group(8)!;
  final offsetMinutes = _offsetMinutes(offset);
  if (offsetMinutes == null) {
    throw UnsupportedDataException.invalid(
      path: path,
      rawValue: value,
      expected: 'valid ISO-8601 UTC offset',
    );
  }

  final local = DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    microsecond,
  );
  if (local.year != year ||
      local.month != month ||
      local.day != day ||
      local.hour != hour ||
      local.minute != minute ||
      local.second != second ||
      local.microsecond != microsecond) {
    throw UnsupportedDataException.invalid(
      path: path,
      rawValue: value,
      expected: 'valid calendar date and time',
    );
  }
  final parsed = DateTime.tryParse(value);
  final expectedUtc = local.subtract(Duration(minutes: offsetMinutes));
  if (parsed == null || parsed.toUtc() != expectedUtc) {
    throw UnsupportedDataException.invalid(
      path: path,
      rawValue: value,
      expected: 'valid ISO-8601 timestamp',
    );
  }
  return expectedUtc;
}

int? _offsetMinutes(String value) {
  if (value == 'Z' || value == 'z') return 0;
  final sign = value.codeUnitAt(0) == 0x2D ? -1 : 1;
  final hours = int.tryParse(value.substring(1, 3));
  final minutes = int.tryParse(value.substring(4, 6));
  if (hours == null || minutes == null || hours > 23 || minutes > 59) {
    return null;
  }
  return sign * (hours * 60 + minutes);
}

/// Deeply copies and freezes JSON-like values so DTO/domain models cannot be
/// changed through a caller's original map or a nested list.
Object? deepFreeze(Object? value) {
  if (value is Map) {
    final copy = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw UnsupportedDataException.invalid(
          path: 'object',
          rawValue: entry.key,
          expected: 'string key',
        );
      }
      copy[entry.key as String] = deepFreeze(entry.value);
    }
    return Map<String, Object?>.unmodifiable(copy);
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(deepFreeze));
  }
  if (value is num && value is! int && !value.isFinite) {
    throw UnsupportedDataException.invalid(
      path: 'value',
      rawValue: value,
      expected: 'finite number',
    );
  }
  return value;
}

Map<String, Object?> immutableObject(Map<String, Object?> value) {
  return deepFreeze(value) as Map<String, Object?>;
}

List<T> immutableList<T>(Iterable<T> values) {
  return List<T>.unmodifiable(values);
}

bool _isUuid(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}
