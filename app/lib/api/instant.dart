/// The instants the frozen contract's `date-time` admits, and no others.
///
/// **One reader for every model in `api/`.** `Me.createdAt` and
/// `HistoryEntry.at` are pinned to the same pattern in the same document, and
/// two re-derivations of one rule is the drift this repository names R2 —
/// `test/api/contract_parity_test.dart` runs this against the artifact's own
/// regular expression on a list of probes.
///
/// **Narrower than `DateTime.parse` on purpose.** The contract pins `date-time`
/// to a literal `Z` with optional seconds and fraction; `DateTime.parse` also
/// takes `+00:00`, a bare local time, and a space in place of the `T`. Each of
/// those round-trips to different bytes than it arrived as, which is how a
/// client and a server quietly stop agreeing about an instant.
///
/// The calendar arithmetic — 30-day months, and 29 February only in a leap
/// year — is the contract's too. Reproducing the frozen regular expression here
/// would be a second copy of it; re-deriving the same *rules* and then having
/// `test/api/contract_parity_test.dart` check both against the artifact is the
/// arrangement this repository uses everywhere else.
final RegExp _instant = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2})(?:\.(\d+))?)?Z$',
);

bool _isLeapYear(int year) =>
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);

const List<int> _daysInMonth = <int>[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];

DateTime readInstant(String value) {
  final RegExpMatch? match = _instant.firstMatch(value);
  if (match == null) {
    throw FormatException('not the date-time the contract pins', value);
  }

  final int year = int.parse(match.group(1)!);
  final int month = int.parse(match.group(2)!);
  final int day = int.parse(match.group(3)!);
  if (month < 1 || month > 12) {
    throw FormatException('month out of range', value);
  }
  final int last =
      month == 2 && _isLeapYear(year) ? 29 : _daysInMonth[month - 1];
  if (day < 1 || day > last) {
    throw FormatException('day out of range for that month', value);
  }

  final int hour = int.parse(match.group(4)!);
  final int minute = int.parse(match.group(5)!);
  final int second = int.parse(match.group(6) ?? '0');
  if (hour > 23 || minute > 59 || second > 59) {
    throw FormatException('time out of range', value);
  }
  return DateTime.utc(
    year,
    month,
    day,
    hour,
    minute,
    second,
    _millisecondsOf(match.group(7)),
  );
}

/// A matched fraction-of-a-second as whole milliseconds.
///
/// **Milliseconds and no finer.** `DateTime` on the web has no microseconds and
/// the server emits three digits, so a longer fraction is truncated rather than
/// refused: the contract allows it, and losing it changes no instant this
/// product can measure.
int _millisecondsOf(String? fraction) =>
    int.parse((fraction ?? '').padRight(3, '0').substring(0, 3));
