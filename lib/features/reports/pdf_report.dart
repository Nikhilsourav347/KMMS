import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/domain.dart';
import 'report_model.dart';

const _blue = PdfColor.fromInt(0xFF3568A8);
const _darkBlue = PdfColor.fromInt(0xFF244A7B);
const _cream = PdfColor.fromInt(0xFFFFF8E7);
const _ink = PdfColor.fromInt(0xFF202731);
const _line = PdfColor.fromInt(0xFFDBD1BF);
const _body = pw.TextStyle(fontSize: 8.5, color: _ink);
final _title = pw.TextStyle(
  fontSize: 13,
  fontWeight: pw.FontWeight.bold,
  color: _darkBlue,
);
final _bold = pw.TextStyle(
  fontSize: 8.5,
  fontWeight: pw.FontWeight.bold,
  color: _darkBlue,
);
final _columnTitle = pw.TextStyle(
  fontSize: 8,
  fontWeight: pw.FontWeight.bold,
  color: PdfColors.white,
);

final reportFormat = PdfPageFormat.a4.landscape;

pw.Table _table(
  List<String> headers,
  Iterable<List<String>> data,
  List<double> widths, {
  required int numericFrom,
  List<String>? subtotal,
}) {
  pw.TableRow row(
    List<String> cells,
    int index, {
    bool header = false,
    bool total = false,
  }) => pw.TableRow(
    repeat: header,
    decoration: pw.BoxDecoration(
      color: header
          ? _blue
          : total || index.isOdd
          ? _cream
          : PdfColors.white,
    ),
    children: [
      for (final (i, cell) in cells.indexed)
        pw.Container(
          alignment: i >= numericFrom
              ? pw.Alignment.centerRight
              : pw.Alignment.centerLeft,
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          child: pw.Text(
            cell,
            style: header ? _columnTitle : (total ? _bold : _body),
            textAlign: i >= numericFrom
                ? pw.TextAlign.right
                : pw.TextAlign.left,
          ),
        ),
    ],
  );

  return pw.Table(
    children: [
      row(headers, 0, header: true),
      for (final (i, cells) in data.indexed) row(cells, i),
      if (subtotal != null) row(subtotal, 0, total: true),
    ],
    border: const pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _line, width: .35),
      bottom: pw.BorderSide(color: _line, width: .5),
    ),
    columnWidths: {
      for (final (i, width) in widths.indexed) i: pw.FlexColumnWidth(width),
    },
  );
}

pw.Widget _heading(String value) => pw.Padding(
  padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
  child: pw.Text(value, style: _title),
);

pw.Widget _total(String label, int amount) => pw.Container(
  padding: const pw.EdgeInsets.all(10),
  decoration: const pw.BoxDecoration(color: _blue),
  child: pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Expanded(child: pw.Text(label, style: _columnTitle)),
      pw.Text('${kg(amount)} kg', style: _columnTitle),
    ],
  ),
);

List<pw.Widget> _reportSections(ReportData report) => [
  if ((report.request.kind == ReportKind.job
          ? report.programs.firstOrNull
          : null)
      case final first?) ...[
    pw.Text(
      'Job date ${dbDateLabel(first['job_date'])}  ·  Yarn ${cellText(first['yarn'])}',
      style: _body,
    ),
    pw.SizedBox(height: 8),
  ],
  pw.Wrap(
    spacing: 7,
    runSpacing: 7,
    children: [
      for (final (label, value) in report.productionSummary)
        pw.Container(
          width: 117,
          padding: const pw.EdgeInsets.all(9),
          decoration: const pw.BoxDecoration(color: _cream),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(label, style: _body),
              pw.SizedBox(height: 4),
              pw.Text(value, style: _title),
            ],
          ),
        ),
    ],
  ),
  for (final day in report.productionDays.entries) ...[
    pw.NewPage(freeSpace: 113),
    _heading('${dbDateLabel(day.key)}  |  Production (kg)'),
    _table(
      report.productionColumns([
        '${dayProgramHeaders.first}\n${dbDateLabel(day.key)}',
        ...dayProgramHeaders.skip(1),
      ]),
      day.value.map((row) => report.productionColumns(dayProgramCells(row))),
      report.productionColumns([
        1.25,
        1.65,
        .82,
        .7,
        .6,
        1.65,
        .83,
        .8,
        .88,
        .9,
        .95,
        .9,
      ]),
      numericFrom: 6,
      subtotal: report.subtotalCells(day.key, day.value),
    ),
  ],
  if (report.unproducedPrograms.isNotEmpty) ...[
    pw.NewPage(freeSpace: 95),
    _heading('Programs without recorded production (kg)'),
    _table(
      unproducedProgramHeaders,
      report.unproducedPrograms.map(unproducedProgramCells),
      [1, .8, .8, 2, 1, 1],
      numericFrom: 4,
    ),
  ],
  pw.NewPage(freeSpace: 64),
  pw.SizedBox(height: 13),
  _total(report.totalLabel, report.period),
  pw.Padding(
    padding: const pw.EdgeInsets.only(top: 8),
    child: pw.Text(report.balanceLabel, style: _bold),
  ),
];

Future<Uint8List> buildReportPdf(ReportData report) async {
  final request = report.request;
  if (!report.hasData) {
    throw StateError('No production records found for the selected filters.');
  }
  final image = await rootBundle.load(logoAsset);
  final regular = await rootBundle.load('assets/fonts/roboto-regular.ttf');
  final strong = await rootBundle.load('assets/fonts/roboto-bold.ttf');
  final logo = pw.MemoryImage(
    image.buffer.asUint8List(image.offsetInBytes, image.lengthInBytes),
  );
  final doc = pw.Document(
    title: request.kind.title,
    author: companyName,
    subject: report.reference,
    theme: pw.ThemeData.withFont(
      base: pw.Font.ttf(regular),
      bold: pw.Font.ttf(strong),
    ),
  );
  final party =
      request.partyName ??
      (request.jobNumber == null
          ? null
          : report.programs.firstOrNull?['party']?.toString());
  final filterLines = [
    if (request.kind == ReportKind.range)
      'From ${prettyDate(request.start!)}  ·  To ${prettyDate(request.end!)}'
    else if (request.start != null)
      prettyDate(request.start!),
    if (request.shift != null) '${request.shift!.label} shift',
    if (request.jobNumber != null) 'Job ${request.jobNumber}',
    if (party != null) 'Party $party',
    if (request.dia != null) 'DIA ${request.dia}',
  ];

  doc.addPage(
    pw.MultiPage(
      // A data-derived ceiling guards against a layout error in debug builds.
      maxPages: 8 + report.filteredEntries.length * 2 + report.programs.length,
      pageFormat: reportFormat,
      margin: const pw.EdgeInsets.fromLTRB(34, 28, 34, 28),
      header: (_) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(11),
        decoration: const pw.BoxDecoration(color: _blue),
        child: pw.Row(
          children: [
            pw.Image(logo, width: 43, height: 43, fit: pw.BoxFit.contain),
            pw.SizedBox(width: 11),
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    companyName.toUpperCase(),
                    style: pw.TextStyle(
                      color: _cream,
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 2),
                  pw.Text(
                    request.kind.title,
                    style: const pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 11,
                    ),
                  ),
                  if (filterLines.isNotEmpty) ...[
                    pw.SizedBox(height: 4),
                    pw.Text(filterLines.join('  ·  '), style: _columnTitle),
                  ],
                ],
              ),
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
              pw.Text(companyName, style: _body),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: _body,
              ),
            ],
          ),
        ],
      ),
      build: (_) => [
        pw.Text(
          'Generated ${dbTimeLabel(report.generated.toIso8601String())}  |  ${report.reference}',
          style: _body,
        ),
        pw.SizedBox(height: 10),
        ..._reportSections(report),
      ],
    ),
  );
  return doc.save();
}
