import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:ukm/core/domain.dart';
import 'package:ukm/core/auth.dart';
import 'package:ukm/core/repository.dart';
import 'package:ukm/features/machine_status/machines.dart';
import 'package:ukm/features/profile/profile.dart';
import 'package:ukm/features/program_schedule/schedule.dart';

class _MachineAuth implements MillAuth {
  _MachineAuth(this.role);
  final StaffRole role;
  String? recoveredEmail;

  @override
  Future<RowData> profile() async => {
    'full_name': 'Fixture',
    'email': 'fixture@example.invalid',
    'role': role.name,
  };

  @override
  Future<List<RowData>> managers() async => [];

  @override
  Future<void> requestRecovery(String email) async {
    recoveredEmail = email;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MachineData implements MillData {
  _MachineData(StaffRole role, {int machines = 3}) : auth = _MachineAuth(role) {
    for (var i = 1; i <= machines; i++) {
      records.add({
        'id': i,
        'number': '$i',
        'name': 'Machine $i',
        'dia': 24 + i * 2,
      });
    }
  }
  @override
  final _MachineAuth auth;
  final records = <RowData>[];
  final bookings = <int, Set<String>>{};
  final statusEvents = StreamController<MachineStatusUpdate?>.broadcast();
  Completer<List<RowData>>? nextRead;
  Completer<void>? nextWrite;
  int writes = 0;

  @override
  Stream<int> updates(Dataset dataset) => const Stream.empty();
  @override
  Stream<MachineStatusUpdate?> get machineStatusUpdates => statusEvents.stream;
  @override
  Future<List<RowData>> registeredMachines() async => List.of(records);
  @override
  Future<List<RowData>> machineDay(DateTime date) async =>
      nextRead?.future ?? records.map((row) => {...row}).toList();
  @override
  Future<MachineStatus> setRunning(int id, DateTime date, bool running) async {
    writes++;
    await nextWrite?.future;
    final row = records.firstWhere((row) => row['id'] == id);
    final revision = (row['status_revision'] as int? ?? 0) + 1;
    row['running'] = running;
    row['status_revision'] = revision;
    return (running: running, revision: revision);
  }

  @override
  Future<void> saveMachine({
    int? id,
    required String number,
    required String dia,
    String type = '',
    String specifications = '',
  }) async {
    records.add({
      'id': id ?? records.length + 1,
      'name': number,
      'number': number,
      'dia_label': dia,
      'type': type,
      'specifications': specifications,
    });
  }

  @override
  Future<List<MachineScheduleRow>> machineSchedule(
    DateTime first,
    DateTime last,
  ) async => [
    for (final machine in records)
      (
        machine: machine,
        bookedDates: Set.of(bookings[machine['id']] ?? const <String>{}),
      ),
  ];
  @override
  Future<void> scheduleMachine(int id, DateTime date) async {
    (bookings[id] ??= {}).add(isoDate(date));
  }

  @override
  Future<void> cancelMachineSchedule(int id, DateTime date) async {
    bookings[id]?.remove(isoDate(date));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _show(
  WidgetTester tester,
  MillData repository,
  Widget screen,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [millDataProvider.overrideWithValue(repository)],
      child: MaterialApp(home: Scaffold(body: screen)),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  for (final role in StaffRole.values) {
    testWidgets('${role.label} can request recovery from Change password', (
      tester,
    ) async {
      final repository = _MachineData(role, machines: 0);
      await _show(tester, repository, ProfileScreen(logout: () async {}));
      final change = find.text('Change password');
      await tester.ensureVisible(change);
      await tester.tap(change);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Forgot Current Password?'));
      await tester.pumpAndSettle();
      expect(repository.auth.recoveredEmail, 'fixture@example.invalid');
      expect(
        find.textContaining('Check your registered email'),
        findsOneWidget,
      );
    });
  }
  testWidgets('running switches sit in two columns and show the assigned DIA', (
    tester,
  ) async {
    final repository = _MachineData(StaffRole.manager);
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
    'manager ignores rapid taps and old snapshots, and rolls back errors',
    (tester) async {
      final repository = _MachineData(StaffRole.manager, machines: 1);
      addTearDown(repository.statusEvents.close);
      await _show(
        tester,
        repository,
        const MachineScreen(role: StaffRole.manager),
      );
      final switchFinder = find.byType(CupertinoSwitch);
      bool running() => tester.widget<CupertinoSwitch>(switchFinder).value;

      final stale = repository.nextRead = Completer<List<RowData>>();
      repository.statusEvents.add(null);
      await tester.pump();
      final write = repository.nextWrite = Completer<void>();
      await tester.tap(switchFinder);
      await tester.pump();
      expect(running(), isTrue);
      expect(find.text('Running Machines · 1'), findsOneWidget);
      tester.widget<CupertinoSwitch>(switchFinder).onChanged!(false);
      expect(repository.writes, 1);
      write.complete();
      await tester.pump();
      expect(running(), isTrue);

      stale.complete([
        {...repository.records.single, 'running': false, 'status_revision': 0},
      ]);
      repository.nextRead = null;
      repository.statusEvents.add((
        id: 1,
        date: isoDate(indiaToday()),
        status: (running: false, revision: 0),
      ));
      await tester.pumpAndSettle();
      expect(running(), isTrue);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      final failed = repository.nextWrite = Completer<void>();
      await tester.tap(switchFinder);
      await tester.pump();
      expect(running(), isFalse);
      failed.completeError(const MillError('Could not update fixture.'));
      await tester.pumpAndSettle();
      expect(running(), isTrue);
      expect(find.text('Could not update fixture.'), findsOneWidget);
      expect(find.text('Stopped Machines · 0'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await _show(
        tester,
        repository,
        const MachineScreen(role: StaffRole.manager),
      );
      expect(running(), isTrue);
    },
  );

  testWidgets('admin status follows Realtime and rotates only while running', (
    tester,
  ) async {
    final repository = _MachineData(StaffRole.admin, machines: 1);
    addTearDown(repository.statusEvents.close);
    await _show(tester, repository, const MachineScreen(role: StaffRole.admin));
    final gear = find.descendant(
      of: find.byKey(const ValueKey('machine-card-1')),
      matching: find.byType(RotationTransition),
    );
    double turns() => tester.widget<RotationTransition>(gear).turns.value;
    void send(bool running, int revision) => repository.statusEvents.add((
      id: 1,
      date: isoDate(indiaToday()),
      status: (running: running, revision: revision),
    ));
    expect(find.byType(CupertinoSwitch), findsNothing);
    expect(find.text('Stopped'), findsOneWidget);
    expect(turns(), 0);
    send(true, 2);
    await tester.pump();
    await tester.pump();
    expect(find.text('Running'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(turns(), greaterThan(0));
    send(false, 1);
    await tester.pump();
    expect(find.text('Running'), findsOneWidget);
    send(false, 3);
    await tester.pumpAndSettle();
    expect(find.text('Stopped'), findsOneWidget);
    expect(turns(), 0);
    expect(repository.writes, 0);
  });

  testWidgets('admin respects reduced motion for running machines', (
    tester,
  ) async {
    final repository = _MachineData(StaffRole.admin, machines: 1);
    addTearDown(repository.statusEvents.close);
    repository.records.single['running'] = true;
    await _show(
      tester,
      repository,
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true, size: Size(390, 844)),
        child: MachineScreen(role: StaffRole.admin),
      ),
    );
    final gear = tester.widget<RotationTransition>(
      find.descendant(
        of: find.byKey(const ValueKey('machine-card-1')),
        matching: find.byType(RotationTransition),
      ),
    );
    expect(gear.turns.value, 0);
    expect(find.text('Running'), findsOneWidget);
  });

  testWidgets(
    'manager can confirm or cancel a calendar booking with separate dialogs',
    (tester) async {
      final repository = _MachineData(StaffRole.manager, machines: 1);
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
      final repository = _MachineData(StaffRole.admin, machines: 0);
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
        find.text('Enter a DIA label of up to 40 characters.'),
        findsOneWidget,
      );

      await tester.enterText(fields.at(1), '34A');
      await tester.enterText(fields.at(3), 'Fine gauge');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(find.byType(DataTable), findsOneWidget);
      expect(find.text('KIT-4'), findsOneWidget);
      expect(find.text('34A'), findsOneWidget);
      expect(find.text('Fine gauge'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
