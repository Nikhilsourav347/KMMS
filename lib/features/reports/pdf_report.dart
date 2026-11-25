import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/domain.dart';
import 'report_model.dart';

const _blue = PdfColor.fromInt(0xFF3568A8);
const _cream = PdfColor.fromInt(0xFFFFF8E7);
const _ink = PdfColor.fromInt(0xFF202731);
const _line = PdfColor.fromInt(0xFFDBD1BF);

PdfPageFormat reportFormat(ReportKind kind) =>
    kind == ReportKind.job || kind == ReportKind.daily
    ? PdfPageFormat.a4
    : PdfPageFormat.a4.landscape;

Future<Uint8List> buildReportPdf(ReportData report) async {
  final image = await rootBundle.load(logoAsset);
  final regular = await rootBundle.load('assets/fonts/roboto-regular.ttf');
  final strong = await rootBundle.load('assets/fonts/roboto-bold.ttf');
  final logo = pw.MemoryImage(
    image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes),
  );
  final body = pw.Font.ttf(regular);
  final bold = pw.Font.ttf(strong);
  final doc = pw.Document(
    title: report.request.kind.title,
    author: companyName,
    subject: report.reference,
    theme: pw.ThemeData.withFont(base: body, bold: bold),
  );
  final job = report.request.kind == ReportKind.job;
  final daily = report.request.kind == ReportKind.daily;
  final compact = job || daily;
  final jobMeta = report.programs.firstOrNull;
  final summary = job
      ? _jobRows(report.programs)
      : daily
      ? _dayRows(report.programs)
      : <_OrderRow>[];
  final summaryBalance = summary.fold(0, (sum, row) => sum + row.balance);
  final tableText = pw.TextStyle(fontSize: 8, color: _ink);
  final titleStyle = pw.TextStyle(
    fontSize: 13,
    fontWeight: pw.FontWeight.bold,
    color: _blue,
  );

  pw.Widget table(
    List<String> headers,
    List<List<String>> data,
    List<double> widths, {
    Set<int> numeric = const {},
  }) => pw.TableHelper.fromTextArray(
    headers: headers,
    data: data,
    headerDecoration: const pw.BoxDecoration(color: _blue),
    headerStyle: pw.TextStyle(
      color: PdfColors.white,
      fontWeight: pw.FontWeight.bold,
      fontSize: 8,
    ),
    cellStyle: tableText,
    oddRowDecoration: const pw.BoxDecoration(color: _cream),
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _line, width: .35),
      bottom: pw.BorderSide(color: _line, width: .5),
    ),
    columnWidths: {
      for (final (i, width) in widths.indexed) i: pw.FlexColumnWidth(width),
    },
    cellAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
    headerAlignments: {for (final i in numeric) i: pw.Alignment.centerRight},
    cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 7),
  );

  pw.Widget heading(String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 15, bottom: 7),
    child: pw.Text(value, style: titleStyle),
  );
  pw.Widget metric(String title, String value) => pw.Expanded(
    child: pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: const pw.TextStyle(fontSize: 8, color: _ink)),
          pw.SizedBox(height: 4),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 16,
              color: _blue,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        ],
      ),
    ),
  );

  doc.addPage(
    pw.MultiPage(
      maxPages: 500,
      pageFormat: reportFormat(report.request.kind),
      margin: const pw.EdgeInsets.fromLTRB(34, 30, 34, 30),
      header: (context) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 13),
        padding: const pw.EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: pw.BoxDecoration(
          color: _blue,
          borderRadius: pw.BorderRadius.circular(7),
        ),
        child: pw.Row(
          children: [
            pw.Image(logo, width: 42, height: 42),
            pw.SizedBox(width: 11),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName.toUpperCase(),
                    style: pw.TextStyle(
                      color: _cream,
                      fontSize: 19,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    report.request.kind.title,
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            pw.Text(
              report.reference,
              style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
            ),
          ],
        ),
      ),
      footer: (context) => pw.Column(
        children: [
          pw.Divider(color: _line, thickness: .5),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(companyName, style: tableText),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: tableText,
              ),
            ],
          ),
        ],
      ),
      build: (context) => [
        pw.Text(
          report.request.filterLabel,
          style: const pw.TextStyle(fontSize: 11, color: _ink),
        ),
        pw.SizedBox(height: 4),
        pw.Text(
          'Generated ${dbTimeLabel(report.generated.toIso8601String())}',
          style: tableText,
        ),
        if (jobMeta != null && job) ...[
          pw.SizedBox(height: 6),
          pw.Text(
            'Party ${jobMeta['party']}  |  Job date ${dbDateLabel(jobMeta['job_date'])}',
            style: tableText,
          ),
          pw.Text('Yarn ${jobMeta['yarn']}', style: tableText),
          pw.Text(
            'Status ${report.programs.every((p) => p['completed'] == true) ? 'Completed' : 'Pending'}',
            style: tableText,
          ),
        ],
        pw.SizedBox(height: 12),
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(vertical: 11),
          decoration: pw.BoxDecoration(
            color: _cream,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Row(
            children: [
              metric(
                compact ? 'Total ordered' : 'Ordered',
                '${kg(report.ordered)} kg',
              ),
              if (!compact)
                metric('Period production', '${kg(report.period)} kg'),
              metric(
                'Balance',
                '${kg(compact ? summaryBalance : report.balance)} kg',
              ),
              if (!compact)
                metric(
                  'Order completion',
                  percent(report.produced, report.ordered),
                ),
            ],
          ),
        ),
        if (compact && summary.isNotEmpty) ...[
          heading(
            daily ? 'Customer and job details (kg)' : 'DIA order details (kg)',
          ),
          table(
            [
              if (daily) ...['Customer', 'Job'],
              'DIA',
              'Design',
              'Ordered',
              'Balance',
            ],
            [
              for (final row in summary)
                [
                  if (daily) ...[row.party, row.job],
                  row.dia,
                  row.design,
                  kg(row.ordered),
                  kg(row.balance),
                ],
            ],
            daily ? [1.8, 1.05, .55, 1.3, .85, .85] : [.65, 2, 1, 1],
            numeric: daily ? {4, 5} : {2, 3},
          ),
        ],
        if (!compact && report.ordered > 0) ...[
          pw.SizedBox(height: 4),
          pw.LinearProgressIndicator(
            value: (report.produced / report.ordered).clamp(0.0, 1.0),
            backgroundColor: _cream,
            valueColor: _blue,
            minHeight: 4,
          ),
        ],
        if (report.programs.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(vertical: 16),
            child: pw.Text('No matching production records.', style: tableText),
          ),
        if (!compact && report.byDia.isNotEmpty) ...[
          heading('DIA and shift totals (kg)'),
          table(
            ['DIA', 'Day', 'Night', 'Total'],
            [
              for (final dia in dias)
                if (report.byDia[dia] case final amounts?)
                  [
                    '$dia',
                    kg(amounts.$1),
                    kg(amounts.$2),
                    kg(amounts.$1 + amounts.$2),
                  ],
            ],
            [1, 1, 1, 1],
            numeric: {1, 2, 3},
          ),
        ],
        if (!compact && report.programs.isNotEmpty) ...[
          heading('Program quantities (kg)'),
          if (!job)
            pw.Text(
              'Ordered, lifetime output and balance are counted once per program. Period output follows the selected filters.',
              style: tableText,
            ),
          if (!job) pw.SizedBox(height: 5),
          table(
            [
              if (!job) 'Job / Party / Yarn',
              'DIA / Program',
              'Loop',
              'Design / Remarks',
              'Ordered',
              if (!job) 'Period',
              'Produced',
              'Balance',
              'Done',
            ],
            [
              for (final p in report.programs)
                [
                  if (!job) '${p['job_number']} / ${p['party']}\n${p['yarn']}',
                  '${p['dia']} / ${p['position']}',
                  '${p['loop_length']}',
                  '${p['specification']}${(p['remarks'] as String).isEmpty ? '' : '\n${p['remarks']}'}',
                  kg(grams(p['ordered_kg'])),
                  if (!job) kg(grams(p['period_kg'])),
                  kg(grams(p['produced_kg'])),
                  kg(grams(p['balance_kg'])),
                  percent(grams(p['produced_kg']), grams(p['ordered_kg'])),
                ],
            ],
            [if (!job) 2.3, 1.15, .65, 3, .85, if (!job) .85, .9, .85, .8],
            numeric: job ? {1, 3, 4, 5, 6} : {2, 4, 5, 6, 7, 8},
          ),
        ],
        if (!compact && report.entries.isNotEmpty) ...[
          heading('Production history'),
          table(
            [
              'Date',
              'Shift',
              if (!job) 'Job / Party',
              'DIA / Program',
              'Output (kg)',
            ],
            [
              for (final e in report.entries)
                [
                  dbDateLabel(e['production_date']),
                  shiftName(e),
                  if (!job) '${e['job_number']} / ${e['party']}',
                  '${e['dia']} / ${e['program_position']} · ${e['specification']}',
                  kg(grams(e['quantity_kg'])),
                ],
            ],
            [1.2, .85, if (!job) 2.2, 2.4, 1],
            numeric: {job ? 3 : 4},
          ),
        ],
        pw.Container(
          margin: const pw.EdgeInsets.only(top: 33),
          child: pw.Row(
            children: [
              for (final label in [
                'Manager signature',
                'Authorized verification',
              ])
                pw.Expanded(
                  child: pw.Padding(
                    padding: const pw.EdgeInsets.only(right: 24),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Divider(color: _line, thickness: .7),
                        pw.Text(label, style: tableText),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );
  return doc.save();
}

typedef _OrderRow = ({
  String party,
  String job,
  String dia,
  String design,
  int ordered,
  int balance,
});

List<_OrderRow> _jobRows(List<RowData> programs) => [
  for (final row in programs) _orderRow(row, 'balance_kg'),
];

List<_OrderRow> _dayRows(List<RowData> programs) => [
  for (final row
      in [...programs]..sort((a, b) {
        final party = cellText(a['party']).compareTo(cellText(b['party']));
        return party == 0
            ? cellText(a['job_number']).compareTo(cellText(b['job_number']))
            : party;
      }))
    _orderRow(row, 'balance_on_end_kg'),
];

_OrderRow _orderRow(RowData row, String balanceField) => (
  party: cellText(row['party']),
  job: cellText(row['job_number']),
  dia: cellText(row['dia']),
  design: cellText(row['specification']),
  ordered: grams(row['ordered_kg']),
  balance: grams(row[balanceField] ?? row['balance_kg']),
);
