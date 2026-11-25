import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ukm/core/domain.dart';
import 'package:ukm/core/local_auth.dart';
import 'package:ukm/core/repository.dart';
import 'package:ukm/features/machine_status/machines.dart';
import 'package:ukm/features/profile/profile.dart';
import 'package:ukm/features/program_schedule/schedule.dart';

Future<MillRepository> _repository(StaffRole role, {int machines = 3}) async {
  final database = await newDatabaseFactoryMemory().openDatabase('machines');
  addTearDown(database.close);
  final auth = LocalAuth(database, storage: null, rounds: 1000);
  await auth.setup(
    const AccountSetup(
      'Admin Test',
      'admin@example.invalid',
      'Admin test password',
    ),
  );
  await auth.signIn(
    'admin@example.invalid',
    'Admin test password',
    role: StaffRole.admin,
  );
  final repository = MillRepository(database, auth);
  for (var i = 1; i <= machines; i++) {
    await repository.saveMachine(number: '$i', dia: 24 + i * 2);
  }
  if (role == StaffRole.manager) {
    await auth.addAccount(
      StaffRole.manager,
      const AccountSetup(
        'Manager Test',
        'manager@example.invalid',
        'Manager test password',
      ),
    );
    await auth.signOut();
    await auth.signIn(
      'manager@example.invalid',
      'Manager test password',
      role: StaffRole.manager,
    );
  }
  return repository;
}

Future<void> _show(
  WidgetTester tester,
  MillRepository repository,
  Widget screen,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [localRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('running switches sit in two columns and show the assigned DIA', (
    tester,
  ) async {
    final repository = (await tester.runAsync(
      () => _repository(StaffRole.manager),
    ))!;
    await _show(
      tester,
      repository,
      const MachineScreen(role: StaffRole.manager),
    );
    final one = find.byKey(const ValueKey('machine-card-1'));
    final two = find.byKey(const ValueKey('machine-card-2'));
    final three = find.byKey(const ValueKey('machine-card-3'));
    expect(tester.getTopLeft(one).dy, tester.getTopLeft(two).dy);
    expect(tester.getTopLeft(two).dx, greaterThan(tester.getTopLeft(one).dx));
    expect(tester.getTopLeft(three).dy, greaterThan(tester.getTopLeft(one).dy));
    expect(
      find.descendant(of: one, matching: find.text('DIA 26')),
      findsOneWidget,
    );

    final toggle = find.descendant(
      of: one,
      matching: find.byType(CupertinoSwitch),
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(toggle).value, isTrue);
    expect(find.text('ON'), findsOneWidget);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<CupertinoSwitch>(toggle).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manager can confirm or cancel a calendar booking with separate dialogs',
    (tester) async {
      final repository = (await tester.runAsync(
        () => _repository(StaffRole.manager, machines: 1),
      ))!;
      await _show(
        tester,
        repository,
        const ScheduleScreen(role: StaffRole.manager),
      );
      final today = indiaToday();
      final month = DateTime(today.year, today.month);
      final cell = find.byKey(ValueKey('schedule-1-${isoDate(month)}'));
      expect(find.text('Machine / DIA'), findsOneWidget);
      expect(find.text('DIA 26'), findsOneWidget);
      expect(
        find.descendant(of: cell, matching: find.text('Available')),
        findsOneWidget,
      );

      await tester.tap(cell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cell, matching: find.text('Available')),
        findsOneWidget,
      );

      await tester.tap(cell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Schedule'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cell, matching: find.text('Scheduled')),
        findsOneWidget,
      );

      await tester.tap(cell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Make available'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: cell, matching: find.text('Available')),
        findsOneWidget,
      );

      await tester.tap(find.byTooltip('Next month'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          DateFormat.yMMMM().format(DateTime(month.year, month.month + 1)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Today'));
      await tester.pumpAndSettle();
      expect(find.text(DateFormat.yMMMM().format(month)), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'admin profile blocks show the column register and require a DIA',
    (tester) async {
      final repository = (await tester.runAsync(
        () => _repository(StaffRole.admin, machines: 0),
      ))!;
      await _show(tester, repository, ProfileScreen(logout: () async {}));
      expect(find.text('Profile details'), findsOneWidget);
      expect(find.text('Account settings'), findsOneWidget);
      expect(find.text('Staff accounts'), findsOneWidget);
      final addMachine = find.text('Add Machine');
      await tester.ensureVisible(addMachine);
      await tester.tap(addMachine);
      await tester.pumpAndSettle();

      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.at(0), 'KIT-4');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
        find.text('Enter a whole-number DIA from 1 to 999.'),
        findsOneWidget,
      );

      await tester.enterText(fields.at(1), '34');
      await tester.enterText(fields.at(3), 'Fine gauge');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('KIT-4'), findsOneWidget);
      expect(find.text('34'), findsOneWidget);
      expect(find.text('Fine gauge'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
