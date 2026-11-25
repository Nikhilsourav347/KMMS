import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sembast/sembast.dart';

import 'domain.dart';
import 'local_auth.dart';

final localRepositoryProvider = Provider<MillData?>((ref) => null);
final repositoryProvider = Provider(
  (ref) => ref.watch(localRepositoryProvider)!,
);

enum Dataset { machines, schedule, jobs, production }

final revisionsProvider = StreamProvider.autoDispose.family<int, Dataset>(
  (ref, _) => ref.watch(repositoryProvider).updates,
);

final jobsProvider = FutureProvider.autoDispose<List<RowData>>((ref) {
  ref.watch(revisionsProvider(Dataset.jobs));
  return ref.watch(repositoryProvider).jobs();
});

final _machines = intMapStoreFactory.store('machines');
final _dailyStatus = stringMapStoreFactory.store('daily_machine_status');
final _status = intMapStoreFactory.store('machine_status');
final _history = stringMapStoreFactory.store('machine_status_history');
final _schedules = stringMapStoreFactory.store('schedules');
final _jobs = stringMapStoreFactory.store('jobs');
final _programs = stringMapStoreFactory.store('job_programs');
final _parties = stringMapStoreFactory.store('parties');
final _specifications = stringMapStoreFactory.store('specifications');
final _production = stringMapStoreFactory.store('production_entries');
final _audit = intMapStoreFactory.store('audit_logs');
final _meta = intMapStoreFactory.store('metadata');
final _revision = _meta.record(1);
final _random = Random.secure();

String _uniqueId() => List.generate(
  16,
  (_) => _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();
String _normalized(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
String _date(Object? value) => value as String;
int _byText(RowData a, RowData b, String key) =>
    '${a[key]}'.compareTo('${b[key]}');

Future<List<RowData>> _all<K>(
  StoreRef<K, RowData> store,
  DatabaseClient client,
) async => (await store.find(client)).map((record) => record.value).toList();

typedef MachineScheduleRow = ({RowData machine, Set<String> bookedDates});

abstract interface class MillData {
  MillAuth get auth;
  Stream<int> get updates;
  Future<void> close();
  Future<List<RowData>> registeredMachines();
  Future<void> saveMachine({
    int? id,
    required String number,
    required int dia,
    String type = '',
    String specifications = '',
  });
  Future<void> removeMachine(int id);
  Future<List<RowData>> machineDay(DateTime date);
  Future<void> setRunning(int id, DateTime date, bool running);
  Future<List<MachineScheduleRow>> machineSchedule(
    DateTime first,
    DateTime last,
  );
  Future<void> scheduleMachine(int id, DateTime date);
  Future<void> cancelMachineSchedule(int id, DateTime date);
  Future<List<RowData>> names(String table);
  Future<void> saveJob({
    RowData? existing,
    required DateTime date,
    required String number,
    required String party,
    required String yarn,
    required List<RowData> programs,
  });
  Future<List<RowData>> jobs();
  Future<List<RowData>> programs(String jobId);
  Future<RowData> productionSheet(String jobId, DateTime date, Shift shift);
  Future<void> saveProduction(
    String jobId,
    DateTime date,
    Shift shift,
    List<RowData> lines,
  );
  Future<RowData> report({
    DateTime? start,
    DateTime? end,
    Shift? shift,
    String? jobId,
    String? partyId,
    int? dia,
  });
}

class MillRepository implements MillData {
  MillRepository(this.db, this.auth, {DateTime Function()? clock})
    : clock = clock ?? DateTime.now;
  final Database db;
  @override
  final LocalAuth auth;
  final DateTime Function() clock;
  @override
  Future<void> close() => db.close();
  String get _now => clock().toUtc().toIso8601String();
  DateTime get _today => plainDate(indiaTime(clock()));
  @override
  Stream<int> get updates => _revision
      .onSnapshot(db)
      .map((row) => (row?.value['number'] as int?) ?? 0);

  Future<void> _changed(Transaction txn) async {
    final row = await _revision.get(txn);
    await _revision.put(txn, {'number': (row?['number'] as int? ?? 0) + 1});
  }

  Future<void> _write(
    Future<void> Function(Transaction) action, {
    StaffRole? role = StaffRole.manager,
  }) => db.transaction((txn) async {
    await auth.authorize(txn, role: role);
    await action(txn);
    await _changed(txn);
  });

  Future<void> _recordAudit(
    Transaction txn,
    String table,
    String operation,
    RowData? before,
    RowData? after,
  ) async {
    await _audit.add(txn, {
      'table': table,
      'operation': operation,
      'before': before,
      'after': after,
      'actor': auth.currentEmail,
      'recorded_at': _now,
    });
  }

  @override
  Future<List<RowData>> registeredMachines() async {
    await auth.authorize(db);
    return (await _all(
        _machines,
        db,
      )).where((row) => row['removed_at'] == null).toList()
      ..sort((a, b) => _byText(a, b, 'name'));
  }

  @override
  Future<void> saveMachine({
    int? id,
    required String number,
    required int dia,
    String type = '',
    String specifications = '',
  }) => _write((txn) async {
    final label = _required(number, 'a machine number', 40);
    if (dia < 1 || dia > 999) {
      throw const MillError('Enter a DIA from 1 to 999.');
    }
    if (type.trim().length > 80 || specifications.trim().length > 360) {
      throw const MillError(
        'Use up to 80 characters for type and 360 for specifications.',
      );
    }
    final name = RegExp(r'^\d+$').hasMatch(label)
        ? 'Machine ${label.padLeft(2, '0')}'
        : label;
    final all = await _all(_machines, txn);
    if (all.any(
      (row) =>
          row['id'] != id &&
              row['removed_at'] == null &&
              _normalized(row['number'] ?? row['name']) == _normalized(label) ||
          row['id'] != id &&
              row['removed_at'] == null &&
              _normalized(row['name']) == _normalized(name),
    )) {
      throw const MillError('That machine number has already been registered.');
    }
    final nextId =
        id ??
        all.fold<int>(0, (largest, row) => max(largest, row['id'] as int)) + 1;
    final record = _machines.record(nextId);
    final before = await record.get(txn);
    if (id != null && (before == null || before['removed_at'] != null)) {
      throw const MillError('Machine is unavailable.');
    }
    final next = {
      ...?before,
      'id': nextId,
      'name': name,
      'number': label,
      'dia': dia,
      'type': type.trim(),
      'specifications': specifications.trim(),
    };
    await record.put(txn, next);
    await _recordAudit(
      txn,
      'machines',
      before == null ? 'insert' : 'update',
      before,
      next,
    );
  }, role: StaffRole.admin);

  @override
  Future<void> removeMachine(int id) => _write((txn) async {
    final record = _machines.record(id);
    final previous = await record.get(txn);
    if (previous == null || previous['removed_at'] != null) {
      throw const MillError('Machine is unavailable.');
    }
    final next = {...previous, 'removed_at': _now};
    await record.put(txn, next);
    await _recordAudit(txn, 'machines', 'archive', previous, next);
  }, role: StaffRole.admin);

  @override
  Future<List<RowData>> machineDay(DateTime date) async {
    await auth.authorize(db);
    final day = isoDate(date);
    return db.transaction((txn) async {
      final result = <RowData>[];
      for (final machine in await _all(_machines, txn)) {
        if (machine['removed_at'] != null) continue;
        final id = machine['id'] as int;
        final current = await _dailyStatus.record('$id|$day').get(txn);
        final legacy = await _status.record(id).get(txn);
        bool? running = current?['running'] as bool?;
        if (running == null) {
          for (final shift in [Shift.night, Shift.morning]) {
            final historical =
                legacy?['shift_date'] == day && legacy?['shift'] == shift.name
                ? legacy
                : await _history.record('$id|$day|${shift.name}').get(txn);
            final value = historical?['status'];
            if (value == 'running' || value == 'stopped') {
              running = value == 'running';
              break;
            }
          }
        }
        result.add({...machine, 'running': running ?? false});
      }
      return result..sort((a, b) => _byText(a, b, 'name'));
    });
  }

  @override
  Future<void> setRunning(int id, DateTime date, bool running) => _write((
    txn,
  ) async {
    final machine = await _machines.record(id).get(txn);
    if (machine == null || machine['removed_at'] != null) {
      throw const MillError('Machine is unavailable.');
    }
    final day = isoDate(date);
    final record = _dailyStatus.record('$id|$day');
    final previous = await record.get(txn);
    final next = {'machine_id': id, 'date': day, 'running': running};
    await record.put(txn, next);
    await _recordAudit(txn, 'daily_machine_status', 'update', previous, next);
  });

  bool _isBooked(RowData row, int id, String date) =>
      row['machine_id'] == id &&
      _date(row['start_date']).compareTo(date) <= 0 &&
      _date(row['end_date']).compareTo(date) >= 0;

  Future<List<RowData>> scheduleDay(DateTime date) async {
    final day = isoDate(date);
    final entries = await machineSchedule(date, date);
    return [
      for (final entry in entries)
        {...entry.machine, 'scheduled': entry.bookedDates.contains(day)},
    ];
  }

  @override
  Future<List<MachineScheduleRow>> machineSchedule(
    DateTime first,
    DateTime last,
  ) async {
    return db.transaction((txn) async {
      await auth.authorize(txn);
      final bookings = await _all(_schedules, txn);
      final dates = [
        for (
          var date = plainDate(first);
          !date.isAfter(last);
          date = DateTime(date.year, date.month, date.day + 1)
        )
          isoDate(date),
      ];
      final byMachine = <int, List<RowData>>{};
      for (final booking in bookings) {
        if (booking['machine_id'] case final int id) {
          (byMachine[id] ??= []).add(booking);
        }
      }
      return [
        for (final machine in await _all(_machines, txn))
          if (machine['removed_at'] == null)
            (
              machine: machine,
              bookedDates: {
                for (final date in dates)
                  if (byMachine[machine['id']]?.any(
                        (row) => _isBooked(row, machine['id'], date),
                      ) ??
                      false)
                    date,
              },
            ),
      ]..sort((a, b) => _byText(a.machine, b.machine, 'name'));
    });
  }

  @override
  Future<void> scheduleMachine(int id, DateTime date) => _write((txn) async {
    final machine = await _machines.record(id).get(txn);
    if (machine == null || machine['removed_at'] != null) {
      throw const MillError('Machine is unavailable.');
    }
    final day = isoDate(date);
    if ((await _all(_schedules, txn)).any((row) => _isBooked(row, id, day))) {
      throw const MillError('This machine is already scheduled on that date.');
    }
    final key = _uniqueId();
    final booking = {
      'id': key,
      'machine_id': id,
      'start_date': day,
      'end_date': day,
      'updated_at': _now,
    };
    await _schedules.record(key).put(txn, booking);
    await _recordAudit(txn, 'schedules', 'insert', null, booking);
  });

  @override
  Future<void> cancelMachineSchedule(int id, DateTime date) => _write((
    txn,
  ) async {
    final machine = await _machines.record(id).get(txn);
    if (machine == null || machine['removed_at'] != null) {
      throw const MillError('Machine is unavailable.');
    }
    final day = isoDate(date);
    final bookings = (await _schedules.find(
      txn,
    )).where((entry) => _isBooked(entry.value, id, day));
    if (bookings.isEmpty) {
      throw const MillError('This machine is already available on that date.');
    }
    for (final entry in bookings) {
      final original = entry.value;
      await entry.ref.delete(txn);
      await _recordAudit(txn, 'schedules', 'cancel_day', original, {
        'machine_id': id,
        'date': day,
      });
      final before = isoDate(DateTime(date.year, date.month, date.day - 1));
      final after = isoDate(DateTime(date.year, date.month, date.day + 1));
      for (final (start, end) in [
        if (_date(original['start_date']).compareTo(day) < 0)
          (_date(original['start_date']), before),
        if (_date(original['end_date']).compareTo(day) > 0)
          (after, _date(original['end_date'])),
      ]) {
        final key = _uniqueId();
        final replacement = {
          ...original,
          'id': key,
          'start_date': start,
          'end_date': end,
          'updated_at': _now,
        };
        await _schedules.record(key).put(txn, replacement);
        await _recordAudit(txn, 'schedules', 'retain_range', null, replacement);
      }
    }
  });

  void _checkDia(int? dia) {
    if (dia == null || !dias.contains(dia)) {
      throw const MillError('Select a valid DIA.');
    }
  }

  String _required(String value, String label, int limit) {
    final result = value.trim();
    if (result.isEmpty || result.length > limit) {
      throw MillError('Enter $label with up to $limit characters.');
    }
    return result;
  }

  Future<String> _saveName(
    Transaction txn,
    StoreRef<String, RowData> store,
    String name,
    String label,
  ) async {
    final entered = _required(name, label, 120);
    final key = _normalized(entered);
    final existing = await store.record(key).get(txn);
    if (existing == null) {
      await store.record(key).put(txn, {'id': key, 'name': entered});
    }
    return key;
  }

  @override
  Future<List<RowData>> names(String table) async {
    await auth.authorize(db);
    final results = await _all(
      table == 'parties' ? _parties : _specifications,
      db,
    );
    results.sort((a, b) => _byText(a, b, 'name'));
    return results;
  }

  @override
  Future<void> saveJob({
    RowData? existing,
    required DateTime date,
    required String number,
    required String party,
    required String yarn,
    required List<RowData> programs,
  }) => _write((txn) async {
    final jobNumber = _required(number, 'a job number', 60);
    final yarnDetails = _required(yarn, 'yarn details', 240);
    if (programs.isEmpty) {
      throw const MillError('Add at least one complete program.');
    }
    final id = existing?['id'] as String? ?? _uniqueId();
    final record = _jobs.record(id);
    final prior = await record.get(txn);
    if (existing != null &&
        (prior == null || existing['updated_at'] != prior['updated_at'])) {
      throw const MillError('This job changed. Reopen it before saving.');
    }
    if ((await _all(_jobs, txn)).any(
      (job) =>
          job['id'] != id &&
          _normalized(job['job_number']) == _normalized(jobNumber),
    )) {
      throw const MillError('This job number is already in use.');
    }
    final partyId = await _saveName(txn, _parties, party, 'a party name');
    final history = await _all(_production, txn);
    final used = <String>{};
    for (final (i, draft) in programs.indexed) {
      final previousId = draft['id'] as String?;
      final programId = previousId ?? _uniqueId();
      if (!used.add(programId)) {
        throw const MillError('A program occurs more than once.');
      }
      final program = _programs.record(programId);
      final original = await program.get(txn);
      if (previousId != null && original?['job_id'] != id) {
        throw const MillError('A program does not belong to this job.');
      }
      final dia = draft['dia'] as int?;
      _checkDia(dia);
      final loop = parseGrams(draft['loop_length']);
      final ordered = parseGrams(draft['ordered_kg']);
      final remarks = (draft['remarks'] as String? ?? '').trim();
      if (loop == null ||
          loop <= 0 ||
          ordered == null ||
          ordered <= 0 ||
          remarks.length > 360) {
        throw const MillError(
          'Enter positive loop lengths and ordered quantities with up to three decimals.',
        );
      }
      final specId = await _saveName(
        txn,
        _specifications,
        draft['specification'],
        'a specification',
      );
      final entries = history.where((row) => row['program_id'] == programId);
      if (entries.isNotEmpty && original != null) {
        if (original['dia'] != dia ||
            grams(original['loop_length']) != loop ||
            original['specification_id'] != specId) {
          throw const MillError(
            'DIA, loop length and specification are locked after recording production.',
          );
        }
        if (ordered < _output(entries)) {
          throw const MillError(
            'Ordered quantity cannot be lower than recorded production.',
          );
        }
      }
      final next = <String, dynamic>{
        'id': programId,
        'job_id': id,
        'dia': dia,
        'loop_length': kg(loop),
        'ordered_kg': kg(ordered),
        'specification_id': specId,
        'remarks': remarks,
        'position': i + 1,
      };
      await program.put(txn, next);
      await _recordAudit(
        txn,
        'job_programs',
        original == null ? 'insert' : 'update',
        original,
        next,
      );
    }
    for (final program in (await _all(
      _programs,
      txn,
    )).where((p) => p['job_id'] == id && !used.contains(p['id']))) {
      if (history.any((e) => e['program_id'] == program['id'])) {
        throw const MillError(
          'A program with production history cannot be removed.',
        );
      }
      await _programs.record(program['id']).delete(txn);
      await _recordAudit(txn, 'job_programs', 'delete', program, null);
    }
    final next = <String, dynamic>{
      'id': id,
      'job_date': isoDate(date),
      'job_number': jobNumber,
      'party_id': partyId,
      'yarn': yarnDetails,
      'updated_at': _now,
    };
    await record.put(txn, next);
    await _recordAudit(
      txn,
      'jobs',
      prior == null ? 'insert' : 'update',
      prior,
      next,
    );
  });

  int _output(Iterable<RowData> records) =>
      records.fold(0, (sum, row) => sum + grams(row['quantity_kg']));

  @override
  Future<List<RowData>> jobs() async {
    await auth.authorize(db);
    return db.transaction((txn) async {
      final state = await _snapshot(txn);
      final jobs = [for (final j in state.jobs.values) state.jobTotals(j)];
      jobs.sort(
        (a, b) => _byText(b, a, 'job_date') != 0
            ? _byText(b, a, 'job_date')
            : _byText(a, b, 'job_number'),
      );
      return jobs;
    });
  }

  @override
  Future<List<RowData>> programs(String jobId) async {
    await auth.authorize(db);
    return db.transaction((txn) async {
      final state = await _snapshot(txn);
      return state.byJob(jobId).map(state.programTotals).toList();
    });
  }

  @override
  Future<RowData> productionSheet(
    String jobId,
    DateTime date,
    Shift shift,
  ) async {
    await auth.authorize(db, role: StaffRole.manager);
    return db.transaction((txn) async {
      final state = await _snapshot(txn);
      final programs = state.byJob(jobId)
        ..sort(
          (a, b) => (a['dia'] as int).compareTo(b['dia']) != 0
              ? (a['dia'] as int).compareTo(b['dia'])
              : (a['position'] as int).compareTo(b['position']),
        );
      final job = state.jobs[jobId];
      return {
        'job': job == null ? null : state.jobTotals(job),
        'programs': [
          for (final p in programs) _entryFor(state, p, date, shift),
        ],
      };
    });
  }

  RowData _entryFor(
    _MillSnapshot state,
    RowData program,
    DateTime date,
    Shift shift,
  ) {
    final current = state.entriesByProgram[program['id']]
        ?.where(
          (row) =>
              row['production_date'] == isoDate(date) &&
              row['shift'] == shift.name,
        )
        .firstOrNull;
    final totals = state.programTotals(program);
    return {
      ...totals,
      'shift_kg': current?['quantity_kg'],
      'shift_version': current?['updated_at'],
      'previous_kg': kg(
        grams(totals['produced_kg']) - grams(current?['quantity_kg']),
      ),
    };
  }

  @override
  Future<void> saveProduction(
    String jobId,
    DateTime date,
    Shift shift,
    List<RowData> lines,
  ) => _write((txn) async {
    if (date.isAfter(_today) || lines.isEmpty) {
      throw const MillError(
        'Select a valid date and enter at least one quantity.',
      );
    }
    if (await _jobs.record(jobId).get(txn) == null) {
      throw const MillError('The selected job is unavailable.');
    }
    final day = isoDate(date);
    final history = await _all(_production, txn);
    final seen = <String>{};
    for (final line in lines) {
      final id = line['program_id'] as String;
      final program = await _programs.record(id).get(txn);
      if (program == null || program['job_id'] != jobId || !seen.add(id)) {
        throw const MillError('Select distinct programs from this job.');
      }
      final quantity = parseGrams(line['quantity_kg']);
      if (quantity == null || quantity < 0) {
        throw const MillError(
          'Enter a non-negative quantity with up to three decimals.',
        );
      }
      final entry = _production.record('$id|$day|${shift.name}');
      final original = await entry.get(txn);
      if (original?['updated_at'] != line['version']) {
        throw const MillError(
          'Production changed. Reload the sheet before saving.',
        );
      }
      final others = history.where(
        (row) => row['program_id'] == id && row['id'] != entry.key,
      );
      if (_output(others) + quantity > grams(program['ordered_kg'])) {
        throw const MillError(
          'Production exceeds the remaining ordered quantity for a program.',
        );
      }
      if (original != null && grams(original['quantity_kg']) == quantity) {
        continue;
      }
      final next = <String, dynamic>{
        'id': entry.key,
        'program_id': id,
        'production_date': day,
        'shift': shift.name,
        'quantity_kg': kg(quantity),
        'updated_at': _now,
        'updated_by': auth.currentEmail,
      };
      await entry.put(txn, next);
      await _recordAudit(
        txn,
        'production_entries',
        original == null ? 'insert' : 'update',
        original,
        next,
      );
    }
  });

  Future<_MillSnapshot> _snapshot(Transaction txn) async => _MillSnapshot(
    await _all(_jobs, txn),
    await _all(_programs, txn),
    await _all(_parties, txn),
    await _all(_specifications, txn),
    await _all(_production, txn),
  );

  @override
  Future<RowData> report({
    DateTime? start,
    DateTime? end,
    Shift? shift,
    String? jobId,
    String? partyId,
    int? dia,
  }) async {
    await auth.authorize(db);
    return db.transaction((txn) async {
      final snapshot = await _snapshot(txn);
      final records = <RowData>[];
      final totals = <RowData>[];
      final from = start == null ? null : isoDate(start);
      final to = end == null ? null : isoDate(end);
      for (final program in snapshot.programs) {
        final job = snapshot.jobs[program['job_id']]!;
        if ((dia != null && program['dia'] != dia) ||
            (jobId != null && job['id'] != jobId) ||
            (partyId != null && job['party_id'] != partyId)) {
          continue;
        }
        final detail = snapshot.programTotals(program);
        final matches = (snapshot.entriesByProgram[program['id']] ?? []).where((
          entry,
        ) {
          final date = _date(entry['production_date']);
          return (from == null || date.compareTo(from) >= 0) &&
              (to == null || date.compareTo(to) <= 0) &&
              (shift == null || entry['shift'] == shift.name);
        }).toList();
        if (matches.isEmpty &&
            !(jobId != null && start == null && end == null)) {
          continue;
        }
        final labels = {
          'job_id': job['id'],
          'job_number': job['job_number'],
          'job_date': job['job_date'],
          'party': snapshot.partyName(job),
          'yarn': job['yarn'],
        };
        totals.add({
          ...detail,
          ...labels,
          'period_kg': kg(_output(matches)),
          if (to != null)
            'balance_on_end_kg': kg(
              grams(program['ordered_kg']) -
                  _output(
                    (snapshot.entriesByProgram[program['id']] ?? []).where(
                      (entry) =>
                          _date(entry['production_date']).compareTo(to) <= 0,
                    ),
                  ),
            ),
        });
        for (final entry in matches) {
          records.add({
            ...entry,
            ...labels,
            'dia': program['dia'],
            'program_position': program['position'],
            'specification': detail['specification'],
            'loop_length': program['loop_length'],
            'remarks': program['remarks'],
          });
        }
      }
      totals.sort(
        (a, b) => _byText(a, b, 'job_number') != 0
            ? _byText(a, b, 'job_number')
            : (a['dia'] as int).compareTo(b['dia']) != 0
            ? (a['dia'] as int).compareTo(b['dia'])
            : (a['position'] as int).compareTo(b['position']),
      );
      records.sort(
        (a, b) => _byText(a, b, 'production_date') != 0
            ? _byText(a, b, 'production_date')
            : _byText(a, b, 'shift'),
      );
      return {'programs': totals, 'entries': records};
    });
  }
}

class _MillSnapshot {
  _MillSnapshot(
    List<RowData> jobs,
    this.programs,
    List<RowData> parties,
    List<RowData> specs,
    List<RowData> entries,
  ) : jobs = {for (final j in jobs) j['id']: j},
      parties = {for (final p in parties) p['id']: p},
      specs = {for (final s in specs) s['id']: s} {
    for (final entry in entries) {
      (entriesByProgram[entry['program_id']] ??= []).add(entry);
    }
    for (final program in programs) {
      (programsByJob[program['job_id']] ??= []).add(program);
    }
  }
  final Map<String, RowData> jobs, parties, specs;
  final List<RowData> programs;
  final entriesByProgram = <String, List<RowData>>{};
  final programsByJob = <String, List<RowData>>{};

  String partyName(RowData job) =>
      parties[job['party_id']]?['name'] as String? ?? '';
  List<RowData> byJob(String jobId) =>
      [...?programsByJob[jobId]]
        ..sort((a, b) => (a['position'] as int).compareTo(b['position']));

  RowData programTotals(RowData p) {
    final entries = entriesByProgram[p['id']] ?? [];
    final produced = entries.fold(0, (sum, e) => sum + grams(e['quantity_kg']));
    final ordered = grams(p['ordered_kg']);
    return {
      ...p,
      'specification': specs[p['specification_id']]?['name'] ?? '',
      'produced_kg': kg(produced),
      'balance_kg': kg(ordered - produced),
      'completed': produced >= ordered,
      'has_history': entries.isNotEmpty,
    };
  }

  RowData jobTotals(RowData job) {
    final lines = byJob(job['id']).map(programTotals).toList();
    return {
      ...job,
      'party': partyName(job),
      'ordered_kg': kg(lines.fold(0, (sum, p) => sum + grams(p['ordered_kg']))),
      'produced_kg': kg(
        lines.fold(0, (sum, p) => sum + grams(p['produced_kg'])),
      ),
      'completed':
          lines.isNotEmpty && lines.every((p) => p['completed'] == true),
    };
  }
}

String friendlyError(Object error) => error is MillError
    ? error.message
    : 'Could not complete the request. Check your device storage and try again.';
