import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/theme.dart';
import 'package:akimath_app/features/onboarding/ui/calibration_intro_screen.dart';
import 'package:akimath_app/features/shell/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  VoidCallback? onStart,
  VoidCallback? onSkip,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AkiMathTheme.build(),
      home: AppShell(
        child: CalibrationIntroScreen(
          onStart: onStart ?? () {},
          onSkip: onSkip ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it says what the probe is for, in the design\'s words',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.textContaining('ACOMODAR TU NIVEL'), findsOneWidget);
    expect(
      find.text(
        'Diez como máximo. Sirven para que los retos lleguen a tu medida, '
        'nada más.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('it promises both of the things the design promises',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('No se califica'), findsOneWidget);
    expect(find.text('Se puede saltar'), findsOneWidget);
  });

  testWidgets('it never uses the word "prueba"', (WidgetTester tester) async {
    await _pump(tester);

    final Iterable<String> copy = tester
        .widgetList<Text>(find.byType(Text))
        .map((Text text) => (text.data ?? '').toLowerCase());

    expect(copy.where((String line) => line.contains('prueba')), isEmpty);
  });

  testWidgets('Aki is here, because nobody is solving yet',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.byType(Aki), findsOneWidget);
  });

  testWidgets('the green button starts the probe and nothing else',
      (WidgetTester tester) async {
    int started = 0;
    int skipped = 0;
    await _pump(tester, onStart: () => started++, onSkip: () => skipped++);

    await tester.tap(find.text('Va, empecemos'));
    await tester.pumpAndSettle();

    expect(started, 1);
    expect(skipped, 0);
  });

  testWidgets('the quiet one leaves it, and does not start it',
      (WidgetTester tester) async {
    int started = 0;
    int skipped = 0;
    await _pump(tester, onStart: () => started++, onSkip: () => skipped++);

    await tester.tap(find.text('Saltar por ahora'));
    await tester.pumpAndSettle();

    expect(skipped, 1);
    expect(started, 0);
  });
}
