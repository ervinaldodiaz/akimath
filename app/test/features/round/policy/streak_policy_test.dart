/// The streak policy, and the daylight-saving defect it was fixed for.
///
/// **The DST cases pass vacuously in a zone without one**, which includes
/// `America/Mexico_City` (abolished 2022) and the UTC that CI defaults to.
/// `.github/workflows/ci.yml` therefore runs this file a second time under
/// `TZ=America/Tijuana`; without that run, the bug they cover is invisible to
/// the suite. Tijuana and Ciudad Juárez are Mexican DST zones, so this is the
/// target audience and not a travelling device.
///
/// What it cost before the fix: a player with a 30-day run, opening the app on
/// the morning of 9 March 2026, saw **0** on the home and then **29** on the
/// verdict screen. Two screens, one morning, neither number right.
library;

import 'package:akimath_app/features/round/policy/streak_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Local calendar days, as the policy takes them.
DateTime day(int y, int m, int d) => DateTime(y, m, d);

void main() {
  _weekMarksTests();

  group('a streak counts consecutive local calendar days', () {
    test('playing today after yesterday continues the streak', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[day(2026, 8, 14), day(2026, 8, 15)],
          today: day(2026, 8, 15),
        ),
        2,
      );
    });

    test('a gap ends the streak at the run that reaches today, so the 12th and '
        '13th being missed leaves the 14th and 15th', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[
            day(2026, 8, 10),
            day(2026, 8, 11),
            day(2026, 8, 14),
            day(2026, 8, 15),
          ],
          today: day(2026, 8, 15),
        ),
        2,
      );
    });

    test('having played yesterday but not today keeps the streak alive, '
        'because the day is not over until it is over', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[day(2026, 8, 13), day(2026, 8, 14)],
          today: day(2026, 8, 15),
        ),
        2,
      );
    });

    test('a gap of two days is a broken streak', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[day(2026, 8, 12), day(2026, 8, 13)],
          today: day(2026, 8, 15),
        ),
        0,
      );
    });

    test('no attempts is a streak of zero', () {
      expect(
        streakLength(attemptDays: <DateTime>[], today: day(2026, 8, 15)),
        0,
      );
    });

    test('playing twice in one day counts that day once', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[
            day(2026, 8, 15),
            day(2026, 8, 15),
            day(2026, 8, 14),
          ],
          today: day(2026, 8, 15),
        ),
        2,
      );
    });

    test('the order attempts arrive in does not matter', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[
            day(2026, 8, 15),
            day(2026, 8, 13),
            day(2026, 8, 14),
          ],
          today: day(2026, 8, 15),
        ),
        3,
      );
    });

    test('a time of day within a counted day is ignored', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[
            DateTime(2026, 8, 14, 23, 59),
            DateTime(2026, 8, 15, 0, 1),
          ],
          today: DateTime(2026, 8, 15, 12),
        ),
        2,
      );
    });
  });

  group('what a streak never does', () {
    test('a wrong answer does not decrement it, because the policy is never '
        'given a verdict at all (Q7)', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[day(2026, 8, 14), day(2026, 8, 15)],
          today: day(2026, 8, 15),
        ),
        2,
      );
    });

    test('it reads no clock of its own, so two different todays over the same '
        'attempts disagree — which DateTime.now() could not do', () {
      final List<DateTime> attempts = <DateTime>[
        day(2026, 8, 14),
        day(2026, 8, 15),
      ];
      expect(
        streakLength(attemptDays: attempts, today: day(2026, 8, 15)),
        isNot(streakLength(attemptDays: attempts, today: day(2026, 9, 30))),
      );
    });

    test('a future attempt does not extend the streak, so a clock that jumped '
        'forward and back mints no days', () {
      expect(
        streakLength(
          attemptDays: <DateTime>[day(2026, 8, 15), day(2026, 12, 25)],
          today: day(2026, 8, 15),
        ),
        1,
      );
    });
  });

  group('a daylight-saving transition does not break a streak', () {
    /// An unbroken run of [count] local calendar days ending at [last].
    ///
    /// Component arithmetic, like the policy's own: a `Duration` step would
    /// build the very run the transition breaks.
    List<DateTime> consecutiveDaysEnding(DateTime last, int count) => <DateTime>[
          for (int i = 0; i < count; i++)
            DateTime(last.year, last.month, last.day - i),
        ];

    test('the grace path survives spring forward, for a player who played '
        'through the 8th and opens the app on the 9th before playing', () {
      expect(
        streakLength(
          attemptDays: consecutiveDaysEnding(day(2026, 3, 8), 30),
          today: DateTime(2026, 3, 9, 9),
        ),
        30,
      );
    });

    test('the counting loop survives spring forward, for a player who played '
        'through the 9th including today', () {
      expect(
        streakLength(
          attemptDays: consecutiveDaysEnding(day(2026, 3, 9), 30),
          today: DateTime(2026, 3, 9, 9),
        ),
        30,
      );
    });

    test('a run spanning autumn back is counted whole', () {
      expect(
        streakLength(
          attemptDays: consecutiveDaysEnding(day(2026, 11, 3), 10),
          today: DateTime(2026, 11, 3, 9),
        ),
        10,
      );
    });

    test('every day of a DST year counts a five-day run as five — a sweep, '
        'because a single date proves one of the two transitions a year', () {
      for (int dayOfYear = 5; dayOfYear < 365; dayOfYear++) {
        final DateTime today = DateTime(2026, 1, dayOfYear);
        expect(
          streakLength(
            attemptDays: consecutiveDaysEnding(today, 5),
            today: today,
          ),
          5,
          reason: 'played-today path wrong at $today',
        );
        expect(
          streakLength(
            attemptDays: consecutiveDaysEnding(
              DateTime(today.year, today.month, today.day - 1),
              5,
            ),
            today: today,
          ),
          5,
          reason: 'grace path wrong at $today',
        );
      }
    });
  });
}

void _weekMarksTests() {
  group('the week strip marks which of the last seven days were played', () {
    DateTime day(int d) => DateTime(2026, 3, d);

    test('it is always seven marks, ending on today', () {
      expect(weekMarks(attemptDays: <DateTime>[], today: day(15)), hasLength(7));
    });

    test('nothing played is seven unplayed marks, so the band does not vanish '
        'and move the layout under a player on their first morning', () {
      expect(weekMarks(attemptDays: <DateTime>[], today: day(15)), everyElement(isFalse));
    });

    test('every day played is seven played marks', () {
      expect(
        weekMarks(attemptDays: <DateTime>[for (int d = 9; d <= 15; d++) day(d)], today: day(15)),
        everyElement(isTrue),
      );
    });

    test('a gap in the middle is visible, which is the one fact a total cannot '
        'carry and the whole reason the strip exists', () {
      expect(
        weekMarks(attemptDays: <DateTime>[day(13), day(15)], today: day(15)),
        <bool>[false, false, false, false, true, false, true],
      );
    });

    test('today is the last mark and the oldest day is the first', () {
      expect(weekMarks(attemptDays: <DateTime>[day(9)], today: day(15)).first, isTrue);
      expect(weekMarks(attemptDays: <DateTime>[day(15)], today: day(15)).last, isTrue);
    });

    test('a streak longer than a week still draws seven', () {
      expect(
        weekMarks(attemptDays: <DateTime>[for (int d = 1; d <= 15; d++) day(d)], today: day(15)),
        hasLength(7),
      );
    });

    test('a day older than the window does not leak in', () {
      expect(weekMarks(attemptDays: <DateTime>[day(8)], today: day(15)), everyElement(isFalse));
    });

    test('a day in the future is ignored and not trusted, the same rule '
        'streakLength follows', () {
      expect(
        weekMarks(attemptDays: <DateTime>[day(16), day(20)], today: day(15)),
        everyElement(isFalse),
      );
    });

    test('a time of day inside a counted day is ignored', () {
      expect(
        weekMarks(
          attemptDays: <DateTime>[DateTime(2026, 3, 15, 23, 59)],
          today: DateTime(2026, 3, 15, 0, 1),
        ).last,
        isTrue,
      );
    });

    test('the same day twice counts once and shifts nothing', () {
      expect(
        weekMarks(attemptDays: <DateTime>[day(15), day(15)], today: day(15)),
        <bool>[false, false, false, false, false, false, true],
      );
    });

    test('it crosses a daylight-saving boundary without losing a day, measured '
        'from the 9th and not the 8th — Tijuana springs forward at 02:00 on '
        'the 8th, so a walk starting there never crosses the transition', () {
      expect(
        weekMarks(
          attemptDays: <DateTime>[for (int d = 3; d <= 9; d++) DateTime(2026, 3, d)],
          today: DateTime(2026, 3, 9),
        ),
        everyElement(isTrue),
      );
    });

    test('it crosses a month boundary', () {
      expect(
        weekMarks(attemptDays: <DateTime>[DateTime(2026, 2, 28)], today: DateTime(2026, 3, 2)),
        <bool>[false, false, false, false, true, false, false],
      );
    });
  });
}
