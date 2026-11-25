import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukm/app/dashboard.dart';
import 'package:ukm/app/startup.dart';
import 'package:ukm/core/domain.dart';
import 'package:ukm/core/repository.dart';
import 'package:ukm/core/theme.dart';
import 'package:ukm/features/authentication/authentication.dart';
import 'package:ukm/features/job_entry/jobs.dart';
import 'package:ukm/features/production_entry/production.dart';

class _ProductionFixture implements MillData {
  final entries = <Shift, Map<String, Object?>>{};
  List<RowData> savedPrograms = [];

  @override
  Stream<int> get updates => const Stream.empty();

  @override
  Future<List<RowData>> jobs() async => [
    {'id': 'test', 'job_number': 'QA-024', 'party': 'Fixture party'},
  ];

  @override
  Future<List<RowData>> names(String table) async => [];

  @override
  Future<RowData> productionSheet(
    String jobId,
    DateTime date,
    Shift shift,
  ) async => {
    'job': (await jobs()).single,
    'programs': [
      for (final dia in [24, 26, 30])
        {
          'id': '$dia',
          'dia': dia,
          'position': 1,
          'ordered_kg': 100,
          'previous_kg': 0,
          'specification': 'Herringbone $dia',
          'loop_length': 2.5,
          'shift_kg': entries[shift]?['$dia'],
        },
    ],
  };

  @override
  Future<void> saveProduction(
    String jobId,
    DateTime date,
    Shift shift,
    List<RowData> lines,
  ) async {
    entries[shift] = {
      for (final line in lines)
        line['program_id'] as String: line['quantity_kg'],
    };
  }

  @override
  Future<void> saveJob({
    RowData? existing,
    required DateTime date,
    required String number,
    required String party,
    required String yarn,
    required List<RowData> programs,
  }) async {
    savedPrograms = programs;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

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

  testWidgets('day and night entries send all three DIAs separately', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1250);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _ProductionFixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localRepositoryProvider.overrideWithValue(store)],
        child: const MaterialApp(home: Scaffold(body: ProductionScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Production date'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Day'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select job number'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('QA-024 · Fixture party'));
    await tester.pumpAndSettle();

    for (final shift in Shift.values) {
      if (shift == Shift.night) {
        await tester.ensureVisible(find.text('Night'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Night'));
        await tester.pumpAndSettle();
      }
      for (final dia in [24, 26, 30]) {
        expect(find.text('DIA $dia'), findsOneWidget);
        expect(find.text('Program 1 · Herringbone $dia'), findsOneWidget);
      }
      final inputs = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.controller != null &&
            widget.controller!.text.isEmpty,
      );
      expect(
        find.text('${shift.label} Shift Production (KG)'),
        findsNWidgets(3),
      );
      expect(inputs, findsNWidgets(3));
      final fields = find.byType(TextFormField);
      final quantities = shift == Shift.morning ? [1, 2, 3] : [4, 5, 6];
      for (final (index, value) in quantities.indexed) {
        final input = fields.at(index);
        await tester.ensureVisible(input);
        await tester.enterText(input, '$value');
      }
      final save = find.text('Confirm production');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        store.entries[shift]!.values.map(grams).toList(),
        quantities.map((value) => value * 1000).toList(),
      );
    }
    expect(store.entries[Shift.morning]!.keys, ['24', '26', '30']);
    expect(store.entries[Shift.night]!.keys, ['24', '26', '30']);
  });

  testWidgets('Others requires and saves the entered design name', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 1000);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = _ProductionFixture();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localRepositoryProvider.overrideWithValue(store)],
        child: const MaterialApp(home: Scaffold(body: JobsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New job'));
    await tester.pumpAndSettle();
    final design = find.byType(DropdownButtonFormField<String>).first;
    await tester.ensureVisible(design);
    await tester.tap(design);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Others').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter Design Name'), findsOneWidget);
    for (final (label, value) in [
      ('Job number', 'CUSTOM-024'),
      ('Party name', 'Fixture party'),
      ('Yarn details', 'Cotton'),
      ('Loop length', '2.5'),
      ('Quantity (kg)', '50'),
    ]) {
      final field = find
          .byWidgetPredicate(
            (widget) =>
                widget is TextField && widget.decoration?.labelText == label,
          )
          .first;
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
    }
    final dia = find.byType(DropdownButtonFormField<int>).first;
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(dia), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(dia);
    await tester.pumpAndSettle();
    await tester.tap(find.text('24').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save job'));
    await tester.pumpAndSettle();
    expect(store.savedPrograms, isEmpty);
    final custom = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Enter Design Name',
    );
    await tester.ensureVisible(custom);
    await tester.enterText(custom, 'Mill Herringbone');
    await tester.tap(find.text('Save job'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(store.savedPrograms.single['specification'], 'Mill Herringbone');
  });
}
