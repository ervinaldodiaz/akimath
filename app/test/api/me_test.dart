/// `Me` off the wire, and the instant inside it.
///
/// **A band nobody declared is refused rather than defaulted.** Either default
/// would state a band the device never sent, and which one is wrong is not a
/// decision a parser gets to make — `AgeBand` carries the same rule from the
/// production side.
library;

import 'package:akimath_app/api/me.dart';
import 'package:flutter_test/flutter_test.dart';

const String _playerId = '018f4e3c-0000-7000-8000-0000000000b1';
const String _createdAt = '2026-08-19T09:15:00.000Z';

Map<String, Object?> _json({
  String playerId = _playerId,
  String ageBand = 'under_13',
  String createdAt = _createdAt,
}) => <String, Object?>{
  'playerId': playerId,
  'ageBand': ageBand,
  'createdAt': createdAt,
};

/// Instants `DateTime.parse` reads happily and the frozen pattern refuses,
/// each paired with what is wrong with it.
///
/// Every one of them round-trips to different bytes than it arrived as, which
/// is how a client and a server stop agreeing about an instant.
const List<(String, String)> _parseableButRefused = <(String, String)>[
  ('2026-01-02T03:04:05.678+00:00', 'an offset, not Z'),
  ('2026-01-02T03:04:05.678', 'no zone at all'),
  ('2026-01-02 03:04:05.678Z', 'a space instead of T'),
  ('2026-02-30T00:00:00.000Z', 'a day February never has'),
  ('2025-02-29T00:00:00.000Z', 'not a leap year'),
];

void main() {
  group('a profile off the wire', () {
    test('reads the three fields the frozen schema requires', () {
      final Me me = Me.fromJson(_json());

      expect(me.playerId, _playerId);
      expect(me.ageBand, AgeBand.under13);
      expect(me.createdAt, DateTime.utc(2026, 8, 19, 9, 15));
      expect(me.createdAt.isUtc, isTrue);
    });

    test('each band the contract names has a Dart value', () {
      expect(Me.fromJson(_json(ageBand: 'under_13')).ageBand, AgeBand.under13);
      expect(Me.fromJson(_json(ageBand: '13_17')).ageBand, AgeBand.thirteenToSeventeen);
      expect(Me.fromJson(_json(ageBand: 'adult')).ageBand, AgeBand.adult);
    });

    test('a band nobody decided is refused, not defaulted', () {
      expect(() => Me.fromJson(_json(ageBand: '18_plus')), throwsFormatException);
    });

    test('a missing field is refused', () {
      for (final String absent in <String>['playerId', 'ageBand', 'createdAt']) {
        final Map<String, Object?> body = _json()..remove(absent);
        expect(() => Me.fromJson(body), throwsFormatException, reason: absent);
      }
    });

    test('a field of the wrong type is refused rather than coerced', () {
      expect(
        () => Me.fromJson(<String, Object?>{..._json(), 'playerId': 42}),
        throwsFormatException,
      );
    });
  });

  group('createdAt is held to the contract, not to DateTime.parse', () {
    test('accepts what the pattern accepts, seconds and fraction both optional',
        () {
      expect(Me.fromJson(_json(createdAt: '2026-01-02T03:04:05.678Z')).createdAt,
          DateTime.utc(2026, 1, 2, 3, 4, 5, 678));
      expect(Me.fromJson(_json(createdAt: '2026-01-02T03:04Z')).createdAt,
          DateTime.utc(2026, 1, 2, 3, 4));
    });

    test('refuses what the pattern refuses, however parseable it is', () {
      for (final (String off, String why) in _parseableButRefused) {
        expect(() => Me.fromJson(_json(createdAt: off)), throwsFormatException,
            reason: '$off — $why');
      }
    });

    test('a leap day in a leap year is accepted, so the refusals are not blanket',
        () {
      expect(Me.fromJson(_json(createdAt: '2028-02-29T00:00:00.000Z')).createdAt,
          DateTime.utc(2028, 2, 29));
    });
  });

  group('a profile survives the round trip', () {
    test('back to the bytes it arrived as', () {
      final Map<String, Object?> body = _json();
      expect(Me.fromJson(body).toJson(), body);
    });

    test('a time with no seconds normalises, so the round trip is not universal',
        () {
      expect(Me.fromJson(_json(createdAt: '2026-01-02T03:04Z')).toJson()['createdAt'],
          '2026-01-02T03:04:00.000Z');
    });
  });
}
