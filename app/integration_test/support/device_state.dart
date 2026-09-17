import 'package:akimath_app/features/account/data/player_id_store.dart';
import 'package:akimath_app/features/account/data/session_store.dart';
import 'package:akimath_app/features/home/data/prefs_day_log_store.dart';
import 'package:akimath_app/features/home/data/series_cursor_store.dart';
import 'package:akimath_app/features/home/policy/day_log.dart';
import 'package:akimath_app/features/map/data/practised_step_store.dart';
import 'package:akimath_app/features/onboarding/data/onboarding_store.dart';
import 'package:akimath_app/features/preferences/data/prefs_settings_stores.dart';
import 'package:akimath_app/features/preferences/policy/accessibility_settings.dart';
import 'package:akimath_app/features/preferences/policy/notification_settings.dart';
import 'package:akimath_app/features/preferences/policy/sound_settings.dart';
import 'package:akimath_app/features/states/data/streak_notice_store.dart';
import 'package:akimath_app/features/stats/data/answer_record_store.dart';
import 'package:akimath_app/features/sync/data/attempt_journal_store.dart';
import 'package:akimath_app/features/sync/data/issued_pack_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What a suite requires of the device before the app launches.
///
/// **A suite establishes this; it never discovers it.** Every Tier 2 suite used
/// to open with `if (find.byType(WelcomeScreen).evaluate().isNotEmpty)` and take
/// whichever branch the simulator happened to be in. On a handset carrying
/// `akimath.onboarding_complete.v1` that branch never ran, so
/// `playthrough_test`'s *"a fresh install plays through to a finished series"*
/// asserted a fresh install it had never produced and silently skipped the half
/// of itself that says so — a block of assertions testing nothing, in a project
/// where the suite is the evidence. The same device also carried a day log five
/// days stale, which stood `Racha perdida` between the launch and the home
/// and failed four of the six suites at once.
///
/// **Two facts vary, so this type carries two.** A general seeder keyed on
/// arbitrary preference names would be arms nothing exercises (PROC-11) around
/// a registry with one live entry (PROC-10). The three states below cover all
/// six suites; a fourth is added the day a seventh needs it. Everything else a
/// store keeps is reset to what a fresh install reads, because a state is only
/// established if the rest of the device is too.
class DeviceState {
  const DeviceState._({
    required this.onboardingComplete,
    required this.practised,
  });

  /// Nothing has been kept. A launch opens `Bienvenida`.
  static const DeviceState freshInstall = DeviceState._(
    onboardingComplete: false,
    practised: DayLog.empty,
  );

  /// The first run is behind the player and nothing has been practised. A
  /// launch opens the home, with no streak notice over it: an empty log is
  /// `StreakState.none`, so there is no run to be at risk or to have broken.
  static const DeviceState returningPlayer = DeviceState._(
    onboardingComplete: true,
    practised: DayLog.empty,
  );

  /// A returning player whose run of [length] days ended on [last].
  ///
  /// The two streak screens are reached by what is on disk and what time it is,
  /// so a suite about them names the run rather than assembling days inline.
  static DeviceState playedRunEnding(DateTime last, {required int length}) {
    DayLog log = DayLog.empty;
    for (int back = length - 1; back >= 0; back--) {
      log = log.recording(DateTime(last.year, last.month, last.day - back));
    }
    return DeviceState._(onboardingComplete: true, practised: log);
  }

  final bool onboardingComplete;

  final DayLog practised;
}

/// Puts the device into [state], and verifies it landed.
///
/// **Every key is written, and none is removed, because removal does not work
/// here.** Measured on an iPhone 17 simulator under
/// `flutter test integration_test`, six ways: `SharedPreferencesAsync.clear()`,
/// `clear(allowList: …)` and `remove(key)` all return normally and change
/// nothing for a key that was already on disk when the process started —
/// `getString` keeps answering the old value, immediately, a second later, and
/// after a second attempt. `getKeys()` compounds it by reporting `{}` while
/// `com.akimath.akimathApp.plist` still holds ten entries, so the reset *looks*
/// like it worked. (A key created inside the same process does remove
/// correctly, which is how this hid for so long.) `set` is exact, so this
/// writes.
///
/// That is why `streak_notice_tour_test`'s `prefs.clear()` was never doing
/// anything: it only ever added days on top, so nothing it asserted could tell.
///
/// **The empty string is what stands in for a removal.** Each of the stores
/// swept below reads one as nothing kept, which is exactly what removing the
/// key would have produced if removing worked.
///
/// **Through the app's own stores and their own keys.** A suite spelling
/// `'akimath.onboarding_complete.v1'` by hand is a second declaration of a name
/// the app owns; the settings are reset by handing each store its own
/// `defaults`, so no default is copied here to go stale.
///
/// **Read back, because the stores swallow their write errors.**
/// `OnboardingStore.markComplete` reports a failure to `debugPrint` and returns
/// normally, so an unwritten flag would otherwise surface far away, as a suite
/// standing on the welcome screen wondering where the home went. The read-back
/// is what caught the removal problem above.
///
/// Call it per test case and never from a `setUpAll`: the cases share one app
/// process, and solving a board in the first writes answered items and
/// practised steps the second would inherit.
Future<void> establish(DeviceState state) async {
  final SharedPreferencesAsync preferences = SharedPreferencesAsync();

  await preferences.setBool(OnboardingStore.key, state.onboardingComplete);
  await preferences.setString(PrefsDayLogStore.key, state.practised.encode());
  await preferences.setInt(SeriesCursorStore.key, 0);

  for (final String key in <String>[
    PrefsStreakNoticeStore.key,
    PrefsSessionStore.key,
    PrefsPlayerIdStore.key,
    PrefsAnswerRecordStore.key,
    PrefsPractisedStepStore.key,
    PrefsIssuedPackStore.key,
    PrefsAttemptJournalStore.key,
  ]) {
    await preferences.setString(key, '');
  }

  await const PrefsNotificationSettingsStore()
      .write(NotificationSettings.defaults);
  await const PrefsAccessibilitySettingsStore()
      .write(AccessibilitySettings.defaults);
  await const PrefsSoundSettingsStore().write(SoundSettings.defaults);

  await _verify(state);
}

/// Reads the device back through the app's own adapters.
///
/// Not through `SharedPreferencesAsync`: what matters is not that a key holds a
/// string, it is that the store above it answers the way a fresh install makes
/// it answer.
///
/// **The accessibility settings are read back because they steer what every
/// other suite measures.** The handset carried `text_size` at step 1 and
/// `reduce_motion` on, so every Tier 2 run before this change was measuring
/// layout at a text size nobody chose. `PreferenceValues.putInt` swallows its
/// failures like every other adapter here, so a write that did not land would
/// put that back invisibly.
Future<void> _verify(DeviceState state) async {
  expect(
    await const OnboardingStore().isComplete(),
    state.onboardingComplete,
    reason: 'the onboarding flag did not reach the device',
  );
  expect(
    (await const PrefsDayLogStore().read()).days,
    state.practised.days,
    reason: 'the day log did not reach the device',
  );
  expect(
    await const SeriesCursorStore().read(),
    0,
    reason: 'the series cursor did not reach the device',
  );
  expect(
    await const PrefsStreakNoticeStore().lostShownOn(),
    isNull,
    reason: 'a page turn from an earlier run is still recorded',
  );
  expect(
    await const PrefsSessionStore().read(),
    isNull,
    reason: 'a session from an earlier run is still on the device',
  );
  expect(
    await const PrefsAnswerRecordStore().read(),
    isEmpty,
    reason: 'answers from an earlier run are still on the device',
  );
  expect(
    await const PrefsPractisedStepStore().read(),
    isEmpty,
    reason: 'practised steps from an earlier run are still on the device',
  );
  expect(
    await const PrefsIssuedPackStore().read(),
    isNull,
    reason: 'an issued pack from an earlier run is still on the device',
  );
  expect(
    await const PrefsAttemptJournalStore().read(),
    isEmpty,
    reason: 'a journal from an earlier run is still on the device',
  );
  expect(
    await const PrefsAccessibilitySettingsStore().read(),
    AccessibilitySettings.defaults,
    reason: 'the accessibility settings did not reach the device',
  );
}
