import '../policy/day_log.dart';

/// Where the day log is kept between launches.
///
/// **A seam, and today only the in-memory side of it exists.** Persisting on a
/// phone means writing to the app's documents directory, and Flutter exposes no
/// path to it without a plugin — `path_provider` or `shared_preferences`. Adding
/// either is a **DEP-1 decision**: every dependency is checked for whether it
/// phones home *before* it is proposed — data minimisation under the LFPDPPP
/// applies to adults too (ADR 0004's amendment §2) — and
/// `dependency_allowlist_test` fails loudly on any addition precisely so a
/// human takes that call rather than a session.
///
/// So this change ships the model, the seam and the wiring, all tested, and the
/// persistent implementation is one file behind a decision that is not a
/// session's to make. Nothing else moves when it lands.
abstract interface class DayLogStore {
  /// The log as it stands. Returns an empty log rather than throwing when
  /// there is nothing to read or what is there cannot be read.
  Future<DayLog> read();

  /// Records the day [moment] falls on.
  Future<DayLog> record(DateTime moment);
}

/// A store that forgets when the app closes.
///
/// Not a stub: it is the correct implementation of "remember within a session",
/// it is what the app uses today, and it keeps the streak honest — a figure that
/// resets on relaunch is at least *true*, which a hard-coded one would not be.
class InMemoryDayLogStore implements DayLogStore {
  InMemoryDayLogStore([DayLog initial = DayLog.empty]) : _log = initial;

  DayLog _log;

  @override
  Future<DayLog> read() async => _log;

  @override
  Future<DayLog> record(DateTime moment) async {
    _log = _log.recording(moment);
    return _log;
  }
}
