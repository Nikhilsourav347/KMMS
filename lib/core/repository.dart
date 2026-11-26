import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth.dart';
import 'domain.dart';

export 'auth.dart' show friendlyError;

final millDataProvider = Provider<MillData?>((ref) => null);

final repositoryProvider = Provider<MillData>(
  (ref) => ref.watch(millDataProvider)!,
);

enum Dataset { machines, schedule, jobs, production }

final revisionsProvider = StreamProvider.autoDispose.family<int, Dataset>(
  (ref, dataset) => ref.watch(repositoryProvider).updates(dataset),
);

final registeredMachinesProvider = FutureProvider.autoDispose<List<RowData>>((
  ref,
) {
  ref.watch(
    revisionsProvider(Dataset.machines).select((update) => update.value),
  );
  return ref.watch(repositoryProvider).registeredMachines();
});

final activeDiasProvider = Provider.autoDispose<AsyncValue<List<String>>>(
  (ref) => ref
      .watch(registeredMachinesProvider)
      .whenData(
        (machines) => sortedDias(machines.map(machineDiaValue).nonNulls),
      ),
);

final jobsProvider = FutureProvider.autoDispose<List<RowData>>((ref) {
  ref.watch(revisionsProvider(Dataset.jobs).select((update) => update.value));
  return ref.watch(repositoryProvider).jobs();
});

typedef MachineScheduleRow = ({RowData machine, Set<String> bookedDates});

typedef MachineStatus = ({bool running, int revision});
typedef MachineStatusUpdate = ({int id, String date, MachineStatus status});

abstract interface class MillData {
  MillAuth get auth;
  Stream<int> updates(Dataset dataset);
  // A null event requests a full snapshot after reconnects or registry changes.
  Stream<MachineStatusUpdate?> get machineStatusUpdates;
  Future<void> close();
  Future<List<RowData>> registeredMachines();
  Future<void> saveMachine({
    int? id,
    required String number,
    required String dia,
    String type = '',
    String specifications = '',
  });
  Future<bool> removeMachine(int id);
  Future<List<RowData>> machineDay(DateTime date);
  Future<MachineStatus> setRunning(int id, DateTime date, bool running);
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
    String? dia,
  });
  Future<List<String>> reportDias(DateTime start, DateTime end);
}
