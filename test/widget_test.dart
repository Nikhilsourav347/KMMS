import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ukm/app/dashboard.dart';
import 'package:ukm/app/startup.dart';
import 'package:ukm/core/domain.dart';
import 'package:ukm/core/auth.dart';
import 'package:ukm/core/repository.dart';
import 'package:ukm/core/theme.dart';
import 'package:ukm/core/widgets.dart';
import 'package:ukm/features/authentication/authentication.dart';
import 'package:ukm/features/job_entry/jobs.dart';
import 'package:ukm/features/production_entry/production.dart';
import 'package:ukm/features/reports/reports.dart';

class _ProductionFixture implements MillData {
  final entries = <Shift, Map<String, Object?>>{};
  final registryChanges = StreamController<int>.broadcast();
  final dias = ['24', '26', '30A', '30A'];
  List<RowData> savedPrograms = [];
  final reportCalls = <(DateTime?, DateTime?, String?, String?, String?)>[];

  @override
  Stream<int> updates(Dataset dataset) => dataset == Dataset.machines
      ? registryChanges.stream
      : const Stream.empty();

  @override
  Future<List<RowData>> registeredMachines() async => [
    for (final dia in dias) {'dia': dia},
  ];

  @override
  Future<List<RowData>> jobs() async => [
    {'id': 'test', 'job_number': 'QA-024', 'party': 'Fixture party'},
  ];

  @override
  Future<List<RowData>> names(String table) async => [
    if (table == 'parties') {'id': 'party-1', 'name': 'Fixture party'},
  ];

  @override
  Future<List<String>> reportDias(DateTime start, DateTime end) async => [
    '19RIB',
  ];

  @override
  Future<RowData> report({
    DateTime? start,
    DateTime? end,
    Shift? shift,
    String? jobId,
    String? partyId,
    String? dia,
  }) async {
    reportCalls.add((start, end, jobId, partyId, dia));
    return {'entries': [], 'programs': [], 'days': []};
  }

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
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('first launch retries the backend and opens staff sign-in', (
    tester,
  ) async {
    var attempts = 0;
    final backend = _StartupBackend();
    await tester.pumpWidget(
      MillApp(
        openBackend: () async {
          if (++attempts == 1) throw const MillError('Connection failed.');
          return backend;
        },
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Connection failed.'), findsOneWidget);
    await tester.tap(find.text('Retry connection'));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.text('Create administrator'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final role in StaffRole.values) {
    testWidgets(
      'restores ${role.label} session and returns to sign-in on logout',
      (tester) async {
        final backend = _StartupBackend();
        backend.auth.currentStaff = Staff('Fixture', role);
        await tester.pumpWidget(MillApp(openBackend: () async => backend));
        await tester.pumpAndSettle();
        expect(
          tester.widget<Dashboard>(find.byType(Dashboard)).staff.role,
          role,
        );
        await backend.auth.signOut();
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );
  }

  testWidgets('recovery session opens password reset and returns to sign-in', (
    tester,
  ) async {
    final backend = _StartupBackend();
    backend.auth.isPasswordRecovery = true;
    await tester.pumpWidget(MillApp(openBackend: () async => backend));
    await tester.pumpAndSettle();
    expect(find.byType(PasswordRecoveryScreen), findsOneWidget);
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'new-test-password');
    await tester.enterText(fields.last, 'new-test-password');
    final reset = find.widgetWithText(FilledButton, 'Reset Password');
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('login shows the two roles and password visibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(auth: _StartupAuth()),
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
      isNotNull,
    );
  });

  testWidgets('wrong password stays on login and recovery requests a link', (
    tester,
  ) async {
    final auth = _StartupAuth();
    await tester.pumpWidget(MaterialApp(home: LoginScreen(auth: auth)));
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.first, 'fixture@example.invalid');
    await tester.enterText(fields.last, 'wrong password');
    final signIn = find.byKey(const ValueKey('sign-in-action'));
    await tester.ensureVisible(signIn);
    await tester.tap(signIn);
    await tester.pumpAndSettle();
    expect(
      find.text('The email address or password is incorrect.'),
      findsOneWidget,
    );
    final forgot = find.text('Forgot password?');
    await tester.ensureVisible(forgot);
    await tester.tap(forgot);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send recovery link'));
    await tester.pumpAndSettle();
    expect(auth.recoveryEmail, 'fixture@example.invalid');
    expect(find.textContaining('one-time code'), findsOneWidget);
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
          expect(find.text('Machine Operations'), findsOneWidget);
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
        overrides: [millDataProvider.overrideWithValue(store)],
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
        overrides: [millDataProvider.overrideWithValue(store)],
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
    final dia = find.text('Select DIA').first;
    await tester.pumpAndSettle();
    await Scrollable.ensureVisible(tester.element(dia), alignment: .5);
    await tester.pumpAndSettle();
    await tester.tap(dia);
    await tester.pumpAndSettle();
    expect(find.text('30A'), findsOneWidget);
    await tester.tap(find.text('30A'));
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
    expect(store.savedPrograms.single['dia'], '30A');
  });

  testWidgets('open job editor gets active DIA additions, edits and removals', (
    tester,
  ) async {
    final store = _ProductionFixture();
    addTearDown(store.registryChanges.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [millDataProvider.overrideWithValue(store)],
        child: const MaterialApp(home: Scaffold(body: JobsScreen())),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('New job'));
    await tester.pumpAndSettle();
    final picker = find.text('Select DIA').first;
    await tester.ensureVisible(picker);
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('30A'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    store.dias
      ..remove('24')
      ..remove('30A')
      ..addAll(['6', '76RIB']);
    store.registryChanges.add(1);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    expect(find.text('24'), findsNothing);
    expect(find.text('30A'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('76RIB'), findsOneWidget);
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();

    store.dias.clear();
    store.registryChanges.add(2);
    await tester.pumpAndSettle();
    expect(
      find.text('No active machines with a DIA are registered.'),
      findsOneWidget,
    );
  });

  for (final (scope, useDia) in [
    ('All Jobs and Parties', false),
    ('Filter by Job Number', false),
    ('Filter by Party Name', false),
    ('All Jobs and Parties', true),
    ('Filter by Job Number', true),
    ('Filter by Party Name', true),
  ]) {
    testWidgets('date-range report accepts $scope with DIA filter $useDia', (
      tester,
    ) async {
      final store = _ProductionFixture();
      addTearDown(store.registryChanges.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [millDataProvider.overrideWithValue(store)],
          child: const MaterialApp(home: Scaffold(body: ReportsScreen())),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Date range'));
      await tester.pumpAndSettle();
      expect(find.text('All DIA'), findsOneWidget);
      expect(find.textContaining('From Date'), findsOneWidget);
      expect(find.textContaining('To Date'), findsOneWidget);
      await tester.tap(find.text(scope));
      await tester.pumpAndSettle();

      if (scope == 'Filter by Job Number') {
        await tester.tap(find.text('Select job number'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('QA-024'));
        await tester.pumpAndSettle();
        expect(find.text('Party · Fixture party'), findsOneWidget);
        expect(find.text('Select party name'), findsNothing);
      }
      if (scope == 'Filter by Party Name') {
        await tester.tap(find.text('Select party name'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Fixture party'));
        await tester.pumpAndSettle();
        expect(find.text('Select job number'), findsNothing);
      }
      if (useDia) {
        await tester.tap(find.text('All DIA'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('19RIB'));
        await tester.pumpAndSettle();
      }

      final generate = find.text('Generate PDF');
      await tester.ensureVisible(generate);
      await tester.tap(generate);
      await tester.pumpAndSettle();
      final (start, end, job, party, dia) = store.reportCalls.single;
      expect(start, indiaToday());
      expect(end, indiaToday());
      expect(job, scope == 'Filter by Job Number' ? 'test' : null);
      expect(party, scope == 'Filter by Party Name' ? 'party-1' : null);
      expect(dia, useDia ? '19RIB' : null);
      expect(
        find.text('No production records found for the selected filters.'),
        findsOneWidget,
      );
      expect(find.text('PDF preview'), findsNothing);

      final from = find.byWidgetPredicate(
        (widget) => widget is DateField && widget.label == 'From Date',
      );
      final today = indiaToday();
      tester.widget<DateField>(from).onChanged!(
        DateTime(today.year, today.month, today.day + 1),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('From Date must be on or before To Date.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<FilledButton>(
              find.ancestor(
                of: generate,
                matching: find.byWidgetPredicate(
                  (widget) => widget is FilledButton,
                ),
              ),
            )
            .onPressed,
        isNull,
      );
    });
  }
}

class _StartupAuth implements MillAuth {
  final events = StreamController<AuthFlow>.broadcast();
  String? recoveryEmail;
  @override
  Staff? currentStaff;
  @override
  bool isPasswordRecovery = false;
  @override
  String? get recoveryError => null;
  @override
  Stream<AuthFlow> get stateChanges => events.stream;
  @override
  Future<Staff?> restore() async => currentStaff;
  @override
  Future<Staff> signIn(String email, String password, {StaffRole? role}) async {
    throw const MillError('The email address or password is incorrect.');
  }

  @override
  Future<void> requestRecovery(String email) async {
    recoveryEmail = email;
  }

  @override
  Future<void> signOut() async {
    currentStaff = null;
    isPasswordRecovery = false;
    events.add(AuthFlow.signedOut);
  }

  @override
  Future<void> completeRecovery(String newPassword) => signOut();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StartupBackend implements MillData {
  @override
  final _StartupAuth auth = _StartupAuth();
  @override
  Stream<int> updates(Dataset dataset) => const Stream.empty();
  @override
  Stream<MachineStatusUpdate?> get machineStatusUpdates => const Stream.empty();
  @override
  Future<List<RowData>> machineDay(DateTime date) async => [];
  @override
  Future<void> close() => auth.events.close();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
