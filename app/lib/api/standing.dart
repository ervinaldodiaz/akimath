import 'package:meta/meta.dart';

import 'instant.dart';

/// What `GET /me/standing` answers.
///
/// **A PURE-2 model, hand-written, holding no decisions** — ADR 0001's shape
/// for everything in `api/`. It reads the frozen `Standing` and nothing more:
/// no defaults, no coercion, and no arithmetic over the ratings, because what a
/// rating *means* is the server's and a client deriving anything from one would
/// be a second opinion about it.
///
/// **The shape carries rating and only rating.** `Standing` is a `playerId` and
/// a list of `{skillId, rating, deviation, updatedAt}`. There is no accuracy in
/// it and no time on task, so no screen can read either from here however much
/// `attempts` knows about both — that is a contract question, not something
/// this file can answer by adding a field.

T _read<T>(Map<String, Object?> json, String field) {
  final Object? value = json[field];
  if (value is! T) {
    throw FormatException('$field is ${value.runtimeType}, not $T', json.toString());
  }
  return value;
}

/// A `number` in the frozen schema, which JSON hands over as either Dart type.
///
/// **`num`, then widened.** `rating` and `deviation` are `type: number` and
/// `real` in Postgres, so a rating of exactly 1200 is serialised `1200` and
/// decodes as an `int` — a reader asking for a `double` would throw on it, and
/// only for the players whose rating happens to be whole. Asking for `num`
/// still refuses a string, which is the check that was actually wanted.
double _readNumber(Map<String, Object?> json, String field) =>
    _read<num>(json, field).toDouble();

/// One skill's rating, as the server holds it.
///
/// **`rating` is not nullable and there is nothing to default it to.** Unlike
/// `HistoryEntry.ratingDelta`, the frozen schema marks every field here
/// required and none of them nullable — a skill with no rating is a skill with
/// no entry, so absence is expressed by the list, never by a zero inside it.
@immutable
class SkillStanding {
  const SkillStanding({
    required this.skillId,
    required this.rating,
    required this.deviation,
    required this.updatedAt,
  });

  factory SkillStanding.fromJson(Map<String, Object?> json) => SkillStanding(
    skillId: _read<int>(json, 'skillId'),
    rating: _readNumber(json, 'rating'),
    deviation: _readNumber(json, 'deviation'),
    updatedAt: readInstant(_read<String>(json, 'updatedAt')),
  );

  /// Which skill. A `smallint` server-side, and a name in no table — naming one
  /// is `@akimath/core`'s `skillName()`, on the server, and never this client's.
  final int skillId;

  /// How the server rates the player at it.
  ///
  /// **Unbounded by the contract, so a figure that looks wrong is still read.**
  /// Refusing one the server is entitled to send would blank a screen over a
  /// number.
  final double rating;

  /// How sure the server is of that rating. Unbounded by the contract.
  final double deviation;

  final DateTime updatedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'skillId': skillId,
    'rating': rating,
    'deviation': deviation,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  bool operator ==(Object other) =>
      other is SkillStanding &&
      other.skillId == skillId &&
      other.rating == rating &&
      other.deviation == deviation &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(skillId, rating, deviation, updatedAt);

  @override
  String toString() => 'SkillStanding($skillId, $rating ± $deviation)';
}

/// Every skill the server has rated this player at.
///
/// **An empty list is the ordinary answer and not a failure.** Rating is F4 and
/// nothing writes a rating yet, so today it is the answer for everybody. A
/// caller that read it as an error, or drew a `0` from it, would be inventing
/// exactly the figure the empty list exists to withhold — which is the same
/// reading `HistoryEntry.ratingDelta` takes of its null.
///
/// **The order is not re-sorted here.** The server orders by skill so that two
/// calls agree; sorting again in the client is a second opinion that diverges
/// the day the server's changes.
@immutable
class Standing {
  const Standing({required this.playerId, required this.skills});

  factory Standing.fromJson(Map<String, Object?> json) {
    final Object? skills = json['skills'];
    if (skills is! List<Object?>) {
      throw FormatException('skills is ${skills.runtimeType}, not a list', json.toString());
    }
    return Standing(
      playerId: _read<String>(json, 'playerId'),
      skills: skills
          .map((Object? skill) => skill is Map<String, Object?>
              ? SkillStanding.fromJson(skill)
              : throw FormatException('a skill is not an object', json.toString()))
          .toList(growable: false),
    );
  }

  /// Carried verbatim, not validated — the same asymmetry `Me` records: an
  /// off-contract id is the server's bug, and refusing it here would blank a
  /// screen over a cosmetic defect.
  final String playerId;

  final List<SkillStanding> skills;

  /// Whether the server has rated this player at anything at all.
  ///
  /// Named rather than left as `skills.isEmpty` at each call site, because the
  /// two readings of an empty list — "no rating yet" and "something went
  /// wrong" — are exactly what a caller must not confuse, and a name can only
  /// mean the first.
  bool get isUnrated => skills.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
    'playerId': playerId,
    'skills': skills.map((SkillStanding skill) => skill.toJson()).toList(growable: false),
  };

  @override
  bool operator ==(Object other) =>
      other is Standing &&
      other.playerId == playerId &&
      other.skills.length == skills.length &&
      List<int>.generate(skills.length, (int i) => i)
          .every((int i) => other.skills[i] == skills[i]);

  @override
  int get hashCode => Object.hash(playerId, Object.hashAll(skills));

  /// **A count, never the ratings.** The same reading as
  /// `LinkedSession.toString`: `toString` reaches logs and crash reports, so it
  /// says what a developer needs and nothing more.
  @override
  String toString() => 'Standing($playerId, ${skills.length} skill(s))';
}
