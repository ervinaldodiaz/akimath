/// The days the player has practised.
///
/// Pure and immutable: recording a day returns a new log. It reads no clock —
/// the caller says which day — and it holds **days, never moments**.
///
/// **That is a privacy decision, not a rounding convenience.** What time of day
/// a player plays is not needed to count a streak, so it is not stored. The
/// encoded form carries dates and nothing else, and a test asserts it contains
/// no `:`.
library;

class DayLog {
  const DayLog._(this._days);

  static const DayLog empty = DayLog._(<DateTime>[]);

  /// How many days are kept.
  ///
  /// A log kept forever is a year of a player's activity sitting on the device
  /// for a figure that only needs the current run — retention is a privacy
  /// question as much as a storage one. Ninety days is comfortably longer than
  /// any streak worth showing and short enough to be a bounded file.
  ///
  /// **Stated limit:** a streak cannot be reported longer than this.
  static const int retainedDays = 90;

  final List<DateTime> _days;

  /// The recorded days, oldest first.
  List<DateTime> get days => List<DateTime>.unmodifiable(_days);

  /// This log plus the day [moment] falls on.
  DayLog recording(DateTime moment) {
    final DateTime day = _startOfDay(moment);
    final Set<DateTime> merged = <DateTime>{..._days, day};

    final List<DateTime> ordered = merged.toList()..sort();
    // Keep the most recent, drop the oldest.
    final List<DateTime> kept = ordered.length <= retainedDays
        ? ordered
        : ordered.sublist(ordered.length - retainedDays);

    return DayLog._(kept);
  }

  /// One ISO date per day, comma separated.
  ///
  /// A hand-rolled format rather than JSON: it is a list of dates, and reaching
  /// for a parser would be the heaviest possible way to store one.
  String encode() => _days.map(_formatDay).join(',');

  /// Reads what [encode] wrote.
  ///
  /// **Never throws.** Storage is the one input nobody reviews, and a corrupt
  /// file must cost the streak rather than the launch — so an unreadable entry
  /// is skipped and an unreadable file is an empty log.
  static DayLog decode(String encoded) {
    final List<DateTime> days = <DateTime>[];
    for (final String field in encoded.split(',')) {
      final String trimmed = field.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final DateTime? parsed = DateTime.tryParse(trimmed);
      // `tryParse` is lenient about out-of-range components: `2026-13-45`
      // parses, rolling over into February 2027. Requiring the parse to
      // round-trip is what rejects a date that never existed, rather than
      // silently recording a day the player was not there.
      if (parsed != null && _formatDay(parsed) == trimmed) {
        days.add(_startOfDay(parsed));
      }
    }
    return DayLog._((days.toSet().toList())..sort());
  }

  static String _formatDay(DateTime day) =>
      '${day.year.toString().padLeft(4, '0')}-'
      '${day.month.toString().padLeft(2, '0')}-'
      '${day.day.toString().padLeft(2, '0')}';

  static DateTime _startOfDay(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);
}
