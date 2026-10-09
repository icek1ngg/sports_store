/// Thrown when a server response cannot be represented by the current
/// contract.  The raw value is kept so callers can log a safe diagnostic or
/// render an unsupported-data state without guessing a default.
class UnsupportedDataException extends FormatException {
  UnsupportedDataException(
    super.message, {
    this.path,
    this.rawValue,
    this.expected,
  });

  final String? path;
  final Object? rawValue;
  final String? expected;

  factory UnsupportedDataException.missing(String path) {
    return UnsupportedDataException(
      'Required response field is missing: $path.',
      path: path,
      expected: 'present key',
    );
  }

  factory UnsupportedDataException.invalid({
    required String path,
    required Object? rawValue,
    required String expected,
  }) {
    return UnsupportedDataException(
      'Unsupported value at $path; expected $expected.',
      path: path,
      rawValue: rawValue,
      expected: expected,
    );
  }

  factory UnsupportedDataException.unknownEnum({
    required String path,
    required String enumName,
    required Object? rawValue,
  }) {
    return UnsupportedDataException(
      'Unsupported $enumName value at $path.',
      path: path,
      rawValue: rawValue,
      expected: enumName,
    );
  }
}

/// Raised for a caller-created command that violates a domain invariant.
/// Server response parsing should use [UnsupportedDataException] instead.
class InvalidDomainArgumentException extends ArgumentError {
  InvalidDomainArgumentException(super.message);
}
