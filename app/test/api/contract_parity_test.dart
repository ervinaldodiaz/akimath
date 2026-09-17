/// `app/lib/api/` held against `contract/openapi.json`, operation by operation.
///
/// **Three facts this file asserts by omission, which no test name can say.**
/// `500` is deliberately absent from the statuses checked against `GET /me`:
/// the contract does not declare it, and the client must survive one anyway, so
/// it falls into the catch-all rather than a branch of its own. The `501` list
/// is checked the other way round — an operation stops advertising itself as
/// unbuilt in the diff that builds it, which is the client's half of the
/// server's `test/contract-parity.test.ts`. And `SkillStanding.rating` is
/// asserted **not** nullable: the day the schema gains `nullable: true` there,
/// this file goes red and the model has a decision to revisit.
///
/// **The out-of-range probe is out of range on purpose.** The time-on-task case
/// read `4200` ms against a maximum of 3_600_000 until 2026-09-02 — PROC-11's
/// fifth bullet, an assertion that was sound over a fixture that made it
/// insensitive, so a test named for the bound could not fail on anything the
/// app produces. The `greaterThan(maximum)` guard beside the probe is what
/// stops that returning.
library;

import 'dart:convert';
import 'dart:io';

import 'package:akimath_app/api/history.dart';
import 'package:akimath_app/api/me.dart';
import 'package:akimath_app/api/standing.dart';
import 'package:akimath_app/api/sync.dart';
import 'package:akimath_app/api/time_on_task.dart';
import 'package:akimath_app/features/sync/policy/attempt_journal.dart';
import 'package:flutter_test/flutter_test.dart';

/// Instants the frozen pattern and the Dart model both take.
const List<String> _acceptedByBoth = <String>[
  '2026-08-19T09:15:00.000Z',
  '2026-01-02T03:04:05.678Z',
  '2026-01-02T03:04:05Z',
  '2026-01-02T03:04Z',
  '2028-02-29T00:00:00.000Z',
  '2000-02-29T00:00:00.000Z',
  '2026-01-31T23:59:59.999Z',
];

/// Instants both refuse, several of which `DateTime.parse` would happily read.
const List<String> _refusedByBoth = <String>[
  '2026-01-02T03:04:05.678+00:00',
  '2026-01-02T03:04:05.678',
  '2026-01-02 03:04:05.678Z',
  '2026-02-30T00:00:00.000Z',
  '2025-02-29T00:00:00.000Z',
  '1900-02-29T00:00:00.000Z',
  '2026-04-31T00:00:00.000Z',
  '2026-13-01T00:00:00.000Z',
  '2026-01-02T24:00:00.000Z',
  '2026-01-02T03:60:00.000Z',
  'yesterday',
  '',
];

/// The frozen contract, read rather than restated.
///
/// R2 in its client form: `contract/openapi.json` and `app/lib/api/` are two
/// descriptions of the same wire, and nothing else compares them. The server
/// has `test/contract-parity.test.ts` for its half; this is the other.
///
/// Thrown at load, the way `content/model/canon_test.dart` does it: this runs
/// while the file is being loaded, before any test body, where `expect` has
/// nowhere to report — and a parity test that silently covers nothing is worse
/// than none (PROC-10).
Map<String, Object?> _contract() {
  final File file = File('../contract/openapi.json');
  if (!file.existsSync()) {
    throw StateError(
      'the frozen contract is missing at ${file.absolute.path} — client parity '
      'cannot be checked, and a silently vacuous gate is worse than none',
    );
  }
  return json.decode(file.readAsStringSync()) as Map<String, Object?>;
}

Map<String, Object?> _schema(Map<String, Object?> contract, String name) {
  final Map<String, Object?> components =
      contract['components']! as Map<String, Object?>;
  final Map<String, Object?> schemas =
      components['schemas']! as Map<String, Object?>;
  return schemas[name]! as Map<String, Object?>;
}

/// Fields the model carries without checking their shape, and why.
///
/// **`playerId` is passed through, not validated.** The contract pins it to a
/// uuid pattern, and the asymmetry with `createdAt` is deliberate: parsing a
/// date *changes* the value, so an unvalidated one round-trips to different
/// bytes and the two sides stop agreeing about an instant. An id is carried
/// verbatim — an off-contract one is the server's bug, and refusing it here
/// would turn a cosmetic server defect into a client that cannot show a
/// profile.
///
/// Named rather than omitted, so a second entry has to be argued for.
const Map<String, String> _carriedNotValidated = <String, String>{
  'playerId': 'carried verbatim; validating it would refuse a profile over a server-side typo',
};

void main() {
  final Map<String, Object?> contract = _contract();
  final Map<String, Object?> me = _schema(contract, 'Me');
  final List<String> required =
      (me['required']! as List<Object?>).cast<String>();

  final Me sample = Me(
    playerId: '018f4e3c-0000-7000-8000-0000000000b1',
    ageBand: AgeBand.under13,
    createdAt: DateTime.utc(2026, 8, 19, 9, 15),
  );

  test('the gate read a real document', () {
    expect(required, isNotEmpty);
    // ignore: avoid_print
    print('  api parity · Me → ${required.length} required field(s), '
        '${_carriedNotValidated.length} carried without validation');
  });

  group('the Dart model is the frozen Me, both directions', () {
    test('it carries every field the schema requires', () {
      expect(sample.toJson().keys.toSet(), containsAll(required));
    });

    test('and no field the schema does not describe, so the client cannot '
        'invent one', () {
      final Map<String, Object?> properties =
          me['properties']! as Map<String, Object?>;
      expect(sample.toJson().keys.toSet(), properties.keys.toSet());
    });

    test('every band the schema names, in the order it names them, because a '
        'set comparison would pass while the two rotated', () {
      final Map<String, Object?> properties =
          me['properties']! as Map<String, Object?>;
      final Map<String, Object?> band =
          properties['ageBand']! as Map<String, Object?>;
      final List<String> frozen = (band['enum']! as List<Object?>).cast<String>();

      expect(AgeBand.values.map((AgeBand b) => b.wireName).toList(), frozen);
    });
  });

  group('the Dart model is the frozen HistoryEntry, both directions', () {
    final Map<String, Object?> schema = _schema(contract, 'HistoryEntry');
    final List<String> entryRequired =
        (schema['required']! as List<Object?>).cast<String>();
    final Map<String, Object?> properties =
        schema['properties']! as Map<String, Object?>;

    final HistoryEntry sampleEntry = HistoryEntry(
      kind: HistoryKind.series,
      title: 'Restas',
      at: DateTime.utc(2026, 8, 19, 9, 15),
      score: '4/5',
      ratingDelta: null,
    );

    test('the gate read a real schema', () {
      expect(entryRequired, isNotEmpty);
      // ignore: avoid_print
      print('  api parity · HistoryEntry → ${entryRequired.length} required field(s)');
    });

    test('it carries every field the schema requires, and no other', () {
      expect(sampleEntry.toJson().keys.toSet(), containsAll(entryRequired));
      expect(sampleEntry.toJson().keys.toSet(), properties.keys.toSet());
    });

    test('every kind the schema names, in the order it names them', () {
      final Map<String, Object?> kind = properties['kind']! as Map<String, Object?>;
      final List<String> frozen = (kind['enum']! as List<Object?>).cast<String>();

      expect(HistoryKind.values.map((HistoryKind k) => k.wireName).toList(), frozen);
    });

    test('ratingDelta is nullable in the schema and nullable here', () {
      final Map<String, Object?> delta =
          properties['ratingDelta']! as Map<String, Object?>;

      expect(entryRequired, contains('ratingDelta'));
      expect(delta['nullable'], isTrue);
      expect(sampleEntry.toJson()['ratingDelta'], isNull);
    });

    test('and its instant is read by the same reader Me uses', () {
      final Map<String, Object?> at = properties['at']! as Map<String, Object?>;
      final Map<String, Object?> meProperties =
          me['properties']! as Map<String, Object?>;
      final Map<String, Object?> createdAt =
          meProperties['createdAt']! as Map<String, Object?>;

      expect(at['pattern'], createdAt['pattern']);
    });
  });

  group('the Dart model is the frozen Standing, both directions', () {
    final Map<String, Object?> standing = _schema(contract, 'Standing');
    final List<String> standingRequired =
        (standing['required']! as List<Object?>).cast<String>();
    final Map<String, Object?> standingProperties =
        standing['properties']! as Map<String, Object?>;
    final Map<String, Object?> skillSchema =
        (standingProperties['skills']! as Map<String, Object?>)['items']!
            as Map<String, Object?>;
    final List<String> skillRequired =
        (skillSchema['required']! as List<Object?>).cast<String>();
    final Map<String, Object?> skillProperties =
        skillSchema['properties']! as Map<String, Object?>;

    final Standing sampleStanding = Standing(
      playerId: '018f4e3c-0000-7000-8000-0000000000b1',
      skills: <SkillStanding>[
        SkillStanding(
          skillId: 1,
          rating: 1200.5,
          deviation: 350,
          updatedAt: DateTime.utc(2026, 8, 19, 9, 15),
        ),
      ],
    );

    test('the gate read a real schema', () {
      expect(standingRequired, isNotEmpty);
      expect(skillRequired, isNotEmpty);
      // ignore: avoid_print
      print('  api parity · Standing → ${standingRequired.length} required field(s), '
          'each skill ${skillRequired.length}');
    });

    test('it carries every field the schema requires, and no other', () {
      expect(sampleStanding.toJson().keys.toSet(), containsAll(standingRequired));
      expect(sampleStanding.toJson().keys.toSet(), standingProperties.keys.toSet());
    });

    test('and so does each skill in it', () {
      final Map<String, Object?> skill =
          (sampleStanding.toJson()['skills']! as List<Object?>).first!
              as Map<String, Object?>;

      expect(skill.keys.toSet(), containsAll(skillRequired));
      expect(skill.keys.toSet(), skillProperties.keys.toSet());
    });

    test('rating is required and NOT nullable, which is why there is no null to send', () {
      final Map<String, Object?> rating =
          skillProperties['rating']! as Map<String, Object?>;

      expect(skillRequired, contains('rating'));
      expect(rating['nullable'], isNot(isTrue));
      expect(rating['type'], 'number');
    });

    test('an unrated player is an empty list, and still a whole Standing', () {
      const Standing unrated = Standing(
        playerId: '018f4e3c-0000-7000-8000-0000000000b1',
        skills: <SkillStanding>[],
      );

      expect(unrated.isUnrated, isTrue);
      expect(unrated.toJson()['skills'], isEmpty);
      expect(unrated.toJson().keys.toSet(), containsAll(standingRequired));
    });

    test('its instant is read by the same reader Me uses', () {
      final Map<String, Object?> updatedAt =
          skillProperties['updatedAt']! as Map<String, Object?>;
      final Map<String, Object?> meProperties =
          me['properties']! as Map<String, Object?>;
      final Map<String, Object?> createdAt =
          meProperties['createdAt']! as Map<String, Object?>;

      expect(updatedAt['pattern'], createdAt['pattern']);
    });

    test('the operation is one the contract describes, and no longer unbuilt', () {
      final Map<String, Object?> paths = contract['paths']! as Map<String, Object?>;
      final Map<String, Object?> get =
          (paths['/me/standing']! as Map<String, Object?>)['get']!
              as Map<String, Object?>;
      final Set<String> declared =
          (get['responses']! as Map<String, Object?>).keys.toSet();

      expect(get['operationId'], 'getStanding');
      expect(declared, containsAll(<String>['200', '401', '404']));
      expect(declared, isNot(contains('501')));
    });
  });

  group('the Dart submission is the frozen AttemptSubmission', () {
    final Map<String, Object?> schema = _schema(contract, 'AttemptSubmission');
    final List<String> required =
        (schema['required']! as List<Object?>).cast<String>();
    final Map<String, Object?> properties =
        schema['properties']! as Map<String, Object?>;

    /// A submission naming a pack item, as it goes on the wire.
    ///
    /// One builder per source rather than one taking a flag: the two
    /// constructions are two constructors now, and a boolean selecting between
    /// them would be the shape FUN-2 bans.
    Map<String, Object?> sentByPack({
      Duration elapsed = const Duration(milliseconds: 4200),
    }) => AttemptSubmission.forPackItem(
      ref: const PackRef(packId: '018f4e3c-0000-7000-8000-0000000000c1', index: 0),
      sessionId: '018f4e3c-0000-7000-8000-0000000000c2',
      answer: '13',
      at: DateTime.utc(2026, 8, 19, 9, 15),
      elapsed: elapsed,
    ).toJson();

    /// The same, naming an item the server issued.
    Map<String, Object?> sentByIssuedItem({
      Duration elapsed = const Duration(milliseconds: 4200),
    }) => AttemptSubmission.forIssuedItem(
      itemId: '018f4e3c-0000-7000-8000-0000000000c3',
      sessionId: '018f4e3c-0000-7000-8000-0000000000c2',
      answer: '13',
      at: DateTime.utc(2026, 8, 19, 9, 15),
      elapsed: elapsed,
    ).toJson();

    /// A row read back off disk, which is the path a device that recorded one
    /// before this bound existed still travels. `toSubmission` is the one
    /// mapping (`test/architecture/one_way_to_build_a_submission_test.dart`),
    /// so this is what the shipping flush actually sends.
    Map<String, Object?> sentFromTheJournal(Duration elapsed) =>
        JournalledAttempt(
          packId: '018f4e3c-0000-7000-8000-0000000000c1',
          index: 0,
          sessionId: '018f4e3c-0000-7000-8000-0000000000c2',
          answer: '13',
          at: DateTime.utc(2026, 8, 19, 9, 15),
          elapsed: elapsed,
        ).toSubmission().toJson();

    test('the gate read a real schema', () {
      expect(required, isNotEmpty);
      // ignore: avoid_print
      print('  api parity · AttemptSubmission → ${required.length} required field(s), '
          '${properties.length} in all');
    });

    test('it sends every field the schema requires', () {
      for (final Map<String, Object?> body in <Map<String, Object?>>[
        sentByPack(),
        sentByIssuedItem(),
      ]) {
        expect(body.keys.toSet(), containsAll(required));
      }
    });

    test('and no field the schema does not describe, or the batch comes back '
        'a 400', () {
      for (final Map<String, Object?> body in <Map<String, Object?>>[
        sentByPack(),
        sentByIssuedItem(),
      ]) {
        expect(properties.keys.toSet(), containsAll(body.keys));
      }
    });

    test('exactly one source — 3.0.3 has no union, so the schema cannot say it '
        'and two enforcements do', () {
      expect(required, isNot(contains('itemId')));
      expect(required, isNot(contains('packRef')));
      expect(sentByPack().containsKey('itemId'), isFalse);
      expect(sentByIssuedItem().containsKey('packRef'), isFalse);

      final Map<String, Object?> operation =
          ((contract['paths']! as Map<String, Object?>)['/attempts']!
              as Map<String, Object?>)['post']! as Map<String, Object?>;
      expect(operation['description'], contains('exactly one'));
    });

    test('and time on task stays inside the bound the schema sets', () {
      final Map<String, Object?> elapsed =
          properties['elapsedMs']! as Map<String, Object?>;
      final int maximum = elapsed['maximum']! as int;
      const Duration leftInAPocket = Duration(hours: 3, minutes: 20);

      expect(elapsed['minimum'], 0);
      expect(leftInAPocket.inMilliseconds, greaterThan(maximum),
          reason: 'the probe has to be out of range or this proves nothing');

      for (final Map<String, Object?> body in <Map<String, Object?>>[
        sentByPack(elapsed: leftInAPocket),
        sentByIssuedItem(elapsed: leftInAPocket),
        sentFromTheJournal(leftInAPocket),
      ]) {
        expect(body['elapsedMs'], lessThanOrEqualTo(maximum));
        expect(body['elapsedMs'], greaterThanOrEqualTo(elapsed['minimum']! as int));
      }
    });

    test('the bound the client saturates at is the bound the document sets', () {
      final Map<String, Object?> elapsed =
          properties['elapsedMs']! as Map<String, Object?>;

      expect(maxReportableTimeOnTask.inMilliseconds, elapsed['maximum']);
      expect(reportableTimeOnTask(Duration.zero).inMilliseconds, elapsed['minimum']);
    });

    test('and so does one measured backwards across a clock change', () {
      final Map<String, Object?> elapsed =
          properties['elapsedMs']! as Map<String, Object?>;

      for (final Map<String, Object?> body in <Map<String, Object?>>[
        sentByPack(elapsed: const Duration(milliseconds: -1)),
        sentByIssuedItem(elapsed: const Duration(milliseconds: -1)),
        sentFromTheJournal(const Duration(milliseconds: -1)),
      ]) {
        expect(body['elapsedMs'], elapsed['minimum']);
      }
    });
  });

  group("createdAt agrees with the contract's own pattern", () {
    late final RegExp frozen;

    setUpAll(() {
      final Map<String, Object?> properties =
          me['properties']! as Map<String, Object?>;
      final Map<String, Object?> createdAt =
          properties['createdAt']! as Map<String, Object?>;
      frozen = RegExp(createdAt['pattern']! as String);
    });

    const List<String> probes = <String>[
      ..._acceptedByBoth,
      ..._refusedByBoth,
    ];

    test('on every probe, accepted or refused together', () {
      final List<String> disagreements = <String>[];
      for (final String probe in probes) {
        final bool byContract = frozen.hasMatch(probe);
        bool byModel;
        try {
          Me.fromJson(<String, Object?>{
            'playerId': '018f4e3c-0000-7000-8000-0000000000b1',
            'ageBand': 'adult',
            'createdAt': probe,
          });
          byModel = true;
        } on FormatException {
          byModel = false;
        }
        if (byContract != byModel) {
          disagreements.add(
            '"$probe": contract=${byContract ? 'accepts' : 'refuses'} '
            'model=${byModel ? 'accepts' : 'refuses'}',
          );
        }
      }

      expect(probes.length, greaterThan(10));
      expect(disagreements, isEmpty);
    });
  });

  group('what the client is allowed to expect back', () {
    test('GET /me is an operation the contract describes', () {
      final Map<String, Object?> paths = contract['paths']! as Map<String, Object?>;
      final Map<String, Object?> path = paths['/me']! as Map<String, Object?>;
      final Map<String, Object?> get = path['get']! as Map<String, Object?>;

      expect(get['operationId'], 'getMe');
    });

    test('every status the client maps is one the contract declares, never one '
        'written from memory', () {
      final Map<String, Object?> paths = contract['paths']! as Map<String, Object?>;
      final Map<String, Object?> path = paths['/me']! as Map<String, Object?>;
      final Map<String, Object?> get = path['get']! as Map<String, Object?>;
      final Set<String> declared =
          (get['responses']! as Map<String, Object?>).keys.toSet();

      expect(declared, containsAll(<String>['200', '401', '404']));
    });

    test('every carried-not-validated field is really in the schema, so a stale '
        'exclusion excuses nothing', () {
      final Map<String, Object?> properties =
          me['properties']! as Map<String, Object?>;
      for (final MapEntry<String, String> entry in _carriedNotValidated.entries) {
        expect(properties.keys, contains(entry.key));
        expect(entry.value, isNotEmpty);
      }
    });
  });

  group('the link the client can now make', () {
    test('POST /players/link is an operation the contract describes', () {
      final Map<String, Object?> paths = contract['paths']! as Map<String, Object?>;
      final Map<String, Object?> post =
          (paths['/players/link']! as Map<String, Object?>)['post']! as Map<String, Object?>;
      expect(post['operationId'], 'linkPlayer');
    });

    test('every status the client maps is one the contract declares, 409 '
        'included', () {
      final Map<String, Object?> paths = contract['paths']! as Map<String, Object?>;
      final Map<String, Object?> post =
          (paths['/players/link']! as Map<String, Object?>)['post']! as Map<String, Object?>;
      final Set<String> declared =
          (post['responses']! as Map<String, Object?>).keys.toSet();

      expect(declared, containsAll(<String>['200', '400', '401', '409']));
    });

    test('the request carries what the schema requires and nothing more, so a '
        'new field fails rather than going unsent', () {
      final Map<String, Object?> link = _schema(contract, 'PlayerLink');
      final Set<String> required =
          (link['required']! as List<Object?>).cast<String>().toSet();
      final Set<String> properties =
          (link['properties']! as Map<String, Object?>).keys.toSet();

      expect(required, <String>{'playerId', 'ageBand'});
      expect(properties, required);
      expect(link['additionalProperties'], isFalse);
    });

    test('the header the contract marks required is one the client sends', () {
      final Map<String, Object?> paths = contract['paths']! as Map<String, Object?>;
      final Map<String, Object?> post =
          (paths['/players/link']! as Map<String, Object?>)['post']! as Map<String, Object?>;
      final List<Object?> parameters = post['parameters']! as List<Object?>;
      final List<String> requiredHeaders = <String>[
        for (final Object? p in parameters)
          if ((p! as Map<String, Object?>)['in'] == 'header' &&
              (p as Map<String, Object?>)['required'] == true)
            (p)['name']! as String,
      ];
      expect(requiredHeaders, <String>['Idempotency-Key']);
    });
  });
}
