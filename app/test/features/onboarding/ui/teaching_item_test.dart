/// The `7 + 6` collision gate: a Tier 2 finding turned into a red build.
///
/// The teaching item **was** `7 + 6`, which is `add-1` — the starter pack's
/// *first* item, and so both what the home previews as `RETO DEL DÍA` and what
/// `Empezar la serie` opens with. A new player solved it in the tutorial and
/// then met it twice on the very next screen.
///
/// Nothing in the suite could see it: `FirstItemScreen` is handed its item in
/// every test and the home tests are handed a fixture, so the two never met.
/// Reading the **real** pack is what closes that gap — and it means editing
/// `assets/packs/starter.json` to add a `5 + 8` fails here rather than shipping
/// the repeat back. `policy/calibration_test.dart` guards the probe's end of
/// the same rule, because the probe takes the pack's first ten.
library;

import 'package:akimath_app/content/model/item.dart';
import 'package:akimath_app/content/model/pack.dart';
import 'package:akimath_app/content/pack_reader.dart';
import 'package:akimath_app/features/onboarding/ui/first_item_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the player reads, as one comparable string.
///
/// `PromptToken` has no `==`, and giving it one for a test's benefit would put
/// equality semantics on a model that has no use for them. A few lines here are
/// cheaper and say exactly what is being compared: the glyphs on screen.
///
/// **Total over the sealed type, not a cast.** It cast every item to arithmetic
/// until the pack gained number-series items, at which point it threw — and a
/// collision gate that dies on the first new family is a gate that gets deleted
/// rather than fixed. A series and an expression can never collide anyway; the
/// prefix says so rather than the cast assuming it.
String _prompt(Item item) => switch (item.stimulus) {
      ArithmeticStimulus(:final List<PromptToken> prompt) =>
        prompt.map((PromptToken token) {
          return switch (token) {
            TextToken(:final String value) => value,
            OperatorToken(:final String glyph) => glyph,
            FractionToken(:final String numerator, :final String denominator) =>
              '$numerator/$denominator',
          };
        }).join(' '),
      NumberSeriesStimulus(:final List<int> terms) =>
        'series: ${terms.join(' ')}',
      MatrixStimulus(:final List<int> cells) => 'matrix: ${cells.join(' ')}',
      AnalogyStimulus(:final List<int> terms) =>
        'analogy: ${terms.join(' ')}',
      HiddenOperationStimulus(:final int queryInput) =>
        'machine: $queryInput',
      FigurateStimulus(:final List<int> dotCounts) =>
        'figurate: ${dotCounts.join(' ')}',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the teaching item is not an item the player is about to meet', () {
    test('no item in the shipped pack has its prompt', () async {
      final Pack pack = await const PackReader().load();

      expect(
        pack.items.map(_prompt),
        isNot(contains(_prompt(FirstItemScreen.teachingItem))),
        reason: 'the tutorial repeats a pack item, so the home will show the '
            'player the expression they just solved',
      );
    });

    test('it reports what it compared, and comparing nothing is a failure',
        () async {
      final Pack pack = await const PackReader().load();

      expect(pack.items, isNotEmpty);
      // ignore: avoid_print
      print('  teaching item · compared against ${pack.items.length} pack items'
          ' → ${_prompt(FirstItemScreen.teachingItem)}');
    });
  });
}
