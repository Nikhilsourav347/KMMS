import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ukm/core/domain.dart';
import 'package:ukm/features/reports/pdf_report.dart';
import 'package:ukm/features/reports/report_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final date = DateTime(2026, 11, 25);
  final program = <String, dynamic>{
    'job_number': 'QA-001',
    'job_date': '2026-11-20',
    'party': 'Report fixture party',
    'yarn': '60s dyed cotton and recycled polyester blend',
    'dia': 28,
    'position': 1,
    'loop_length': 2.65,
    'specification': 'Single jersey',
    'remarks': List.filled(
      4,
      'Use the specified yarn lot and check the fabric for consistency.',
    ).join(' '),
    'ordered_kg': 500,
    'produced_kg': 300,
    'balance_kg': 200,
    'period_kg': 24.75,
    'completed': false,
  };
  final entries = [
    for (var i = 0; i < 66; i++)
      <String, dynamic>{
        'production_date': '2026-11-25',
        'shift': i.isEven ? 'morning' : 'night',
        'job_number': 'QA-001',
        'party': 'Report fixture party',
        'dia': 28,
        'program_position': i % 3 + 1,
        'specification': 'Single jersey',
        'quantity_kg': 1.125,
      },
  ];

  for (final kind in ReportKind.values) {
    test(
      '${kind.label} PDF renders branded report bytes and has the expected filename',
      () async {
        final request = ReportRequest(
          kind: kind,
          start: kind == ReportKind.job ? null : date,
          end: switch (kind) {
            ReportKind.job => null,
            ReportKind.range => DateTime(2026, 11, 27),
            _ => date,
          },
          shift: kind == ReportKind.shift ? Shift.morning : null,
          jobNumber: kind == ReportKind.job || kind == ReportKind.range
              ? 'QA-001'
              : null,
        );
        final data = ReportData(
          request,
          {
            'programs': [
              program,
              {...program, 'position': 2},
              {...program, 'position': 3},
            ],
            'entries': entries,
          },
          generated: DateTime.utc(2026, 11, 25, 6),
          reference: 'UKM-QA-001',
        );
        expect(data.ordered, grams('1500'));
        expect(data.byDia[28], (grams('37.125'), grams('37.125')));
        expect(request.filename, switch (kind) {
          ReportKind.job => 'UKM_Job_QA-001_Production_Report.pdf',
          ReportKind.daily => 'UKM_Daily_Report_2026-11-25.pdf',
          ReportKind.shift => 'UKM_Day_Shift_Report_2026-11-25.pdf',
          ReportKind.range => 'UKM_Job_QA-001_2026-11-25_to_2026-11-27.pdf',
        });
        final bytes = await buildReportPdf(data);
        expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        expect(bytes.length, greaterThan(10000));
        final directory = Platform.environment['UKM_PDF_QA_DIR'];
        if (directory != null) {
          await Directory(directory).create(recursive: true);
          await File('$directory/${request.filename}').writeAsBytes(bytes);
        }
      },
    );
  }

  test(
    'range combines both shifts and includes both endpoints for the selected job',
    () {
      final data = ReportData(
        ReportRequest(
          kind: ReportKind.range,
          start: date,
          end: DateTime(2026, 11, 26),
          jobNumber: 'QA-001',
        ),
        {
          'programs': [],
          'entries': [
            entries[0],
            entries[1],
            {...entries[0], 'production_date': '2026-11-26', 'quantity_kg': 2},
            {
              ...entries[0],
              'production_date': '2026-11-24',
              'quantity_kg': 100,
            },
            {
              ...entries[0],
              'production_date': '2026-11-27',
              'quantity_kg': 100,
            },
            {...entries[0], 'job_number': 'UNRELATED', 'quantity_kg': 100},
          ],
        },
        generated: date,
        reference: 'fixture',
      );
      expect(data.dailyProduction, {'2026-11-25': 2250, '2026-11-26': 2000});
      final shift = ReportData(
        ReportRequest(
          kind: ReportKind.shift,
          start: date,
          end: date,
          shift: Shift.night,
        ),
        {
          'programs': [],
          'entries': [
            entries[0],
            entries[1],
            {...entries[1], 'production_date': '2026-11-26'},
          ],
        },
        generated: date,
        reference: 'fixture',
      );
      expect(shift.filteredEntries, [entries[1]]);
    },
  );
}
