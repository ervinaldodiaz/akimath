import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/design/math/spec/math_node.dart';
import 'package:akimath_app/features/round/policy/prompt_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a prompt becomes a node tree', () {
    test('each token kind maps to its node', () {
      final RowNode row = nodeForTokens(<PromptToken>[
        const PromptToken.fraction(numerator: '3', denominator: '4'),
        const PromptToken.operator('+'),
        const PromptToken.text('1'),
      ]) as RowNode;

      expect(row.children, hasLength(3));
      expect(row.children[0], isA<FractionNode>());
      expect(row.children[1], isA<OperatorNode>());
      expect(row.children[2], isA<NumeralNode>());
    });

    test('a fraction keeps its numerator and denominator, in that order — the '
        'one branch with structure, and a swap would render a different '
        'question with every other gate green', () {
      final FractionNode fraction = (nodeForTokens(<PromptToken>[
        const PromptToken.fraction(numerator: '3', denominator: '4'),
      ]) as RowNode)
          .children
          .single as FractionNode;

      expect((fraction.numerator as NumeralNode).digits, '3');
      expect((fraction.denominator as NumeralNode).digits, '4');
    });

    test('the token order is preserved', () {
      final RowNode row = nodeForTokens(<PromptToken>[
        const PromptToken.text('9'),
        const PromptToken.operator('−'),
        const PromptToken.text('4'),
        const PromptToken.operator('='),
      ]) as RowNode;

      expect((row.children[0] as NumeralNode).digits, '9');
      expect((row.children[1] as OperatorNode).glyph, '−');
      expect((row.children[2] as NumeralNode).digits, '4');
      expect((row.children[3] as OperatorNode).glyph, '=');
    });

    test('an operator defaults to the face D7 gives it', () {
      final RowNode row = nodeForTokens(<PromptToken>[
        const PromptToken.operator('+'),
        const PromptToken.operator('='),
      ]) as RowNode;

      expect((row.children[0] as OperatorNode).face, MathFace.display);
      expect((row.children[1] as OperatorNode).face, MathFace.textHeavy);
    });

    test('a solidus in a prompt is refused rather than drawn inline, because '
        'the compositor cannot express an inline fraction', () {
      expect(
        () => nodeForTokens(<PromptToken>[const PromptToken.operator('/')]),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
