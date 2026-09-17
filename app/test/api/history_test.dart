import 'package:akimath_app/api/history.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _entry({
  String kind = 'series',
  String title = 'Restas',
  String at = '2026-08-19T09:15:00.000Z',
  String score = '4/5',
  Object? ratingDelta,
  bool withDelta = true,
}) => <String, Object?>{
  'kind': kind,
  'title': title,
  'at': at,
  'score': score,
  if (withDelta) 'ratingDelta': ratingDelta,
};

void main() {
  group('an entry off the wire', () {
    test('reads the five fields the frozen schema requires', () {
      final HistoryEntry entry = HistoryEntry.fromJson(_entry());

      expect(entry.kind, HistoryKind.series);
      expect(entry.title, 'Restas');
      expect(entry.at, DateTime.utc(2026, 8, 19, 9, 15));
      expect(entry.at.isUtc, isTrue);
      expect(entry.score, '4/5');
      expect(entry.ratingDelta, isNull);
    });

    test('both kinds the contract names have a Dart value', () {
      expect(HistoryEntry.fromJson(_entry(kind: 'series')).kind, HistoryKind.series);
      expect(HistoryEntry.fromJson(_entry(kind: 'puzzle')).kind, HistoryKind.puzzle);
    });

    test('a kind nobody decided is refused, not defaulted', () {
      expect(() => HistoryEntry.fromJson(_entry(kind: 'quiz')), throwsFormatException);
    });

    test('a rating it does have is carried', () {
      expect(HistoryEntry.fromJson(_entry(ratingDelta: -12)).ratingDelta, -12);
      expect(HistoryEntry.fromJson(_entry(ratingDelta: 0)).ratingDelta, 0);
    });

    test('and an absent one is refused, unlike a null one', () {
      expect(() => HistoryEntry.fromJson(_entry(withDelta: false)), throwsFormatException);
      expect(HistoryEntry.fromJson(_entry()).ratingDelta, isNull);
    });

    test('a field of the wrong type is refused rather than coerced', () {
      expect(() => HistoryEntry.fromJson(_entry(ratingDelta: '3')), throwsFormatException);
      expect(
        () => HistoryEntry.fromJson(<String, Object?>{..._entry(), 'score': 4}),
        throwsFormatException,
      );
      expect(
        () => HistoryEntry.fromJson(<String, Object?>{..._entry(), 'title': null}),
        throwsFormatException,
      );
    });

    test('and so is an instant the contract would refuse, by the same reader '
        'Me.createdAt uses', () {
      for (final String off in <String>[
        '2026-01-02T03:04:05.678+00:00',
        '2026-02-30T00:00:00.000Z',
        '2025-02-29T00:00:00.000Z',
      ]) {
        expect(() => HistoryEntry.fromJson(_entry(at: off)), throwsFormatException, reason: off);
      }
      expect(HistoryEntry.fromJson(_entry(at: '2028-02-29T00:00:00.000Z')).at,
          DateTime.utc(2028, 2, 29));
    });

    test('it survives the round trip', () {
      final Map<String, Object?> body = _entry(ratingDelta: 7);
      expect(HistoryEntry.fromJson(body).toJson(), body);
    });
  });

  group('the history as a whole', () {
    test('reads a list of them, in the order it arrived', () {
      final History history = History.fromJson(<String, Object?>{
        'entries': <Object?>[
          _entry(at: '2026-08-19T09:15:00.000Z', title: 'segunda'),
          _entry(at: '2026-08-18T09:15:00.000Z', title: 'primera'),
        ],
      });

      expect(history.entries.map((HistoryEntry e) => e.title).toList(),
          <String>['segunda', 'primera']);
      expect(history.isEmpty, isFalse);
    });

    test('an empty history is a history', () {
      final History history = History.fromJson(<String, Object?>{'entries': <Object?>[]});

      expect(history.entries, isEmpty);
      expect(history.isEmpty, isTrue);
    });

    test('a body that is not one is refused', () {
      expect(() => History.fromJson(<String, Object?>{}), throwsFormatException);
      expect(
        () => History.fromJson(<String, Object?>{'entries': <Object?>['nope']}),
        throwsFormatException,
      );
    });

    test('two histories with the same entries are the same history', () {
      final Map<String, Object?> body = <String, Object?>{
        'entries': <Object?>[_entry()],
      };
      expect(History.fromJson(body), History.fromJson(body));
      expect(History.fromJson(body).hashCode, History.fromJson(body).hashCode);
      expect(History.fromJson(body), isNot(History.fromJson(<String, Object?>{
        'entries': <Object?>[_entry(title: 'otra')],
      })));
    });
  });
}
