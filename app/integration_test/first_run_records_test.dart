import 'package:akimath_app/features/profile/ui/profile_route.dart';
import 'package:akimath_app/features/stats/data/answer_record_store.dart';
import 'package:akimath_app/features/stats/policy/local_stats.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/launch.dart';

/// What the first run leaves behind on a real device.
///
/// **The one suite that answers a probe item.** `launchOnAFreshInstall` skips
/// `0.5` for every other suite, so until this existed nothing on a device had
/// ever submitted a probe answer — and the widget suite runs against
/// `InMemorySharedPreferencesAsync`, so nothing anywhere had watched the real
/// plugin take one. That is the gap the probe's missing recorder lived in.
///
/// **It walks all the way to `4.1 Perfil`**, because the claim is not that a
/// store was called: it is that the figure a player reads changes. `RETOS`
/// already moved with the probe, through the series cursor; `ACIERTOS` did not,
/// and a screen showing the first without the second is what this asserts is
/// over.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the probe reaches the record, and Perfil prints it',
      (WidgetTester tester) async {
    await _restoreTheAnswerRecordAfterwards();

    await launchAndPlayTheProbe(tester, answers: 3);

    final List<AnsweredItem> record =
        await const PrefsAnswerRecordStore().read();
    expect(
      record,
      hasLength(3),
      reason: 'read through the shipping store on the shipping plugin: three '
          'probe items were answered and the device kept ${record.length}',
    );
    final LocalStats stats = LocalStats.of(record);
    expect(stats.answered, 3);
    expect(
      stats.accuracyPercent,
      isNotNull,
      reason: 'a player who answered three items has an accuracy',
    );
    expect(
      stats.meanTime,
      isNotNull,
      reason: 'and a mean time, measured per item by 0.5',
    );

    await tester.tap(find.text('Entrar a mi mapa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Después'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Perfil'));
    await tester.pumpAndSettle();

    expect(find.byType(ProfileRoute), findsOneWidget);
    expect(
      find.text('ACIERTOS'),
      findsOneWidget,
      reason: 'Perfil counted the probe as RETOS and not as ACIERTOS. The tile, '
          'not the number: what the probe changed is that the figure has a '
          'source at all, profileTiles drops a tile whose figure is null, and '
          'LocalStats above pins the value.',
    );
    expect(find.text('PROMEDIO'), findsOneWidget);
  });
}

/// Captures the device's answer record and puts it back when the case ends.
///
/// **Annihilate what a run writes** (TEST-2). `establish` clears the key on the
/// way in; this restores whatever the handset was holding, because a Tier 2 run
/// has already overwritten a device's `akimath.day_log.v1` without capturing it
/// once, and that is the rule the fourth A exists for.
Future<void> _restoreTheAnswerRecordAfterwards() async {
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();
  final String? before =
      await preferences.getString(PrefsAnswerRecordStore.key);
  addTearDown(
    () => preferences.setString(PrefsAnswerRecordStore.key, before ?? ''),
  );
}
