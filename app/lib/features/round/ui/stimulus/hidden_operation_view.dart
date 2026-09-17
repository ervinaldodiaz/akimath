import 'package:flutter/widgets.dart';

import '../../../../design/icons/brand_icon.dart';
import '../../../../design/tokens/tokens.dart';
import 'stimulus_tile.dart';

/// The function machine: worked examples, then one to answer.
///
/// ```
/// 2 › 7
/// 5 › 16
/// 9 › ?
/// ```
///
/// The fifth family, and the only one with no `unknown_index` — the hole is
/// always the query's output, because that *is* the question. Two examples is
/// the floor the frozen schema sets and the reason is arithmetic rather than
/// pedagogy: one example fixes no operation, since `2 › 7` is `+5` and `×3+1`
/// and any number of other rules at once.
///
/// **Aki is not here, and that is deliberate.** `docs/IMPLEMENTATION-PLAN.md`
/// describes this family as *"a function machine with Aki's tail curl"*, but
/// `CLAUDE.md` holds that she does not appear while the learner is solving —
/// and an invariant outranks a sketch. The rows carry the machine without her;
/// she can meet the learner on the verdict, where she already does.
class HiddenOperationView extends StatelessWidget {
  const HiddenOperationView({
    super.key,
    required this.examples,
    required this.queryInput,
    this.size = 46,
  });

  /// The worked pairs, in the order the pack lists them. Two or three.
  final List<({int input, int output})> examples;

  /// The input the learner has to transform. Never one of the examples' — the
  /// reader refuses that payload, because an answer already on screen is not a
  /// question.
  final int queryInput;

  /// Nominal numeral size, before text scaling.
  final double size;

  /// The worked rows, the rule, then the question.
  ///
  /// **`IntrinsicWidth`, so the rule is exactly as wide as the machine.** A
  /// `double.infinity` divider inside a `Column(min)` that a `FittedBox` then
  /// measures is an unbounded-width assertion, and computing the row width by
  /// hand would mean re-deriving [StimulusTile]'s padding, border and shadow
  /// here — three numbers that would go stale silently.
  ///
  /// Each row is centred inside the stretched column, so `stretch` reaches the
  /// rule without also left-aligning every row. The rule sits above the query
  /// so it reads as what is *asked* rather than as a fourth thing the learner
  /// was given.
  @override
  Widget build(BuildContext context) {
    return IntrinsicWidth(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final ({int input, int output}) example in examples) ...<Widget>[
            Center(
              child: _row(
                StimulusTile.given(example.input, size: size),
                StimulusTile.given(example.output, size: size),
              ),
            ),
            const SizedBox(height: BrandShape.space2),
          ],
          const SizedBox(
            height: BrandShape.borderWidthField,
            child: ColoredBox(color: BrandColors.ink),
          ),
          const SizedBox(height: BrandShape.space3),
          Center(
            child: _row(
              StimulusTile.given(queryInput, size: size),
              StimulusTile.unknown(size: size),
            ),
          ),
        ],
      ),
    );
  }

  /// One line of the machine: what went in, what came out.
  Widget _row(Widget input, Widget output) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          input,
          SizedBox(
            width: size * 0.7,
            child: Center(
              child: BrandIcon(
                BrandGlyph.mapsTo,
                size: size * 0.62,
                color: BrandColors.ink,
              ),
            ),
          ),
          output,
        ],
      );
}
