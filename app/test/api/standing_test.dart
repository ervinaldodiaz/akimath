import 'package:akimath_app/api/standing.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _skill({
  Object? skillId = 1,
  Object? rating = 1200.5,
  Object? deviation = 350,
  Object? updatedAt = '2026-08-19T09:15:00.000Z',
}) => <String, Object?>{
  'skillId': skillId,
  'rating': rating,
  'deviation': deviation,
  'updatedAt': updatedAt,
};

Map<String, Object?> _standing({
  Object? playerId = '018f4e3c-0000-7000-8000-0000000000b1',
  Object? skills,
}) => <String, Object?>{
  'playerId': playerId,
  'skills': skills ?? <Object?>[_skill()],
};

void main() {
  group('one rated skill, read off the wire', () {
    test('it carries every field the frozen entry names', () {
      final SkillStanding skill = SkillStanding.fromJson(_skill());

      expect(skill.skillId, 1);
      expect(skill.rating, 1200.5);
      expect(skill.deviation, 350.0);
      expect(skill.updatedAt, DateTime.utc(2026, 8, 19, 9, 15));
    });

    test('a whole rating arrives as an int and is still a rating', () {
      final SkillStanding skill =
          SkillStanding.fromJson(_skill(rating: 1200, deviation: 350));

      expect(skill.rating, 1200.0);
      expect(skill.deviation, 350.0);
    });

    test('a negative rating is read, because the schema sets no floor', () {
      expect(SkillStanding.fromJson(_skill(rating: -12.5)).rating, -12.5);
    });

    test('a field the schema requires cannot be missing', () {
      for (final String field in <String>[
        'skillId',
        'rating',
        'deviation',
        'updatedAt',
      ]) {
        final Map<String, Object?> body = _skill()..remove(field);
        expect(
          () => SkillStanding.fromJson(body),
          throwsFormatException,
          reason: '$field is required and its absence must not pass',
        );
      }
    });

    test('and a field of the wrong type is refused rather than coerced', () {
      expect(() => SkillStanding.fromJson(_skill(rating: 'high')), throwsFormatException);
      expect(() => SkillStanding.fromJson(_skill(skillId: 1.5)), throwsFormatException);
      expect(() => SkillStanding.fromJson(_skill(updatedAt: 17)), throwsFormatException);
    });

    test('its instant is read by the one reader every model in api/ uses', () {
      expect(
        () => SkillStanding.fromJson(_skill(updatedAt: '2026-08-19T09:15:00.000+00:00')),
        throwsFormatException,
      );
      expect(
        () => SkillStanding.fromJson(_skill(updatedAt: '2025-02-29T00:00:00.000Z')),
        throwsFormatException,
      );
    });

    test('it round-trips through its own json', () {
      final SkillStanding skill = SkillStanding.fromJson(_skill());
      expect(SkillStanding.fromJson(skill.toJson()), skill);
    });
  });

  group('the whole standing', () {
    test('it is the player and every skill that has a rating', () {
      final Standing standing = Standing.fromJson(_standing());

      expect(standing.playerId, '018f4e3c-0000-7000-8000-0000000000b1');
      expect(standing.skills, hasLength(1));
      expect(standing.skills.first.skillId, 1);
    });

    test('a player nothing has rated is an empty list, and that is not an error', () {
      final Standing standing = Standing.fromJson(_standing(skills: <Object?>[]));

      expect(standing.skills, isEmpty);
      expect(standing.isUnrated, isTrue);
    });

    test('and a rated player is not unrated, so isUnrated cannot answer true '
        'to everything', () {
      expect(Standing.fromJson(_standing()).isUnrated, isFalse);
    });

    test('the order the server chose is the order it keeps', () {
      final Standing standing = Standing.fromJson(
        _standing(skills: <Object?>[
          _skill(skillId: 4),
          _skill(skillId: 1),
          _skill(skillId: 2),
        ]),
      );

      expect(
        standing.skills.map((SkillStanding s) => s.skillId).toList(),
        <int>[4, 1, 2],
      );
    });

    test('a body missing either required field is refused', () {
      expect(
        () => Standing.fromJson(<String, Object?>{'skills': <Object?>[]}),
        throwsFormatException,
      );
      expect(
        () => Standing.fromJson(<String, Object?>{'playerId': 'p'}),
        throwsFormatException,
      );
    });

    test('and skills that is not a list of objects is refused', () {
      expect(
        () => Standing.fromJson(_standing(skills: 'none')),
        throwsFormatException,
      );
      expect(
        () => Standing.fromJson(_standing(skills: <Object?>['not an object'])),
        throwsFormatException,
      );
    });

    test('it round-trips through its own json', () {
      final Standing standing = Standing.fromJson(_standing());
      expect(Standing.fromJson(standing.toJson()), standing);
    });

    test('two standings that differ are not equal, the control for the round '
        'trip above', () {
      expect(
        Standing.fromJson(_standing()),
        isNot(Standing.fromJson(_standing(skills: <Object?>[]))),
      );
      expect(
        Standing.fromJson(_standing()),
        isNot(Standing.fromJson(_standing(playerId: 'someone-else'))),
      );
      expect(
        SkillStanding.fromJson(_skill()),
        isNot(SkillStanding.fromJson(_skill(rating: 999))),
      );
    });

    test('its toString does not carry a token or an account', () {
      expect(Standing.fromJson(_standing()).toString(), contains('1 skill'));
    });
  });
}
