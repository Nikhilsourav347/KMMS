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
    'period_kg': 100,
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
          jobNumber: kind == ReportKind.job ? 'QA/001' : null,
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
          ReportKind.job => 'UKM_Job_QA_001_Production_Report.pdf',
          ReportKind.daily => 'UKM_Daily_Report_2026-11-25.pdf',
          ReportKind.shift => 'UKM_Day_Shift_Report_2026-11-25.pdf',
          ReportKind.range => 'UKM_Production_2026-11-25_to_2026-11-27.pdf',
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
}
