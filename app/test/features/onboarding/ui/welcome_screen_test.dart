import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/widgets/speech_bubble.dart';
import 'package:akimath_app/features/onboarding/ui/welcome_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(WidgetTester tester, {VoidCallback? onStart}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: WelcomeScreen(onStart: onStart ?? () {})),
    ),
  );
}

void main() {
  group('the welcome screen greets and offers one thing', () {
    testWidgets('Aki, a bubble and one action', (WidgetTester tester) async {
      await _pump(tester);

      expect(find.byType(Aki), findsOneWidget);
      expect(find.byType(SpeechBubble), findsOneWidget);
      expect(find.text('Resolver uno'), findsOneWidget);
    });

    testWidgets('the action reports once', (WidgetTester tester) async {
      int starts = 0;
      await _pump(tester, onStart: () => starts++);

      await tester.tap(find.text('Resolver uno'));
      await tester.pump();

      expect(starts, 1);
    });
  });

  group('no account is asked for', () {
    testWidgets('there is no text field of any kind',
        (WidgetTester tester) async {
      await _pump(tester);

      expect(find.byType(EditableText), findsNothing);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('nothing asks for an email, a password or an account',
        (WidgetTester tester) async {
      await _pump(tester);

      final String copy = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => (t.data ?? '').toLowerCase())
          .join(' ');

      for (final String word in <String>[
        'correo',
        'email',
        'contraseña',
        'cuenta',
        'registr',
      ]) {
        expect(copy, isNot(contains(word)), reason: '"$word" is on 0.2');
      }
    });
  });

  group('the promise to adapt belongs to 0.4, not to the greeting', () {
    testWidgets('it does not mention levels or calibration',
        (WidgetTester tester) async {
      await _pump(tester);

      final String copy = tester
          .widgetList<Text>(find.byType(Text))
          .map((Text t) => (t.data ?? '').toLowerCase())
          .join(' ');

      for (final String word in <String>['nivel', 'acomodar', 'calibra']) {
        expect(
          copy,
          isNot(contains(word)),
          reason: '"$word" is 0.4\'s promise, made two screens early on 0.2',
        );
      }
    });
  });
}
