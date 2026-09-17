import 'package:meta/meta.dart';

import 'instant.dart';

/// The band a player declared, as a closed union.
///
/// **An enum and not a string**, so a `switch` over it is exhaustive: a band
/// added server-side becomes a compile error here rather than falling through a
/// `default` nobody looked at. The band is what the device answered about its
/// own eligibility — never something to settle with a `?? adult`.
///
/// **Three members, one of which this build can produce.** ADR 0004 makes the
/// product adults-only and the age gate refuses everything below `adult`, so
/// nothing here mints another. The other two stay because the frozen contract
/// and the `players` `CHECK` still name them — they go dead by construction
/// rather than by being narrowed — and because rows and stored sessions
/// carrying `13_17` predate the decision and still have to be readable.
enum AgeBand {
  under13('under_13'),
  thirteenToSeventeen('13_17'),
  adult('adult');

  const AgeBand(this.wireName);

  /// Exactly the string the frozen `Me` schema's enum carries.
  final String wireName;

  static AgeBand fromWire(String value) => AgeBand.values.firstWhere(
    (AgeBand band) => band.wireName == value,
    orElse: () => throw FormatException('not a band this contract names', value),
  );
}

T _read<T>(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! T) {
    throw FormatException('$field is ${value.runtimeType}, not $T', json.toString());
  }
  return value;
}

/// The player behind the current session.
///
/// Immutable, with an explicit `fromJson` — ADR 0001's shape for every model in
/// `api/`. It holds no defaults: every field the frozen schema marks required
/// is required here, and a body missing one is a `FormatException` rather than
/// a `Me` with a hole in it.
@immutable
class Me {
  const Me({
    required this.playerId,
    required this.ageBand,
    required this.createdAt,
  });

  factory Me.fromJson(Map<String, Object?> json) => Me(
    playerId: _read<String>(json, 'playerId'),
    ageBand: AgeBand.fromWire(_read<String>(json, 'ageBand')),
    createdAt: readInstant(_read<String>(json, 'createdAt')),
  );

  final String playerId;
  final AgeBand ageBand;
  final DateTime createdAt;

  /// The body this profile came from, written back.
  ///
  /// **The client never sends a `Me`.** This exists so a test can prove nothing
  /// was lost on the way in, and for the day something caches one.
  Map<String, Object?> toJson() => <String, Object?>{
    'playerId': playerId,
    'ageBand': ageBand.wireName,
    'createdAt': createdAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is Me &&
      other.playerId == playerId &&
      other.ageBand == ageBand &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(playerId, ageBand, createdAt);

  @override
  String toString() => 'Me($playerId, ${ageBand.wireName}, $createdAt)';
}
