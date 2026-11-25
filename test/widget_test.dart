import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukm/app/dashboard.dart';
import 'package:ukm/app/startup.dart';
import 'package:ukm/core/domain.dart';
import 'package:ukm/core/repository.dart';
import 'package:ukm/core/theme.dart';
import 'package:ukm/features/authentication/authentication.dart';
import 'package:ukm/features/production_entry/production.dart';

void main() {
  testWidgets('onboarding explains access, sync, reports and privacy', (
    tester,
  ) async {
    var continued = 0;
    await tester.pumpWidget(
      MaterialApp(home: OnboardingScreen(onContinue: () async => continued++)),
    );
    expect(find.text('Welcome to Unique Knitting Mills'), findsOneWidget);
    expect(find.text('Secure access'), findsOneWidget);
    expect(find.text('Offline storage'), findsOneWidget);
    expect(find.text('PDF reports'), findsOneWidget);
    expect(find.text('Data and privacy'), findsOneWidget);
    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await tester.pump();
    expect(continued, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login shows the two roles and password visibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: const LoginScreen(auth: null),
        theme: millTheme(Brightness.light),
      ),
    );
    expect(find.text('Manager Login'), findsOneWidget);
    expect(find.text('Admin Login'), findsOneWidget);
    final password = find.byType(TextFormField).last;
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: password, matching: find.byType(EditableText)),
          )
          .obscureText,
      isTrue,
    );
    await tester.ensureVisible(find.byTooltip('Show password'));
    await tester.tap(find.byTooltip('Show password'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<EditableText>(
            find.descendant(of: password, matching: find.byType(EditableText)),
          )
          .obscureText,
      isFalse,
    );
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('sign-in-action')))
          .onPressed,
      isNull,
    );
  });

  for (final role in StaffRole.values) {
    for (final size in [const Size(390, 844), const Size(1300, 900)]) {
      testWidgets(
        '${role.label} dashboard at ${size.width}px shows authorized modules',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: millTheme(Brightness.light),
                home: Dashboard(
                  staff: Staff('Test operator', role),
                  logout: () async {},
                  theme: ThemeMode.light,
                  onTheme: (_) {},
                ),
              ),
            ),
          );
          expect(find.text('Mill operations'), findsOneWidget);
          for (final module in Module.values) {
            expect(
              find.text(module.titleFor(role)),
              module.availableTo(role) ? findsWidgets : findsNothing,
            );
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('production job selection unlocks only after date and shift', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          jobsProvider.overrideWith(
            (ref) async => [
              {
                'id': 'test',
                'job_number': 'Test only',
                'party': 'Fixture party',
              },
            ],
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ProductionScreen())),
      ),
    );
    await tester.pumpAndSettle();
    Finder pickJob() => find.ancestor(
      of: find.text('Select job number'),
      matching: find.byType(OutlinedButton),
    );
    expect(tester.widget<OutlinedButton>(pickJob()).onPressed, isNull);
    await tester.tap(find.text('Production date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(pickJob()).onPressed, isNull);
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    expect(tester.widget<OutlinedButton>(pickJob()).onPressed, isNotNull);
    await tester.tap(pickJob());
    await tester.pumpAndSettle();
    expect(find.text('Test only · Fixture party'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
