/// Strict readers shared by delivery projection DTOs.
///
/// The read RPC is intentionally small, so malformed values must fail at the
/// data boundary instead of being silently coerced into a domain snapshot.
class DeliveryDtoReaders {
  static final RegExp _uuidPattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
    r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  static final RegExp _integerPattern = RegExp(r'^\d+$');

  static final RegExp _decimalPattern = RegExp(
    r'^[+-]?(?:(?:\d+(?:\.\d*)?)|(?:\.\d+))$',
  );

  static final RegExp _timestampPattern = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})'
    r'(?:\.(\d{1,6}))?(Z|z|[+-]\d{2}:?\d{2})$',
  );

  static final BigInt _maxSafeInteger = BigInt.parse('9007199254740991');

  static String readRequiredString(
    Map<String, dynamic> json,
    String key, {
    bool nonBlank = true,
  }) {
    if (!json.containsKey(key) || json[key] == null) {
      throw _invalid(key, 'a non-null string');
    }
    final value = json[key];
    if (value is! String || (nonBlank && value.trim().isEmpty)) {
      throw _invalid(key, 'a non-blank string');
    }
    return value;
  }

  static String? readNullableString(
    Map<String, dynamic> json,
    String key, {
    bool nonBlank = true,
  }) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    final value = json[key];
    if (value is! String || (nonBlank && value.trim().isEmpty)) {
      throw _invalid(key, 'null or a non-blank string');
    }
    return value;
  }

  static String readRequiredUuid(Map<String, dynamic> json, String key) {
    final value = readRequiredString(json, key, nonBlank: false);
    _checkUuid(value, key);
    return value;
  }

  static String? readNullableUuid(Map<String, dynamic> json, String key) {
    final value = readNullableString(json, key, nonBlank: false);
    if (value == null) {
      return null;
    }
    _checkUuid(value, key);
    return value;
  }

  static int readRequiredInteger(
    Map<String, dynamic> json,
    String key, {
    bool nonNegative = true,
  }) {
    final value = readNullableInteger(json, key, nonNegative: nonNegative);
    if (value == null) {
      throw _invalid(key, 'a safe integer');
    }
    return value;
  }

  static int? readNullableInteger(
    Map<String, dynamic> json,
    String key, {
    bool nonNegative = true,
  }) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }

    final raw = json[key];
    BigInt value;
    if (raw is int) {
      value = BigInt.from(raw);
    } else if (raw is String && _integerPattern.hasMatch(raw)) {
      value = BigInt.parse(raw);
    } else {
      throw _invalid(key, 'a safe integer or lossless integer string');
    }

    if (nonNegative && value.isNegative) {
      throw _invalid(key, 'a non-negative integer');
    }
    if (value > _maxSafeInteger || value < -_maxSafeInteger) {
      throw _invalid(key, 'an integer within the JavaScript safe range');
    }
    return value.toInt();
  }

  static double readRequiredCoordinate(
    Map<String, dynamic> json,
    String key, {
    required double minimum,
    required double maximum,
  }) {
    final value = readNullableCoordinate(
      json,
      key,
      minimum: minimum,
      maximum: maximum,
    );
    if (value == null) {
      throw _invalid(key, 'a finite coordinate');
    }
    return value;
  }

  static double? readNullableCoordinate(
    Map<String, dynamic> json,
    String key, {
    required double minimum,
    required double maximum,
  }) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }

    final raw = json[key];
    final value = switch (raw) {
      num number when number.isFinite => number.toDouble(),
      String text when _decimalPattern.hasMatch(text) => double.tryParse(text),
      _ => null,
    };
    if (value == null ||
        !value.isFinite ||
        value < minimum ||
        value > maximum) {
      throw _invalid(key, 'a finite coordinate in [$minimum, $maximum]');
    }
    return value;
  }

  static DateTime? readNullableTimestamp(
    Map<String, dynamic> json,
    String key,
  ) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    final raw = json[key];
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
    final fraction = match.group(7);
    final zone = match.group(8)!;

    if (month < 1 ||
        month > 12 ||
        day < 1 ||
        day > _daysInMonth(year, month) ||
        hour > 23 ||
        minute > 59 ||
        second > 59) {
      throw _invalid(key, 'a real calendar timestamp');
    }

    if (zone.toUpperCase() != 'Z') {
      final offset = zone.substring(1).replaceAll(':', '');
      final offsetHour = int.parse(offset.substring(0, 2));
      final offsetMinute = int.parse(offset.substring(2, 4));
      if (offsetHour > 23 || offsetMinute > 59) {
        throw _invalid(key, 'a valid timezone offset');
      }
    }

    final microseconds = fraction == null
        ? 0
        : int.parse(fraction.padRight(6, '0'));
    try {
      // DateTime.parse handles the offset and converts an offset timestamp to
      // UTC. Calendar components were checked above because DateTime.parse
      // accepts and rolls over some invalid dates.
      final parsed = DateTime.parse(raw).toUtc();
      // This also guards against a parser accepting an impossible time value.
      if (parsed.microsecond != microseconds % 1000 ||
          parsed.millisecond != (microseconds ~/ 1000) % 1000) {
        throw _invalid(key, 'a valid timestamp');
      }
      return parsed;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw _invalid(key, 'a valid timestamp');
    }
  }

  static Map<String, dynamic>? readNullableJsonObject(
    Map<String, dynamic> json,
    String key,
  ) {
    if (!json.containsKey(key) || json[key] == null) {
      return null;
    }
    final raw = json[key];
    if (raw is! Map) {
      throw _invalid(key, 'null or a JSON object');
    }
    final frozen = <String, dynamic>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) {
        throw _invalid(key, 'a JSON object with string keys');
      }
      frozen[entry.key as String] = _freezeJson(entry.value, key);
    }
    return Map.unmodifiable(frozen);
  }

  static void checkUuid(String value, String key) => _checkUuid(value, key);

  static FormatException invalid(String key, String expected) =>
      _invalid(key, expected);

  static FormatException _invalid(String key, String expected) {
    return FormatException('Invalid $key: expected $expected');
  }

  static void _checkUuid(String value, String key) {
    if (!_uuidPattern.hasMatch(value)) {
      throw _invalid(key, 'a UUID');
    }
  }

  static int _daysInMonth(int year, int month) {
    const days = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
    if (month == 2 && _isLeapYear(year)) {
      return 29;
    }
    return days[month - 1];
  }

  static bool _isLeapYear(int year) {
    return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
  }

  static dynamic _freezeJson(Object? value, String key) {
    if (value == null || value is String || value is bool) {
      return value;
    }
    if (value is num) {
      if (!value.isFinite) {
        throw _invalid(key, 'JSON numbers that are finite');
      }
      return value;
    }
    if (value is Map) {
      final frozen = <String, dynamic>{};
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw _invalid(key, 'JSON objects with string keys');
        }
        frozen[entry.key as String] = _freezeJson(entry.value, key);
      }
      return Map.unmodifiable(frozen);
    }
    if (value is List) {
      return List.unmodifiable(
        value.map<Object?>((item) => _freezeJson(item, key)),
      );
    }
    throw _invalid(key, 'a JSON value');
  }
}
