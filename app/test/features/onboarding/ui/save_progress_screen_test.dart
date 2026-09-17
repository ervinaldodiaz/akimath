import 'package:akimath_app/design/brand/aki.dart';
import 'package:akimath_app/design/theme.dart';
import 'package:akimath_app/features/onboarding/ui/save_progress_screen.dart';
import 'package:akimath_app/features/shell/ui/app_shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pump(
  WidgetTester tester, {
  int challenges = 6,
  int days = 1,
  VoidCallback? onCreateAccount,
  VoidCallback? onLater,
}) async {
  tester.view
    ..physicalSize = const Size(390, 844)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AkiMathTheme.build(),
      home: AppShell(
        child: SaveProgressScreen(
          challenges: challenges,
          days: days,
          onCreateAccount: onCreateAccount,
          onLater: onLater ?? () {},
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('it asks the design\'s question', (WidgetTester tester) async {
    await _pump(tester, onCreateAccount: () {});

    expect(find.text('¿TE LO GUARDO?'), findsOneWidget);
  });

  testWidgets('the retos and the día are what the caller measured',
      (WidgetTester tester) async {
    await _pump(tester, challenges: 6, days: 1, onCreateAccount: () {});

    expect(find.text('6'), findsOneWidget);
    expect(find.text('RETOS'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('DÍA'), findsOneWidget);
  });

  testWidgets('and they change with the figures handed in',
      (WidgetTester tester) async {
    await _pump(tester, challenges: 3, days: 12, onCreateAccount: () {});

    expect(find.text('3'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('DÍAS'), findsOneWidget);
  });

  testWidgets('the design\'s middle tile is absent, because nothing fills it',
      (WidgetTester tester) async {
    await _pump(tester, onCreateAccount: () {});

    expect(find.textContaining('RATING'), findsNothing);
  });

  testWidgets('the row shrinks to the figures there are, down to one',
      (WidgetTester tester) async {
    await _pump(tester, challenges: 11, days: 0, onCreateAccount: () {});

    expect(find.text('RETOS'), findsOneWidget);
    expect(find.text('11'), findsOneWidget);
    expect(find.textContaining('DÍA'), findsNothing);
    expect(find.textContaining('RATING'), findsNothing);
  });

  testWidgets('it says what happens if the player does nothing',
      (WidgetTester tester) async {
    await _pump(tester, onCreateAccount: () {});

    expect(
      find.text('Si cierras la app sin cuenta, esto se queda en este teléfono.'),
      findsOneWidget,
    );
  });

  testWidgets('Aki is at rest here, because nothing is being solved',
      (WidgetTester tester) async {
    await _pump(tester, onCreateAccount: () {});

    expect(tester.widget<Aki>(find.byType(Aki)).pose, AkiPose.base);
  });

  testWidgets('the green button asks for an account', (WidgetTester tester) async {
    int asked = 0;
    int later = 0;
    await _pump(
      tester,
      onCreateAccount: () => asked++,
      onLater: () => later++,
    );

    await tester.tap(find.text('Crear cuenta'));
    await tester.pumpAndSettle();

    expect(asked, 1);
    expect(later, 0);
  });

  testWidgets('and the quiet one moves on', (WidgetTester tester) async {
    int asked = 0;
    int later = 0;
    await _pump(
      tester,
      onCreateAccount: () => asked++,
      onLater: () => later++,
    );

    await tester.tap(find.text('Después'));
    await tester.pumpAndSettle();

    expect(later, 1);
    expect(asked, 0);
  });

  testWidgets('no days practised is no tile, not a tile reading zero',
      (WidgetTester tester) async {
    await _pump(tester, days: 0, onCreateAccount: () {});

    expect(find.text('DÍA'), findsNothing);
    expect(find.text('DÍAS'), findsNothing);
    expect(find.text('RETOS'), findsOneWidget);
  });

  testWidgets('with no account flow wired, it offers nothing it cannot do',
      (WidgetTester tester) async {
    await _pump(tester);

    expect(find.text('Crear cuenta'), findsNothing);
    expect(find.text('Después'), findsOneWidget);
  });
}
