import 'package:akimath_app/content/model/canon.dart';
import 'package:akimath_app/features/round/policy/answer_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a draft accumulates what was typed', () {
    test('digits append in order', () {
      AnswerDraft draft = AnswerDraft.empty;
      for (final String digit in <String>['2', '3']) {
        draft = draft.type(digit);
      }
      expect(draft.text, '23');
    });

    test('backspace removes one character and stops at empty', () {
      AnswerDraft draft = AnswerDraft.empty.type('4').type('7');
      expect(draft.backspace().text, '4');
      expect(draft.backspace().backspace().text, '');
      expect(
        draft.backspace().backspace().backspace().text,
        '',
        reason: 'backspacing an empty draft must not throw or wrap',
      );
    });

    test('the draft is a value, not a mutable buffer', () {
      const AnswerDraft start = AnswerDraft.empty;
      final AnswerDraft after = start.type('5');

      expect(start.text, '');
      expect(after.text, '5');
    });
  });

  group('the draft holds the codepoint contract it was given', () {
    test('a minus sign is stored as U+2212, never a hyphen', () {
      final AnswerDraft draft = AnswerDraft.empty.type('−').type('6');
      expect(draft.text.codeUnitAt(0), 0x2212);
      expect(draft.text, isNot(contains('-')));
    });

    test('a fraction slash is accepted', () {
      expect(AnswerDraft.empty.type('1').type('/').type('2').text, '1/2');
    });
  });

  group('what a draft refuses', () {
    test('a character the grader cannot read never reaches the draft', () {
      for (final String rejected in <String>[',', '²', 'x', '.', '+']) {
        expect(
          AnswerDraft.empty.type('4').type(rejected).text,
          '4',
          reason: '"$rejected" reached the draft',
        );
      }
    });

    test('a draft of only a rejected character cannot be submitted', () {
      expect(AnswerDraft.empty.type(',').canSubmit, isFalse);
      expect(AnswerDraft.empty.type(',').text, isEmpty);
    });

    test('every accepted character canonicalises, checked against the grader '
        'rather than from memory', () {
      expect(
        AnswerDraft.acceptedCharacters,
        <String>{'0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '−', '/'},
      );

      for (final String digit in <String>['0', '5', '9']) {
        expect(canonicalise(digit, mode: CanonMode.learner).ok, isTrue);
      }
      expect(canonicalise('−5', mode: CanonMode.learner).ok, isTrue);
      expect(canonicalise('1/2', mode: CanonMode.learner).ok, isTrue);
    });

    test('the keys the pad offers but the grader cannot read are excluded', () {
      expect(AnswerDraft.acceptedCharacters, isNot(contains(',')));
      expect(AnswerDraft.acceptedCharacters, isNot(contains('²')));
    });

    test('a minus is only accepted in the leading position', () {
      expect(AnswerDraft.empty.type('5').type('−').text, '5');
      expect(AnswerDraft.empty.type('−').type('5').text, '−5');
    });

    test('a held key stops at the ceiling rather than overflowing the slot',
        () {
      AnswerDraft draft = AnswerDraft.empty;
      for (int i = 0; i < 40; i++) {
        draft = draft.type('9');
      }
      expect(draft.text.length, AnswerDraft.maxLength);
    });
  });

  group('submitting', () {
    test('an empty draft cannot be submitted', () {
      expect(AnswerDraft.empty.canSubmit, isFalse);
      expect(AnswerDraft.empty.type('7').canSubmit, isTrue);
    });

    test('a draft that is only a minus sign cannot be submitted', () {
      expect(AnswerDraft.empty.type('−').canSubmit, isFalse);
    });
  });
}
