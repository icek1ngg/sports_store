import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sports_store/core/errors/unsupported_data_exception.dart';
import 'package:sports_store/core/errors/wire_parsing.dart';

void main() {
  group('parseUtcTimestamp fractional seconds', () {
    test(
      'accepts the six-digit fraction Supabase returns (MH13 regression)',
      () {
        final parsed = parseUtcTimestamp('2026-11-02T03:58:48.986112+00:00');

        expect(parsed.isUtc, isTrue);
        expect([parsed.year, parsed.month, parsed.day], [2026, 11, 2]);
        expect([parsed.hour, parsed.minute, parsed.second], [3, 58, 48]);
        expect(parsed.millisecond, 986);
        // The web runtime keeps millisecond precision only.
        if (!kIsWeb) expect(parsed.microsecond, 112);
      },
    );

    test('accepts the largest fraction without rolling the second over', () {
      final parsed = parseUtcTimestamp('2026-10-30T03:20:05.999999Z');

      expect(parsed.second, 5);
      expect(parsed.millisecond, 999);
      if (!kIsWeb) expect(parsed.microsecond, 999);
    });

    test('pads short fractions as fractions of a second', () {
      expect(parseUtcTimestamp('2026-10-30T03:20:05.1Z').millisecond, 100);
      expect(parseUtcTimestamp('2026-10-30T03:20:05.12Z').millisecond, 120);
      expect(parseUtcTimestamp('2026-10-30T03:20:05.123Z').millisecond, 123);
    });

    test('accepts timestamps without a fraction', () {
      final parsed = parseUtcTimestamp('2026-10-30T03:20:05+00:00');

      expect(parsed, DateTime.utc(2026, 10, 30, 3, 20, 5));
    });

    test('converts an explicit offset to UTC and keeps the fraction', () {
      final parsed = parseUtcTimestamp('2026-11-02T10:58:48.986112+07:00');

      expect(parsed.hour, 3);
      expect(parsed.millisecond, 986);
    });

    test('still rejects impossible calendar values and too-long fractions', () {
      expect(
        () => parseUtcTimestamp('2026-02-30T03:20:05.986112Z'),
        throwsA(isA<UnsupportedDataException>()),
      );
      expect(
        () => parseUtcTimestamp('2026-10-30T03:20:05.9861123Z'),
        throwsA(isA<UnsupportedDataException>()),
      );
    });
  });
}
