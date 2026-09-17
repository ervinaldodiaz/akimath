import 'package:meta/meta.dart';

import 'instant.dart';
import 'time_on_task.dart';

/// Which item in which pack, as `attempts_one_source` spells it.
///
/// **A pack item has no id of its own.** `ARCHITECTURE.md` §4: identity is
/// `(packId, index)`, which is why the pack format gives its items no
/// identifier and why this pair exists at all.
@immutable
class PackRef {
  const PackRef({required this.packId, required this.index});

  final String packId;

  /// Position in `pack.items`. The boards are addressed by nothing: a puzzle
  /// leaves no row on the server, so nothing can grade one.
  final int index;

  Map<String, Object?> toJson() => <String, Object?>{'packId': packId, 'index': index};

  factory PackRef.fromJson(Map<String, Object?> json) {
    final Object? packId = json['packId'];
    final Object? index = json['index'];
    if (packId is! String || index is! int) {
      throw FormatException('not a packRef', json.toString());
    }
    return PackRef(packId: packId, index: index);
  }

  @override
  bool operator ==(Object other) =>
      other is PackRef && other.packId == packId && other.index == index;

  @override
  int get hashCode => Object.hash(packId, index);

  @override
  String toString() => 'PackRef($packId[$index])';
}

/// One answered item, on its way to sync.
///
/// **It carries no verdict, and there is nowhere to put one.** The frozen
/// schema has no field for it and the server grades by rederiving or by
/// digesting — which is what makes "the answer never travels" true by
/// construction rather than by this client's restraint.
///
/// **Exactly one source, and naming neither or both does not compile.**
/// [AttemptSubmission.forIssuedItem] for something the server issued,
/// [AttemptSubmission.forPackItem] for something from a pack; the generative
/// constructor is private, and each door sets the other field itself. Neither
/// and both are a 400, and a 400 is not merely an error a player waits for:
/// `journalAfter` reads a malformed batch as one there is no point resending,
/// so up to two hundred answers go with it.
///
/// **This was an `assert` until 2026-08-29, which is the same guarantee in a
/// mechanism `flutter build --release` deletes** — every test saw a refusal no
/// shipping binary made. Unreachable then, because both call sites name a
/// pack; the first caller of the issued half inherits the hole, and that is
/// the one `GET /items/next` needs.
///
/// **[elapsed] is brought inside the wire's bound by the constructor, and was
/// an assert until 2026-09-02.** No constructor can make an out-of-range
/// `Duration` unrepresentable, so the invariant cannot be a constructor
/// *shape* — but it can be a constructor *effect*, and that is a guarantee
/// `flutter build --release` keeps. The assert only ever caught the negative
/// half, and only in debug: what shipped was an item left open for more than an
/// hour — a phone in a pocket — sending an `elapsedMs` the server refuses, and
/// a refused batch is a *deleted* batch. `reportableTimeOnTask` in
/// `time_on_task.dart` holds the bound and says why the ceiling is what
/// travels.
@immutable
class AttemptSubmission {
  AttemptSubmission._({
    this.itemId,
    this.packRef,
    required this.sessionId,
    required this.answer,
    required this.at,
    required Duration elapsed,
  }) : elapsed = reportableTimeOnTask(elapsed);

  /// An answer to an item from a pack, addressed by `(packId, index)`.
  AttemptSubmission.forPackItem({
    required PackRef ref,
    required String sessionId,
    required String answer,
    required DateTime at,
    required Duration elapsed,
  }) : this._(
          packRef: ref,
          sessionId: sessionId,
          answer: answer,
          at: at,
          elapsed: elapsed,
        );

  /// An answer to an item the server issued one at a time, addressed by its
  /// own id.
  AttemptSubmission.forIssuedItem({
    required String itemId,
    required String sessionId,
    required String answer,
    required DateTime at,
    required Duration elapsed,
  }) : this._(
          itemId: itemId,
          sessionId: sessionId,
          answer: answer,
          at: at,
          elapsed: elapsed,
        );

  /// An item the server issued. Null when this came from a pack.
  final String? itemId;

  /// An item from a pack. Null when the server issued it.
  final PackRef? packRef;

  /// The rating period. One per series, minted on the device.
  final String sessionId;

  /// Exactly as it was typed. Not canonicalised here — folding is the
  /// contract's job and it is done identically on both sides, so a client that
  /// folded first would be a third implementation of the rule.
  final String answer;

  /// When the item was answered. **UTC on the wire, whatever the device says.**
  /// The contract pins `date-time` to a literal `Z`, and a local instant would
  /// round-trip to different bytes than it arrived as.
  final DateTime at;

  /// Time on task, which is not the same as how long the request took. The
  /// server cannot derive it: a pack item has no `issued_at` of its own.
  ///
  /// Inside `0…maxReportableTimeOnTask` whatever was handed in, because the
  /// constructor put it there.
  final Duration elapsed;

  Map<String, Object?> toJson() => <String, Object?>{
    if (itemId != null) 'itemId': itemId,
    if (packRef != null) 'packRef': packRef!.toJson(),
    'sessionId': sessionId,
    'answer': answer,
    'clientTs': at.toUtc().toIso8601String(),
    'elapsedMs': elapsed.inMilliseconds,
  };
}

/// What the server said about one attempt.
///
/// Named `AttemptVerdict` because `Verdict` is already the *drawn* one —
/// outline and glyph, carrying no colour. This is the wire's, and it echoes
/// whichever source the submission named so a client can match them up rather
/// than trust the order.
@immutable
class AttemptVerdict {
  const AttemptVerdict({
    this.itemId,
    this.packRef,
    required this.ok,
    required this.payload,
  });

  factory AttemptVerdict.fromJson(Map<String, Object?> json) {
    final Object? ok = json['ok'];
    final Object? payload = json['payload'];
    if (ok is! bool || payload is! Map<String, Object?>) {
      throw FormatException('not a verdict', json.toString());
    }
    final Object? itemId = json['itemId'];
    final Object? packRef = json['packRef'];
    if (itemId != null && itemId is! String) {
      throw FormatException('itemId is not a string', json.toString());
    }
    return AttemptVerdict(
      itemId: itemId as String?,
      packRef: packRef is Map<String, Object?> ? PackRef.fromJson(packRef) : null,
      ok: ok,
      payload: payload,
    );
  }

  final String? itemId;
  final PackRef? packRef;
  final bool ok;

  /// The diagnosis, opaque on the wire. `ARCHITECTURE.md` §2 forbids response
  /// polymorphism, so variance lives inside an object.
  final Map<String, Object?> payload;

  @override
  bool operator ==(Object other) =>
      other is AttemptVerdict &&
      other.itemId == itemId &&
      other.packRef == packRef &&
      other.ok == ok;

  @override
  int get hashCode => Object.hash(itemId, packRef, ok);

  @override
  String toString() => 'AttemptVerdict(${itemId ?? packRef}, ok: $ok)';
}

/// A pack the server issued, and the two instants that bound it.
///
/// **The body is carried, not parsed.** `content/pack_reader.dart` already
/// knows what a pack is and refuses an expired or malformed one; parsing it
/// twice would be two answers to the same question.
@immutable
class IssuedPack {
  const IssuedPack({
    required this.packId,
    required this.issuedAt,
    required this.expiresAt,
    required this.pack,
  });

  factory IssuedPack.fromJson(Map<String, Object?> json) {
    final Object? packId = json['packId'];
    final Object? pack = json['pack'];
    if (packId is! String) {
      throw FormatException('packId is not a string', json.toString());
    }
    if (pack is! Map<String, Object?>) {
      throw FormatException('pack is not an object', json.toString());
    }
    return IssuedPack(
      packId: packId,
      issuedAt: readInstant(_string(json, 'issuedAt')),
      expiresAt: readInstant(_string(json, 'expiresAt')),
      pack: pack,
    );
  }

  static String _string(Map<String, Object?> json, String field) {
    final Object? value = json[field];
    if (value is! String) {
      throw FormatException('$field is not a string', json.toString());
    }
    return value;
  }

  /// What an attempt against this pack names, with the item's position.
  final String packId;

  final DateTime issuedAt;
  final DateTime expiresAt;

  /// The frozen pack format, unread.
  final Map<String, Object?> pack;

  @override
  String toString() => 'IssuedPack($packId, expires $expiresAt)';
}
