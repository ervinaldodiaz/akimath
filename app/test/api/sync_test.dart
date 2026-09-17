/// What an [AttemptSubmission] puts on the wire, at runtime.
///
/// **Two of this file's invariants are enforced by the compiler, and what is
/// left here is the half a `test` can still reach.** Naming neither source or
/// both is unwritable — the generative constructor is private to `sync.dart`
/// and each public door sets the other field itself — so that half is a build
/// failure rather than a red case, and the falsification for it is recorded as
/// one. What these cases check is that each door leaves exactly one source on
/// the wire, and that an out-of-range `elapsed` is brought inside the bound:
/// the properties those constructor shapes exist to guarantee.
///
/// **They replace two `throwsA(isA<AssertionError>())` cases rather than
/// deleting them.** `flutter build --release` strips an assert, so both
/// guarantees held in every test and in no shipping binary (TYP-2), and losing
/// the last test of an invariant on the way to strengthening it is the PROC-11
/// regression that rule warns about.
library;

import 'package:akimath_app/api/sync.dart';
import 'package:akimath_app/api/time_on_task.dart';
import 'package:flutter_test/flutter_test.dart';

const String _pack = '018f4e3c-0000-7000-8000-0000000000c1';
const String _session = '018f4e3c-0000-7000-8000-0000000000c2';
const String _item = '018f4e3c-0000-7000-8000-0000000000c3';

void main() {
  group('an attempt names exactly one source', () {
    test('a pack item, by pack and position', () {
      final AttemptSubmission attempt = AttemptSubmission.forPackItem(
        ref: const PackRef(packId: _pack, index: 3),
        sessionId: _session,
        answer: '13',
        at: DateTime.utc(2026, 8, 19, 9, 15),
        elapsed: const Duration(milliseconds: 4200),
      );

      expect(attempt.toJson(), <String, Object?>{
        'packRef': <String, Object?>{'packId': _pack, 'index': 3},
        'sessionId': _session,
        'answer': '13',
        'clientTs': '2026-08-19T09:15:00.000Z',
        'elapsedMs': 4200,
      });
    });

    test('or an item the server issued', () {
      final AttemptSubmission attempt = AttemptSubmission.forIssuedItem(
        itemId: _item,
        sessionId: _session,
        answer: '13',
        at: DateTime.utc(2026, 8, 19, 9, 15),
        elapsed: Duration.zero,
      );

      expect(attempt.toJson()['itemId'], _item);
      expect(attempt.toJson().containsKey('packRef'), isFalse);
    });

    test('and never neither or both, in the build a player runs', () {
      final AttemptSubmission byPack = AttemptSubmission.forPackItem(
        ref: const PackRef(packId: _pack, index: 0),
        sessionId: _session,
        answer: '1',
        at: DateTime.utc(2026),
        elapsed: Duration.zero,
      );
      expect(byPack.packRef, isNotNull);
      expect(byPack.itemId, isNull);
      expect(byPack.toJson().containsKey('itemId'), isFalse);

      final AttemptSubmission byIssued = AttemptSubmission.forIssuedItem(
        itemId: _item,
        sessionId: _session,
        answer: '1',
        at: DateTime.utc(2026),
        elapsed: Duration.zero,
      );
      expect(byIssued.itemId, isNotNull);
      expect(byIssued.packRef, isNull);
      expect(byIssued.toJson().containsKey('packRef'), isFalse);
    });

    test('and it carries no verdict, because there is nowhere to put one', () {
      final Map<String, Object?> body = AttemptSubmission.forPackItem(
        ref: const PackRef(packId: _pack, index: 0),
        sessionId: _session,
        answer: '13',
        at: DateTime.utc(2026),
        elapsed: Duration.zero,
      ).toJson();

      for (final String claim in <String>['ok', 'correct', 'isCorrect', 'verdict', 'score']) {
        expect(body.containsKey(claim), isFalse, reason: claim);
      }
    });

    test('time on task is milliseconds, and travels unaltered inside the bound', () {
      expect(
        AttemptSubmission.forPackItem(
          ref: const PackRef(packId: _pack, index: 0),
          sessionId: _session,
          answer: '1',
          at: DateTime.utc(2026),
          elapsed: const Duration(minutes: 1, seconds: 7),
        ).toJson()['elapsedMs'],
        67000,
      );
      expect(
        AttemptSubmission.forPackItem(
          ref: const PackRef(packId: _pack, index: 0),
          sessionId: _session,
          answer: '1',
          at: DateTime.utc(2026),
          elapsed: maxReportableTimeOnTask,
        ).toJson()['elapsedMs'],
        maxReportableTimeOnTask.inMilliseconds,
      );
    });

    test('a negative one is floored rather than refused', () {
      expect(
        AttemptSubmission.forPackItem(
          ref: const PackRef(packId: _pack, index: 0),
          sessionId: _session,
          answer: '1',
          at: DateTime.utc(2026),
          elapsed: const Duration(milliseconds: -1),
        ).toJson()['elapsedMs'],
        0,
      );
    });

    test('and one measured past the bound — an afternoon in a pocket — '
        'saturates at it', () {
      expect(
        AttemptSubmission.forPackItem(
          ref: const PackRef(packId: _pack, index: 0),
          sessionId: _session,
          answer: '1',
          at: DateTime.utc(2026),
          elapsed: const Duration(hours: 3, minutes: 20),
        ).toJson()['elapsedMs'],
        maxReportableTimeOnTask.inMilliseconds,
      );
    });

    test('the instant is UTC on the wire whatever the device says', () {
      final Map<String, Object?> body = AttemptSubmission.forPackItem(
        ref: const PackRef(packId: _pack, index: 0),
        sessionId: _session,
        answer: '1',
        at: DateTime.utc(2026, 8, 19, 9, 15).toLocal(),
        elapsed: Duration.zero,
      ).toJson();

      expect(body['clientTs'], '2026-08-19T09:15:00.000Z');
    });
  });

  group('a verdict off the wire', () {
    test('echoes the pack item it graded', () {
      final AttemptVerdict verdict = AttemptVerdict.fromJson(<String, Object?>{
        'packRef': <String, Object?>{'packId': _pack, 'index': 3},
        'ok': true,
        'payload': <String, Object?>{},
      });

      expect(verdict.ok, isTrue);
      expect(verdict.packRef, const PackRef(packId: _pack, index: 3));
      expect(verdict.itemId, isNull);
    });

    test('or the issued item', () {
      final AttemptVerdict verdict = AttemptVerdict.fromJson(<String, Object?>{
        'itemId': _item,
        'ok': false,
        'payload': <String, Object?>{'misconception': 'off_by_one'},
      });

      expect(verdict.itemId, _item);
      expect(verdict.ok, isFalse);
      expect(verdict.payload['misconception'], 'off_by_one');
    });

    test('and a body that is not one is refused', () {
      for (final Map<String, Object?> body in <Map<String, Object?>>[
        <String, Object?>{'ok': true},
        <String, Object?>{'payload': <String, Object?>{}},
        <String, Object?>{'ok': 'yes', 'payload': <String, Object?>{}},
        <String, Object?>{'ok': true, 'payload': <String, Object?>{}, 'itemId': 7},
      ]) {
        expect(() => AttemptVerdict.fromJson(body), throwsFormatException, reason: '$body');
      }
    });
  });

  group('a pack the server issued', () {
    Map<String, Object?> body() => <String, Object?>{
      'packId': _pack,
      'issuedAt': '2026-08-19T09:15:00.000Z',
      'expiresAt': '2026-09-18T09:15:00.000Z',
      'pack': <String, Object?>{'pack_format_version': 1},
    };

    test('reads the id, the window and the body', () {
      final IssuedPack issued = IssuedPack.fromJson(body());

      expect(issued.packId, _pack);
      expect(issued.issuedAt, DateTime.utc(2026, 8, 19, 9, 15));
      expect(issued.expiresAt, DateTime.utc(2026, 9, 18, 9, 15));
      expect(issued.pack['pack_format_version'], 1);
    });

    test('the body is carried, not parsed', () {
      expect(
        IssuedPack.fromJson(<String, Object?>{...body(), 'pack': <String, Object?>{}}).pack,
        isEmpty,
      );
    });

    test('and an instant the contract would refuse is refused here', () {
      expect(
        () => IssuedPack.fromJson(<String, Object?>{...body(), 'issuedAt': '2026-02-30T00:00:00Z'}),
        throwsFormatException,
      );
      expect(
        () => IssuedPack.fromJson(<String, Object?>{...body(), 'packId': 7}),
        throwsFormatException,
      );
    });
  });
}
