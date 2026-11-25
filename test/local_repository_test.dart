import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:ukm/core/domain.dart';
import 'package:ukm/core/local_auth.dart';
import 'package:ukm/core/repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'local accounts, bookings, decimal production, reports and machine archival',
    () async {
      final database = await newDatabaseFactoryMemory().openDatabase(
        'offline-fixture',
      );
      addTearDown(database.close);
      final auth = LocalAuth(database, storage: null, rounds: 1000);
      var time = DateTime.utc(2026, 11, 25, 6);
      final store = MillRepository(database, auth, clock: () => time);

      await expectLater(store.registeredMachines(), throwsA(isA<MillError>()));
      final keys = await auth.setup(
        const AccountSetup(
          'Testing Admin',
          'admin@example.invalid',
          'Fixture admin secret',
        ),
      );
      expect(keys.length, 1);
      await expectLater(
        auth.setup(
          const AccountSetup(
            'Other',
            'other@example.invalid',
            'Another fixture password',
          ),
        ),
        throwsA(isA<MillError>()),
      );
      await auth.signIn(
        'admin@example.invalid',
        'Fixture admin secret',
        role: StaffRole.admin,
      );
      await auth.addAccount(
        StaffRole.manager,
        const AccountSetup(
          'Testing Manager',
          'manager@example.invalid',
          'Fixture manager secret',
        ),
      );
      await auth.addAccount(
        StaffRole.admin,
        const AccountSetup(
          'Second Admin',
          'second@example.invalid',
          'Second admin secret',
        ),
      );
      for (var id = 1; id <= 10; id++) {
        await store.saveMachine(number: '$id', dia: 26, type: 'Circular');
      }
      await store.saveMachine(
        id: 1,
        number: '1',
        dia: 28,
        type: 'Circular rib',
        specifications: '28 DIA',
      );
      expect((await store.registeredMachines()).first['type'], 'Circular rib');
      expect((await store.registeredMachines()).first['dia'], 28);
      await expectLater(
        store.saveMachine(number: '01', dia: 28),
        throwsA(isA<MillError>()),
      );
      await expectLater(
        store.saveMachine(number: '11', dia: 0),
        throwsA(isA<MillError>()),
      );

      await auth.signOut();
      expect(
        (await auth.signIn(
          'second@example.invalid',
          'Second admin secret',
          role: StaffRole.admin,
        )).role,
        StaffRole.admin,
      );
      await auth.signOut();
      await expectLater(
        auth.signIn(
          'manager@example.invalid',
          'Fixture manager secret',
          role: StaffRole.admin,
        ),
        throwsA(isA<MillError>()),
      );
      await expectLater(
        auth.signIn('manager@example.invalid', 'incorrect'),
        throwsA(isA<MillError>()),
      );
      final manager = await auth.signIn(
        'Manager@example.invalid',
        'Fixture manager secret',
      );
      expect(manager.role, StaffRole.manager);
      final day = DateTime(2026, 11, 25);
      expect((await store.registeredMachines()).length, 10);
      await expectLater(
        store.saveMachine(number: '11', dia: 32),
        throwsA(isA<MillError>()),
      );
      await expectLater(auth.managers(), throwsA(isA<MillError>()));
      await expectLater(store.removeMachine(1), throwsA(isA<MillError>()));
      await expectLater(
        auth.addAccount(
          StaffRole.admin,
          const AccountSetup(
            'Denied',
            'denied@example.invalid',
            'Another fixture password',
          ),
        ),
        throwsA(isA<MillError>()),
      );
      await auth.editProfile(
        'Edited Manager',
        'manager@example.invalid',
        '5550100',
      );
      expect((await auth.profile())['phone'], '5550100');
      await auth.changePassword(
        'Fixture manager secret',
        'New fixture manager secret',
      );
      await store.setRunning(1, day, true);
      expect((await store.machineDay(day)).first['running'], isTrue);
      expect((await store.scheduleDay(day)).first['scheduled'], isFalse);
      await store.scheduleMachine(1, day);
      await expectLater(
        store.scheduleMachine(1, day),
        throwsA(isA<MillError>()),
      );
      expect((await store.scheduleDay(day)).first['scheduled'], isTrue);
      await store.cancelMachineSchedule(1, day);
      expect((await store.scheduleDay(day)).first['scheduled'], isFalse);
      expect((await store.machineDay(day)).first['running'], isTrue);
      final tomorrow = DateTime(2026, 11, 26);
      final activeRange = stringMapStoreFactory.store('schedules');
      await activeRange.record('legacy-range').put(database, {
        'id': 'legacy-range',
        'machine_id': 1,
        'start_date': '2026-11-24',
        'end_date': '2026-11-26',
      });
      await store.cancelMachineSchedule(1, day);
      final calendar = await store.machineSchedule(
        DateTime(2026, 11, 24),
        tomorrow,
      );
      expect(calendar.first.bookedDates, {'2026-11-24', '2026-11-26'});
      await store.scheduleMachine(1, day);
      await store.setRunning(1, day, false);
      expect((await store.machineDay(day)).first['running'], isFalse);
      expect((await store.scheduleDay(day)).first['scheduled'], isTrue);
      await store.setRunning(1, day, true);
      expect(
        (await store.machineDay(DateTime(2026, 11, 24))).first['running'],
        isFalse,
      );
      await store.saveJob(
        date: day,
        number: 'Test-001',
        party: 'Test Party',
        yarn: 'Test yarn',
        programs: [
          {
            'dia': 28,
            'loop_length': '2.2',
            'ordered_kg': '500.001',
            'specification': 'Single Jersey',
            'remarks': 'First program',
          },
          {
            'dia': 28,
            'loop_length': '2.3',
            'ordered_kg': '20',
            'specification': 'single jersey',
            'remarks': 'Second program',
          },
        ],
      );
      final job = (await store.jobs()).single;
      final details = await store.programs(job['id']);
      expect(details.map((program) => program['remarks']), [
        'First program',
        'Second program',
      ]);
      expect((await store.names('specifications')).length, 1);
      expect(details.map((program) => program['specification']).toSet(), {
        'Single Jersey',
      });
      final id = details.first['id'] as String;
      final create = [
        {'program_id': id, 'quantity_kg': '200.001'},
      ];
      await store.saveProduction(job['id'], day, Shift.morning, create);
      await expectLater(
        store.saveProduction(job['id'], day, Shift.morning, create),
        throwsA(isA<MillError>()),
      );
      await store.saveProduction(job['id'], day, Shift.night, [
        {'program_id': id, 'quantity_kg': '100'},
      ]);
      final sheet = await store.productionSheet(job['id'], day, Shift.night);
      final program = rows(sheet['programs']).first;
      expect(program['previous_kg'], '200.001');
      expect(program['balance_kg'], '200');
      time = time.add(const Duration(seconds: 1));
      await store.saveProduction(job['id'], day, Shift.night, [
        {
          'program_id': id,
          'version': program['shift_version'],
          'quantity_kg': '300',
        },
      ]);
      final report = await store.report(jobId: job['id']);
      expect(rows(report['programs']).length, 2);
      expect(rows(report['entries']).length, 2);
      expect(
        rows(
          (await store.report(
            start: day,
            end: day,
            shift: Shift.night,
          ))['entries'],
        ).length,
        1,
      );
      expect(rows(report['programs']).first['balance_kg'], '0');

      await auth.signOut();
      final admin = await auth.signIn(
        'admin@example.invalid',
        'Fixture admin secret',
      );
      expect(admin.role, StaffRole.admin);
      await expectLater(
        store.cancelMachineSchedule(1, day),
        throwsA(isA<MillError>()),
      );
      await expectLater(
        store.setRunning(1, day, false),
        throwsA(isA<MillError>()),
      );
      await store.removeMachine(1);
      expect((await store.registeredMachines()).length, 9);
      expect(
        (await store.scheduleDay(day)).any((row) => row['id'] == 1),
        isFalse,
      );
      expect(
        await stringMapStoreFactory
            .store('daily_machine_status')
            .record('1|2026-11-25')
            .get(database),
        isNotNull,
      );
      await auth.setManagerEnabled('manager@example.invalid', false);
      await expectLater(
        auth.signIn(
          'manager@example.invalid',
          'New fixture manager secret',
          role: StaffRole.manager,
        ),
        throwsA(isA<MillError>()),
      );
      expect(rows((await store.report(jobId: job['id']))['entries']).length, 2);
      await auth.setManagerEnabled('manager@example.invalid', true);
      await auth.signOut();
      expect(
        (await auth.signIn(
          'manager@example.invalid',
          'New fixture manager secret',
          role: StaffRole.manager,
        )).name,
        'Edited Manager',
      );
      await auth.signOut();
      final oldKey = keys.singleWhere((item) => item.role == StaffRole.admin);
      final replacement = await auth.recover(
        'admin@example.invalid',
        oldKey.value,
        'Fixture replacement secret',
      );
      expect(replacement, isNot(oldKey.value));
      await expectLater(
        auth.recover(
          'admin@example.invalid',
          oldKey.value,
          'Fixture third secret',
        ),
        throwsA(isA<MillError>()),
      );
      expect(
        (await auth.signIn(
          'admin@example.invalid',
          'Fixture replacement secret',
        )).role,
        StaffRole.admin,
      );
    },
  );
}
