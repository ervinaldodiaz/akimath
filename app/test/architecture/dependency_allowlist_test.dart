import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The runtime packages `app/` is allowed to ship.
///
/// This list is the contract. Adding a package means editing this line **and**
/// carrying the `CLAUDE.md`:9 phones-home audit in the same change — which is
/// the point: the test cannot judge whether a dependency collects data, so it
/// fails on *any* addition and summons a human who can.
///
/// R5's early signal is a pull request touching `pubspec.yaml` when the task did
/// not ask for it. This turns that from a review habit into a red build.
const Set<String> allowedRuntimeDependencies = <String>{
  'flutter',
  'cupertino_icons',
  'meta',

  // Added 2026-08-16, decided by Ervin. The day log's storage: Flutter exposes
  // no writable path without a plugin, and a streak that resets on every
  // launch is not a streak.
  //
  // **DEP-1 audit, performed before the addition and recorded here because the
  // rule requires it in the same change:**
  // · Published at github.com/flutter/packages — the Flutter team's own
  //   monorepo. Verified from the resolved package's `repository:` field, for
  //   the federated implementations as well as the facade.
  // · It wraps `NSUserDefaults` on iOS and `SharedPreferences` on Android. It
  //   stores one string under one key, on the device.
  // · **It makes no network request.** Verified by grepping the shipped Dart of
  //   the facade, the platform interface and both mobile implementations for
  //   `HttpClient`, `package:http`, `Socket` and `WebSocket`: zero files.
  // · It collects nothing and reports nothing. There is no identifier, no
  //   analytics hook and no remote configuration in it.
  //
  // It brings six federated packages with it — `_android`, `_foundation`,
  // `_linux`, `_platform_interface`, `_web`, `_windows` — all from the same
  // monorepo, and only the host platform's implementation compiles in.
  'shared_preferences',

  // Added 2026-08-20, decided by Ervin. The offline membership verifier:
  // `ARCHITECTURE.md` §4 says the pack states a **digest**, never the answer,
  // so a child's device can tell right from wrong offline without carrying the
  // answer in readable bytes. Reading a pack the server issued means computing
  // `HMAC-SHA256(pack_salt, canonical answer)`, and there is no way round it —
  // the server must never learn an authored answer, and without a local
  // verifier a player gets no verdict until they sync.
  //
  // `content/model/pack.dart` had recorded the blocker in its own doc comment
  // since F1: *"reading it needs an HMAC implementation, which needs a
  // dependency this project has not decided on."* This is that decision.
  //
  // **DEP-1 audit, performed before the addition and recorded here because the
  // rule requires it in the same change:**
  // · `crypto 3.0.7`, published by **dart.dev** — the Dart team's own package,
  //   at github.com/dart-lang/crypto. Verified from the resolved package's
  //   `repository:` field.
  // · Pure Dart. It is hash and MAC algorithms operating on byte lists: no
  //   plugin, no platform channel, no native code.
  // · **It makes no network request.** Verified by grepping the shipped Dart
  //   for `HttpClient`, `package:http`, `Socket`, `WebSocket` and `dart:io`:
  //   zero files.
  // · It collects nothing and reports nothing. No identifier, no analytics
  //   hook, no remote configuration.
  // · One dependency of its own, `typed_data`, also from the Dart team.
  //
  // **Two packages net-new to the shipping set.** It was already resolved in
  // the tree but only for development, through `dart_code_linter` and
  // `analyzer`, so this is the first time it compiles into the app. For
  // comparison, ADR 0001 turned `swagger_dart_code_generator` down at fourteen
  // — for a job this project could hand-write. This is a primitive CLAUDE.md's
  // own rule says not to hand-write.
  'crypto',
};

/// Whether [line] opens a top-level key, which is what ends a block.
///
/// An unindented, non-empty, non-comment line is the only thing that closes
/// `dependencies:` — which is what keeps `dev_dependencies:` out of the scan.
bool _opensATopLevelKey(String line) =>
    line.isNotEmpty && !line.startsWith(' ') && !line.startsWith('#');

/// Reads the `dependencies:` block of `app/pubspec.yaml`.
///
/// A hand parse rather than a YAML package, because adding a YAML package to
/// read the dependency list would be its own punchline. The block is flat and
/// two levels deep; anything more elaborate belongs in a real parser and would
/// be a reason to revisit this.
///
/// **`dev_dependencies:` is out of scope, and deliberately.** They do not ship,
/// so DEP-1 does not reach them; sweeping them in would make the gate fire on
/// every test-tooling bump and get it disabled within a week.
Set<String> _declaredRuntimeDependencies(String yaml) {
  final List<String> lines = yaml.split('\n');
  final Set<String> found = <String>{};

  bool inDependencies = false;
  for (final String line in lines) {
    if (line.startsWith('dependencies:')) {
      inDependencies = true;
      continue;
    }
    if (inDependencies) {
      if (_opensATopLevelKey(line)) {
        break;
      }
      final RegExpMatch? match =
          RegExp(r'^  ([a-z0-9_]+):').firstMatch(line);
      if (match != null) {
        found.add(match.group(1)!);
      }
    }
  }
  return found;
}

void main() {
  group('the runtime dependency list is a committed allowlist', () {
    test('no icon dependency is added', () {
      final String yaml = File('pubspec.yaml').readAsStringSync();
      final Set<String> declared = _declaredRuntimeDependencies(yaml);

      expect(
        declared,
        allowedRuntimeDependencies,
        reason: 'app/pubspec.yaml declares a runtime dependency the allowlist '
            'does not. Adding one means editing the allowlist AND auditing '
            'whether the package phones home, in the same change (DEP-1).',
      );
    });

    test('it reports what it scanned, and scanning nothing is a failure', () {
      final String yaml = File('pubspec.yaml').readAsStringSync();
      final Set<String> declared = _declaredRuntimeDependencies(yaml);

      expect(
        declared,
        isNotEmpty,
        reason: 'the parser matched no package. One typo in the block name '
            'makes this gate permanently green, which is the one failure mode '
            'it cannot have.',
      );
      // ignore: avoid_print
      print('  dependency allowlist · runtime → ${declared.length} packages');
    });

    test('an added dependency is named, against a manifest that is not on disk',
        () {
      const String withExtra = '''
name: akimath_app

dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  meta: ^1.17.0
  some_analytics_sdk: ^2.0.0

dev_dependencies:
  flutter_test:
    sdk: flutter
''';

      final Set<String> declared = _declaredRuntimeDependencies(withExtra);
      expect(declared.difference(allowedRuntimeDependencies), <String>{
        'some_analytics_sdk',
      });
    });

    test('dev dependencies are out of scope, because they do not ship', () {
      const String yaml = '''
dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_lints: ^6.0.0
  mocktail: ^1.0.0
''';

      expect(_declaredRuntimeDependencies(yaml), <String>{'flutter'});
    });
  });
}
