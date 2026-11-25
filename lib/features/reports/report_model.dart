import '../../core/domain.dart';

enum ReportKind {
  job('Job-wise', 'Job Production Report'),
  daily('Day-wise', 'Daily Production Report'),
  shift('Date & shift', 'Shift Production Report'),
  range('Date range', 'Date Range Production Report');

  const ReportKind(this.label, this.title);
  final String label;
  final String title;
}

class ReportRequest {
  const ReportRequest({
    required this.kind,
    this.start,
    this.end,
    this.shift,
    this.jobId,
    this.jobNumber,
    this.partyId,
    this.partyName,
    this.dia,
  });
  final ReportKind kind;
  final DateTime? start, end;
  final Shift? shift;
  final String? jobId, jobNumber, partyId, partyName;
  final int? dia;

  String get filterLabel => [
    if (start != null && (end == null || start == end)) prettyDate(start!),
    if (start != null && end != null && start != end)
      '${prettyDate(start!)} to ${prettyDate(end!)}',
    if (shift != null) '${shift!.label} shift',
    if (jobNumber != null) 'Job $jobNumber',
    if (partyName != null) 'Party $partyName',
    if (dia != null) 'DIA $dia',
  ].join(' · ');

  String get filename {
    String safe(String input) {
      final value = input.replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '_');
      return value.length > 60 ? value.substring(0, 60) : value;
    }

    return switch (kind) {
      ReportKind.job => 'UKM_Job_${safe(jobNumber!)}_Production_Report.pdf',
      ReportKind.daily => 'UKM_Daily_Report_${isoDate(start!)}.pdf',
      ReportKind.shift =>
        'UKM_${shift!.label}_Shift_Report_${isoDate(start!)}.pdf',
      ReportKind.range =>
        'UKM_Job_${safe(jobNumber!)}_${isoDate(start!)}_to_${isoDate(end!)}.pdf',
    };
  }
}

class ReportData {
  ReportData(
    this.request,
    RowData payload, {
    required this.generated,
    required this.reference,
  }) : programs = rows(payload['programs']),
       entries = rows(payload['entries']);
  final ReportRequest request;
  final List<RowData> programs, entries;
  final DateTime generated;
  final String reference;

  int sumPrograms(String field) =>
      programs.fold(0, (total, row) => total + grams(row[field]));
  int get ordered => sumPrograms('ordered_kg');
  int get produced => sumPrograms('produced_kg');
  int get balance => sumPrograms('balance_kg');
  int get period => sumPrograms('period_kg');
  List<RowData> get filteredEntries {
    final start = request.start == null ? null : isoDate(request.start!);
    final end = request.end == null ? null : isoDate(request.end!);
    return entries.where((row) {
      final date = row['production_date'] as String;
      final matchesJob = request.jobId != null && row['job_id'] != null
          ? row['job_id'] == request.jobId
          : request.jobNumber == null || row['job_number'] == request.jobNumber;
      return (start == null || date.compareTo(start) >= 0) &&
          (end == null || date.compareTo(end) <= 0) &&
          (request.shift == null || row['shift'] == request.shift!.name) &&
          matchesJob;
    }).toList();
  }

  Map<String, int> get dailyProduction {
    final totals = <String, int>{};
    for (final entry in filteredEntries) {
      final date = entry['production_date'] as String;
      totals.update(
        date,
        (sum) => sum + grams(entry['quantity_kg']),
        ifAbsent: () => grams(entry['quantity_kg']),
      );
    }
    return totals;
  }

  Map<int, (int, int)> get byDia {
    final totals = <int, (int, int)>{};
    for (final row in entries) {
      final dia = row['dia'] as int;
      final (morning, night) = totals[dia] ?? (0, 0);
      final output = grams(row['quantity_kg']);
      totals[dia] = row['shift'] == Shift.morning.name
          ? (morning + output, night)
          : (morning, night + output);
    }
    return totals;
  }
}

String jobStatus(RowData row) =>
    row['completed'] == true ? 'Completed' : 'Pending';
String shiftName(RowData row) => Shift.values.byName(row['shift']).label;
