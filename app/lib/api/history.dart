import 'package:meta/meta.dart';

import 'instant.dart';

/// What kind of thing a history entry records.
///
/// **A closed union, so a `switch` over it is exhaustive.** The contract names
/// two and the server can only produce one today — a puzzle leaves no row in
/// any table, so nothing records that one was solved. `puzzle` is here because
/// the schema has it, and a client that could not read one would break on the
/// day the server can send it.
enum HistoryKind {
  series('series'),
  puzzle('puzzle');

  const HistoryKind(this.wireName);

  final String wireName;

  static HistoryKind fromWire(String value) => HistoryKind.values.firstWhere(
    (HistoryKind kind) => kind.wireName == value,
    orElse: () => throw FormatException('not a kind this contract names', value),
  );
}

T _read<T>(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! T) {
    throw FormatException('$field is ${value.runtimeType}, not $T', json.toString());
  }
  return value;
}

/// One session, as the server tells it.
///
/// **`ratingDelta` is nullable and stays nullable.** The schema marks it
/// required *and* nullable, which is not the same as optional: the field is
/// always there and its value is sometimes nothing. F4 landed, so it is usually
/// a number — and it is still nothing for a session that spanned two skills and
/// for one that only calibrated, the two kinds no single figure is a fact
/// about. A client that defaulted one of those to zero would draw "±0" where
/// the truth is "nothing measured you".
@immutable
class HistoryEntry {
  const HistoryEntry({
    required this.kind,
    required this.title,
    required this.at,
    required this.score,
    required this.ratingDelta,
  });

  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
    kind: HistoryKind.fromWire(_read<String>(json, 'kind')),
    title: _read<String>(json, 'title'),
    at: readInstant(_read<String>(json, 'at')),
    score: _read<String>(json, 'score'),
    ratingDelta: _readDelta(json),
  );

  static int? _readDelta(Map<String, Object?> json) {
    if (!json.containsKey('ratingDelta')) {
      throw FormatException('ratingDelta is absent', json.toString());
    }
    final Object? value = json['ratingDelta'];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw FormatException('ratingDelta is ${value.runtimeType}, not int?', json.toString());
    }
    return value;
  }

  final HistoryKind kind;
  final String title;
  final DateTime at;

  /// How the session read, as the server spelled it — `4/5`.
  ///
  /// **A string on the wire, and a string here.** How a score reads is a
  /// presentation decision the contract already made; splitting it into two
  /// numbers would be this client making it a second time.
  final String score;
  final int? ratingDelta;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.wireName,
    'title': title,
    'at': at.toUtc().toIso8601String(),
    'score': score,
    'ratingDelta': ratingDelta,
  };

  @override
  bool operator ==(Object other) =>
      other is HistoryEntry &&
      other.kind == kind &&
      other.title == title &&
      other.at == at &&
      other.score == score &&
      other.ratingDelta == ratingDelta;

  @override
  int get hashCode => Object.hash(kind, title, at, score, ratingDelta);

  @override
  String toString() => 'HistoryEntry(${kind.wireName}, $title, $score, $at)';
}

/// The whole answer: entries, newest first, as the server ordered them.
///
/// **The order is not re-sorted here.** "Newest first" is the server's
/// decision and it is the one thing a client sorting by `at` would silently
/// diverge from the day two sessions share an instant.
@immutable
class History {
  const History(this.entries);

  factory History.fromJson(Map<String, Object?> json) {
    final Object? entries = json['entries'];
    if (entries is! List<Object?>) {
      throw FormatException('entries is ${entries.runtimeType}, not a list', json.toString());
    }
    return History(
      entries
          .map((Object? entry) => entry is Map<String, Object?>
              ? HistoryEntry.fromJson(entry)
              : throw FormatException('an entry is not an object', json.toString()))
          .toList(growable: false),
    );
  }

  final List<HistoryEntry> entries;

  bool get isEmpty => entries.isEmpty;

  @override
  bool operator ==(Object other) =>
      other is History &&
      other.entries.length == entries.length &&
      List<int>.generate(entries.length, (int i) => i)
          .every((int i) => other.entries[i] == entries[i]);

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => 'History(${entries.length} entries)';
}
