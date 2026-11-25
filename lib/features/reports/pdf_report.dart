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
    kind != ReportKind.shift ? PdfPageFormat.a4 : PdfPageFormat.a4.landscape;

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
  pw.Widget summary(String label, int amount) => pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: const pw.BoxDecoration(color: _cream),
    child: pw.Text('$label · ${kg(amount)} kg', style: titleStyle),
  );

  final request = report.request;
  final programs = report.programs;
  final entries = report.filteredEntries;
  final dailyTotals = request.kind == ReportKind.range
      ? report.dailyProduction
      : const <String, int>{};
  final total = entries.fold(0, (sum, row) => sum + grams(row['quantity_kg']));
  final jobMeta = programs.firstOrNull;
  final content = switch (request.kind) {
    ReportKind.job => <pw.Widget>[
      pw.Text(
        'Job ${request.jobNumber ?? cellText(jobMeta?['job_number'])}',
        style: titleStyle,
      ),
      if (jobMeta != null) ...[
        pw.Text('Customer: ${cellText(jobMeta['party'])}', style: tableText),
        pw.Text(
          'Job date: ${dbDateLabel(jobMeta['job_date'])}',
          style: tableText,
        ),
        pw.Text('Yarn: ${cellText(jobMeta['yarn'])}', style: tableText),
        heading('Program summary'),
        table(
          [
            'Program details',
            'DIA',
            'Design',
            'Required (kg)',
            'Completed (kg)',
            'Balance (kg)',
          ],
          [
            for (final row in programs)
              [
                'Program ${cellText(row['position'])}\nLoop ${cellText(row['loop_length'])}',
                cellText(row['dia']),
                cellText(row['specification']),
                kg(grams(row['ordered_kg'])),
                kg(grams(row['produced_kg'])),
                kg(grams(row['balance_kg'])),
              ],
          ],
          [1.35, .48, 1.5, 1, 1, .85],
          numeric: {3, 4, 5},
        ),
      ] else
        pw.Text('No matching programs.', style: tableText),
      pw.SizedBox(height: 12),
      summary('Total production', report.produced),
    ],
    ReportKind.daily => <pw.Widget>[
      pw.Text(request.filterLabel, style: titleStyle),
      pw.Text(
        'Generated ${dbTimeLabel(report.generated.toIso8601String())}',
        style: tableText,
      ),
      pw.SizedBox(height: 12),
      pw.Row(
        children: [
          pw.Expanded(child: summary('Total ordered', report.ordered)),
          pw.Expanded(
            child: summary(
              'Balance',
              programs.fold(
                0,
                (sum, row) =>
                    sum + grams(row['balance_on_end_kg'] ?? row['balance_kg']),
              ),
            ),
          ),
        ],
      ),
      if (programs.isNotEmpty) ...[
        heading('Customer and job details (kg)'),
        table(
          ['Customer', 'Job', 'DIA', 'Design', 'Ordered', 'Balance'],
          [
            for (final row
                in (programs.toList()..sort((a, b) {
                  final party = cellText(
                    a['party'],
                  ).compareTo(cellText(b['party']));
                  return party == 0
                      ? cellText(
                          a['job_number'],
                        ).compareTo(cellText(b['job_number']))
                      : party;
                })))
              [
                cellText(row['party']),
                cellText(row['job_number']),
                cellText(row['dia']),
                cellText(row['specification']),
                kg(grams(row['ordered_kg'])),
                kg(grams(row['balance_on_end_kg'] ?? row['balance_kg'])),
              ],
          ],
          [1.8, 1.05, .55, 1.3, .85, .85],
          numeric: {4, 5},
        ),
      ] else
        pw.Text('No matching production records.', style: tableText),
    ],
    ReportKind.shift => <pw.Widget>[
      pw.Text(request.filterLabel, style: titleStyle),
      if (entries.isNotEmpty) ...[
        heading('Production recorded for this shift'),
        table(
          ['Job', 'Customer', 'DIA', 'Program', 'Design', 'Production (kg)'],
          [
            for (final row in entries)
              [
                cellText(row['job_number']),
                cellText(row['party']),
                cellText(row['dia']),
                cellText(row['program_position']),
                cellText(row['specification']),
                kg(grams(row['quantity_kg'])),
              ],
          ],
          [1, 1.7, .5, .8, 1.55, 1],
          numeric: {5},
        ),
      ] else
        pw.Text('No matching production records.', style: tableText),
      pw.SizedBox(height: 12),
      summary('Total production', total),
    ],
    ReportKind.range => <pw.Widget>[
      pw.Text('Job ${cellText(request.jobNumber)}', style: titleStyle),
      pw.Text(
        'Start date: ${dbDateLabel(request.start == null ? null : isoDate(request.start!))}',
        style: tableText,
      ),
      pw.Text(
        'End date: ${dbDateLabel(request.end == null ? null : isoDate(request.end!))}',
        style: tableText,
      ),
      if (entries.isNotEmpty) ...[
        heading('Date-wise production'),
        table(
          ['Date', 'Production (kg)'],
          [
            for (final date in (dailyTotals.keys.toList()..sort()))
              [dbDateLabel(date), kg(dailyTotals[date]!)],
          ],
          [1, 1],
          numeric: {1},
        ),
      ] else
        pw.Text('No matching production records.', style: tableText),
      pw.SizedBox(height: 12),
      summary('Grand total production', total),
    ],
  };

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
      build: (context) => content,
    ),
  );
  return doc.save();
}
