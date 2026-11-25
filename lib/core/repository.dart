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
  (ref, _) => ref.watch(repositoryProvider).updates,
);

final jobsProvider = FutureProvider.autoDispose<List<RowData>>((ref) {
  ref.watch(revisionsProvider(Dataset.jobs));
  return ref.watch(repositoryProvider).jobs();
});

typedef MachineScheduleRow = ({RowData machine, Set<String> bookedDates});

abstract interface class MillData {
  MillAuth get auth;
  Stream<int> get updates;
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
