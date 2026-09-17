import 'package:akimath_app/design/icons/brand_icon.dart';
import 'package:akimath_app/features/home/ui/home_screen.dart';
import 'package:akimath_app/features/map/ui/skill_map_screen.dart';
import 'package:akimath_app/features/shell/ui/nav_bar.dart';
import 'package:akimath_app/features/preferences/ui/legend_screen.dart';
import 'package:akimath_app/features/preferences/ui/settings_list_screen.dart';
import 'package:akimath_app/features/profile/ui/profile_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/launch.dart';

/// Walks the shell on a real device: splash, first run, home, all three roots,
/// and the settings stack above one of them.
///
/// **The first run is produced, not hoped for.** This docstring claimed to walk
/// it while the walk sat behind `if (WelcomeScreen … isNotEmpty)`, and the
/// simulator carried the completed flag — so the half of the tour this sentence
/// names had never run. `launchOnAFreshInstall` establishes the state and
/// asserts each screen of `0.2 → 0.3 → 0.4 → 0.7` on the way past.
///
/// It is also what makes the empty-store assertions at the end mean something:
/// `ACIERTOS`, `PROMEDIO` and `HISTORIAL` are absent here because this device
/// has answered nothing that counts, which is now true by construction rather
/// than by whatever the handset was holding.
///
/// **The figures are checked on `Perfil`, not on a root of their own.** `Avance`
/// was invented because the shell needed a second root; no document draws a
/// progress screen, and every line it held is a line `4.1` puts under the
/// identity.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a player can reach every root and the stack above one', (WidgetTester tester) async {
    await launchOnAFreshInstall(tester);

    expect(find.text('Inicio'), findsOneWidget,
        reason: 'the bar exists at all because a second root does');
    expect(find.text('Mapa'), findsOneWidget,
        reason: 'Mapa is on the bar rather than merely built: 05 MAPA and '
            'Detalle de nodo were merged fully tested with nothing that '
            'opened either');
    expect(find.text('Perfil'), findsOneWidget);
    expect(find.text('Ajustes'), findsNothing,
        reason: 'declared rule 1 names the bar\'s homes as inicio, mapa, '
            'progreso y perfil; the third root was labelled after a settings '
            'screen, which that rule does not name');
    expect(find.text('Avance'), findsNothing,
        reason: 'it absorbed into the profile, which is where the design draws '
            'what it held');

    final Finder marks =
        find.descendant(of: find.byType(NavBar), matching: find.byType(BrandIcon));
    expect(marks, findsNWidgets(3),
        reason: 'one mark per root, and a mark that stopped rendering would '
            'leave the labels in place and look like a spacing change');

    await tester.tap(find.text('Mapa'));
    await tester.pumpAndSettle();
    expect(find.byType(SkillMapScreen), findsOneWidget);
    expect(find.byType(NavBar), findsOneWidget, reason: 'a root keeps the bar');

    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsListScreen), findsOneWidget);
    expect(find.byType(NavBar), findsOneWidget,
        reason: 'the bar left with the push, and the group badge over 4.1–4.7 '
            'says it must not: "Aquí sí va la barra inferior"');

    await tester.tap(find.text('Cómo se leen los retos'));
    await tester.pumpAndSettle();
    expect(find.byType(LegendScreen), findsOneWidget);
    expect(find.text('¡Bien hecho!'), findsOneWidget,
        reason: 'the legend\'s own words, which fix-verdict-copy changed from '
            'Acierto and Se torció; this suite kept the old pair for weeks '
            'because nothing ran it');
    expect(find.text('Casi'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Volver'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('Volver'));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsOneWidget);

    expect(find.text('DÍAS'), findsOneWidget,
        reason: 'the wide card reads DÍAS because nothing hands over a rating '
            'any more: GET /me/standing answers one per skill and there is no '
            'single number to print, so the slot falls back to the days '
            'practised rather than to an invented 1 248');
    expect(find.text('RACHA'), findsOneWidget);
    expect(find.text('RETOS'), findsOneWidget);
    expect(find.text('RATING'), findsNothing);
    expect(find.textContaining('esta semana'), findsNothing);

    expect(find.text('ACIERTOS'), findsNothing,
        reason: 'absent, not zero: this device has answered nothing that '
            'counts — the teaching item deliberately records no answer — and '
            '0 % would tell a new player they got everything wrong');
    expect(find.text('PROMEDIO'), findsNothing);
    expect(find.text('HISTORIAL'), findsNothing,
        reason: 'no account on a fresh install, and a HISTORIAL nothing can '
            'ever fill is a promise the product cannot keep while nothing '
            'syncs');

    await tester.tap(find.text('Inicio'));
    await tester.pumpAndSettle();
    expect(find.byType(HomeScreen), findsOneWidget, reason: 'the home lost its state');
  });
}
