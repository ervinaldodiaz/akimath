/// How many consecutive days the player has practised.
///
/// **A local calendar fact, not a server one** (D17). The streak survives with
/// no network because it is computed on the device from the days it recorded,
/// and it is one of only two figures a verdict screen shows in F2 — the other
/// being elapsed time. The rating is the server's exclusive authority and is
/// hidden entirely until F3, so nothing on an F2 verdict screen is a number
/// sync can later contradict.
///
/// Pure: two arguments in, an integer out. `today` is a parameter and never a
/// clock read, which is what lets the whole policy be tested by handing it two
/// dates.
library;

/// The number of consecutive calendar days ending at [today] or yesterday.
///
/// **Yesterday counts, and that is deliberate.** A streak that reset at
/// midnight would tell a child who opens the app before playing that they had
/// lost it. The day is not over until it is over.
///
/// **A wrong answer never decrements it** (Q7, decided 2026-08-15). This policy
/// is not given verdicts at all — it counts days practised, not days won, so it
/// has no way to punish one.
///
/// Attempts may arrive in any order and may repeat within a day; both are
/// normalised. An attempt dated after [today] is ignored rather than trusted: a
/// device clock that jumped forward and back should not mint days.
int streakLength({
  required List<DateTime> attemptDays,
  required DateTime today,
}) {
  final DateTime end = _startOfDay(today);

  final Set<DateTime> played = <DateTime>{
    for (final DateTime attempt in attemptDays)
      if (!_startOfDay(attempt).isAfter(end)) _startOfDay(attempt),
  };
  if (played.isEmpty) {
    return 0;
  }

  DateTime cursor = played.contains(end) ? end : _previousDay(end);
  if (!played.contains(cursor)) {
    return 0;
  }

  int length = 0;
  while (played.contains(cursor)) {
    length++;
    cursor = _previousDay(cursor);
  }
  return length;
}

/// How many days the strip shows. A week, and not the streak's length.
///
/// A strip that grew with the streak would reflow the home every morning and
/// could never show a gap — and the gap is the fact a total cannot carry. The
/// number beside it carries anything longer.
const int weekWindow = 7;

/// Which of the last [weekWindow] days were played, oldest first, ending today.
///
/// **Pure**, and deliberately in this file rather than beside the widget that
/// draws it: it needs the same calendar arithmetic [streakLength] does, and a
/// second copy of that arithmetic is exactly how the Tijuana defect below gets
/// reintroduced somewhere new.
///
/// The same two normalisations apply, for the same reasons: a repeated day
/// counts once, and a day after [today] is ignored rather than trusted.
///
/// **Built backwards from today and then reversed**, rather than walked
/// forwards from the oldest day. Walking forwards would need a *next day* that
/// [_previousDay]'s component arithmetic does not provide, and adding one is
/// how two directions drift apart across a daylight-saving transition — the
/// defect [_previousDay] exists to describe, reintroduced from the other end.
List<bool> weekMarks({
  required List<DateTime> attemptDays,
  required DateTime today,
}) {
  final DateTime end = _startOfDay(today);

  final Set<DateTime> played = <DateTime>{
    for (final DateTime attempt in attemptDays)
      if (!_startOfDay(attempt).isAfter(end)) _startOfDay(attempt),
  };

  final List<bool> marks = <bool>[];
  DateTime cursor = end;
  for (int i = 0; i < weekWindow; i++) {
    marks.add(played.contains(cursor));
    cursor = _previousDay(cursor);
  }
  return marks.reversed.toList(growable: false);
}

/// The calendar day before [day], as local midnight.
///
/// **Component arithmetic, never `subtract(Duration(days: 1))`.** A `Duration`
/// is absolute elapsed time and a local calendar day is 23, 24 or 25 hours
/// long, so subtracting 24 hours from midnight lands at 23:00 or 01:00 across a
/// daylight-saving transition — and the days in [streakLength] are a set of
/// midnights, so the lookup simply misses.
///
/// That was not hypothetical. In `America/Tijuana` — Tijuana, not a travelling
/// device — a child with a 30-day run opening the app on the morning of
/// 9 March 2026 saw a streak of **0** on the home, then **29** on the verdict
/// screen after answering: two screens, one morning, neither number right. It
/// also reached `America/Ciudad_Juarez`, `America/Havana`, `America/Santiago`
/// and every US and European zone.
///
/// `DateTime(y, m, d - 1)` normalises day zero into the previous month and
/// always yields that calendar day's local midnight, whatever the offset does.
DateTime _previousDay(DateTime day) =>
    DateTime(day.year, day.month, day.day - 1);

/// Midnight local, so a time of day inside a counted day is ignored.
///
/// Q7 settles the boundary as the **device's local calendar day**. Constructing
/// a `DateTime` from year, month and day is exactly that, and it keeps this
/// module free of a timezone database — the `America/Mexico_City` fallback Q7
/// names is a question for a device that reports no zone, which is the
/// adapter's problem and not this function's.
DateTime _startOfDay(DateTime moment) =>
    DateTime(moment.year, moment.month, moment.day);
