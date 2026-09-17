import 'dart:io';

import 'package:akimath_app/design/widgets/spec/verdict.dart';
import 'package:flutter_test/flutter_test.dart';

import 'source_tree.dart';

/// A verdict is never drawn by hue alone.
///
/// BRD-1: deuteranopia collapses `#5ED6A4` and `#FF8A5B`, so two 22 px circles
/// that differ only in fill say the same thing to a reader who has it.
/// `Verdict` carries **no colour** for that reason — a call site has to reach
/// for the outline or the glyph, because that is all there is.
///
/// **What the type cannot prevent is a second reach.** Nothing stops a screen
/// pairing `Verdict.correct` with `BrandColorRole.success.color` and painting a
/// disc. The type makes hue-only *unrepresentable from the verdict*; this makes
/// it visible when somebody assembles it from two places.
///
/// One file is allowed to, and it is the one that also draws the ring.
const String _theRing = 'design/widgets/verdict_ring.dart';

/// The roles that mean right and wrong. `focus` is deliberately not here: it is
/// an input affordance and says "here", not "right".
final RegExp _verdictColour = RegExp(r'BrandColorRole\.(success|error)\b');
final RegExp _verdictValue = RegExp(r'\bVerdict\.(correct|wrong)\b');

/// Code with the prose taken out.
///
/// The scan reads for names that appear in explanations of the rule as often as
/// in code — this file's own subject. A gate that fires on a comment about
/// itself gets switched off, which is the lesson `one-way-to-erase.test.ts` and
/// `no_spinner_test.dart` both paid for.
String _codeOf(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
    .split('\n')
    .where((String line) => !RegExp(r'^\s*(///|//|\*)').hasMatch(line))
    .join('\n');

void main() {
  group('the two verdicts differ in both channels', () {
    test('a different outline and a different glyph, so a widget that cannot '
        'spend one channel still has the other', () {
      expect(Verdict.correct.outline, isNot(Verdict.wrong.outline));
      expect(Verdict.correct.glyph, isNot(Verdict.wrong.glyph));
    });

    test('and the type hands out no colour at all, read off its source', () {
      final File spec = File('lib/design/widgets/spec/verdict.dart');
      expect(spec.existsSync(), isTrue, reason: spec.absolute.path);

      expect(
        _codeOf(spec.readAsStringSync()),
        isNot(contains('Color')),
        reason: 'the construction, not the convention: there is nothing on '
            'Verdict to paint with. Read off the source because a getter that '
            'returned a Color would compile fine and nothing else would notice',
      );
    });
  });

  group('and nothing assembles one out of two places', () {
    final Map<String, String> scanned = SourceTree.readAppLib().sources;

    test('the sweep read a real tree', () {
      expect(
        scanned,
        isNotEmpty,
        reason: 'PROC-10: this file resolves its root from the working '
            'directory, and a root that resolved to nothing would sweep '
            'nothing and pass',
      );
      // ignore: avoid_print
      print('  verdict is not a colour · scanned ${scanned.length} file(s)');
    });

    test('the file it excuses exists, and is the one that draws the ring', () {
      expect(scanned.keys.any((String path) => path.endsWith(_theRing)), isTrue);
    });

    test('only the ring names a verdict and a verdict colour together', () {
      final List<String> offenders = <String>[];
      for (final MapEntry<String, String> file in scanned.entries) {
        if (file.key.endsWith(_theRing)) {
          continue;
        }
        final String code = _codeOf(file.value);
        if (_verdictValue.hasMatch(code) && _verdictColour.hasMatch(code)) {
          offenders.add(file.key);
        }
      }

      expect(offenders, isEmpty);
    });

    test('and the sweep would catch one, both halves having to fire', () {
      const String planted = 'if (v == Verdict.wrong) paint(BrandColorRole.error.color);';
      expect(
        _verdictValue.hasMatch(planted) && _verdictColour.hasMatch(planted),
        isTrue,
      );

      const String innocent = 'paint(BrandColorRole.error.color);';
      expect(
        _verdictValue.hasMatch(innocent) && _verdictColour.hasMatch(innocent),
        isFalse,
        reason: 'one half alone passes for a file that only mentions a colour, '
            'which most of design/ does',
      );

      const String prose = '/// pairing Verdict.correct with BrandColorRole.success is the bug';
      expect(
        _codeOf(prose),
        isNot(contains('Verdict.correct')),
        reason: 'the stripper has to do its job on this file\'s own explanation',
      );
    });
  });
}
