import 'dart:math';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/domain.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'pdf_report.dart';
import 'report_model.dart';

final _partiesProvider = FutureProvider.autoDispose<List<RowData>>((ref) {
  ref.watch(revisionsProvider(Dataset.jobs));
  return ref.read(repositoryProvider).names('parties');
});

final _reportProvider = FutureProvider.autoDispose
    .family<ReportData, ReportRequest>((ref, filters) async {
      ref.watch(revisionsProvider(Dataset.production));
      final result = await ref
          .read(repositoryProvider)
          .report(
            start: filters.start,
            end: filters.end,
            shift: filters.shift,
            jobId: filters.jobId,
            partyId: filters.partyId,
            dia: filters.dia,
          );
      final generated = DateTime.now().toUtc();
      final suffix = Random.secure()
          .nextInt(0x1000000)
          .toRadixString(16)
          .padLeft(6, '0')
          .toUpperCase();
      return ReportData(
        filters,
        result,
        generated: generated,
        reference: 'UKM-${generated.millisecondsSinceEpoch}-$suffix',
      );
    });

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportKind kind = ReportKind.job;
  DateTime start = indiaToday();
  DateTime end = indiaToday();
  Shift shift = Shift.morning;
  String? jobId;
  String? partyId;
  int? dia;
  ReportRequest? request;

  void selectReport(ReportKind value) {
    if (kind == value) return;
    setState(() {
      kind = value;
      request = null;
      jobId = null;
      partyId = null;
      dia = null;
    });
  }

  void update(VoidCallback change) => setState(() {
    change();
    request = null;
  });

  @override
  Widget build(BuildContext context) {
    final jobs = ref.watch(jobsProvider);
    final parties = kind == ReportKind.range
        ? ref.watch(_partiesProvider)
        : const AsyncData(<RowData>[]);
    final snapshot = request == null
        ? null
        : ref.watch(_reportProvider(request!));
    final usesJobs = kind == ReportKind.job || kind == ReportKind.range;
    final pickedJob = usesJobs
        ? jobs.value?.where((j) => j['id'] == jobId).firstOrNull
        : null;
    final pickedParty = parties.value
        ?.where((p) => p['id'] == partyId)
        .firstOrNull;
    return PageBody(
      children: [
        const SectionTitle(
          'Reports',
          detail: 'Review mill production and generate a company PDF.',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in ReportKind.values)
                    ChoiceChip(
                      label: Text(option.label),
                      selected: kind == option,
                      onSelected: (_) => selectReport(option),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (kind != ReportKind.job)
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DateField(
                      kind == ReportKind.range ? 'From' : 'Production date',
                      start,
                      (date) => update(() {
                        start = date;
                        if (start.isAfter(end)) end = start;
                      }),
                      last: indiaToday(),
                    ),
                    if (kind == ReportKind.range)
                      DateField(
                        'To',
                        end,
                        (date) => update(() => end = date),
                        first: start,
                        last: indiaToday(),
                      ),
                    if (kind == ReportKind.shift)
                      SegmentedButton<Shift>(
                        segments: [
                          for (final value in Shift.values)
                            ButtonSegment(
                              value: value,
                              label: Text(value.label),
                            ),
                        ],
                        selected: {shift},
                        onSelectionChanged: (value) =>
                            update(() => shift = value.first),
                      ),
                  ],
                ),
              if (usesJobs) ...[
                const SizedBox(height: 10),
                loadView(
                  jobs,
                  (results) => SearchPicker(
                    label: 'Select job number',
                    value: jobId,
                    options: {
                      for (final j in results)
                        j['id'] as String: '${j['job_number']} · ${j['party']}',
                    },
                    onChanged: (value) => update(() => jobId = value),
                  ),
                  () => ref.invalidate(jobsProvider),
                ),
              ],
              if (kind == ReportKind.range) ...[
                const SizedBox(height: 9),
                loadView(
                  parties,
                  (results) => SearchPicker(
                    label: 'Filter by party (optional)',
                    value: partyId,
                    options: {
                      for (final p in results)
                        p['id'] as String: p['name'] as String,
                    },
                    onChanged: (value) => update(() => partyId = value),
                  ),
                  () => ref.invalidate(_partiesProvider),
                ),
                const SizedBox(height: 9),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    width: 230,
                    child: DropdownButtonFormField<int>(
                      key: ValueKey(dia),
                      initialValue: dia ?? 0,
                      decoration: const InputDecoration(labelText: 'DIA'),
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('All DIA values'),
                        ),
                        for (final value in dias)
                          DropdownMenuItem(
                            value: value,
                            child: Text('DIA $value'),
                          ),
                      ],
                      onChanged: (value) =>
                          update(() => dia = value == 0 ? null : value),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 13),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  icon: const Icon(Icons.bar_chart),
                  label: const Text('Generate report'),
                  onPressed:
                      (usesJobs && pickedJob == null) ||
                          (jobId != null && pickedJob == null) ||
                          (partyId != null && pickedParty == null) ||
                          snapshot?.isLoading == true
                      ? null
                      : () => setState(() {
                          request = ReportRequest(
                            kind: kind,
                            start: kind == ReportKind.job ? null : start,
                            end: kind == ReportKind.job
                                ? null
                                : kind == ReportKind.range
                                ? end
                                : start,
                            shift: kind == ReportKind.shift ? shift : null,
                            jobId: pickedJob?['id'],
                            jobNumber: pickedJob?['job_number'],
                            partyId: pickedParty?['id'],
                            partyName: pickedParty?['name'],
                            dia: dia,
                          );
                        }),
                ),
              ),
            ],
          ),
        ),
        if (snapshot != null)
          loadView(
            snapshot,
            (data) => _ReportResult(data: data),
            () => ref.invalidate(_reportProvider(request!)),
          ),
      ],
    );
  }
}

class _ReportResult extends StatelessWidget {
  const _ReportResult({required this.data});
  final ReportData data;

  @override
  Widget build(BuildContext context) {
    final job = data.request.kind == ReportKind.job;
    final first = data.programs.firstOrNull;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SectionTitle(
                data.request.kind.title,
                detail: data.request.filterLabel,
                action: FilledButton.tonalIcon(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  label: const Text('Open PDF'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfReportScreen(report: data),
                    ),
                  ),
                ),
              ),
              if (job && first != null) ...[
                const SizedBox(height: 9),
                Text(
                  '${first['party']} · Job date ${dbDateLabel(first['job_date'])}',
                ),
                Text('Yarn · ${first['yarn']}'),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  ToneBadge('Ordered ${kg(data.ordered)} kg', millBlue),
                  ToneBadge(
                    '${job ? 'Produced' : 'Period output'} ${kg(job ? data.produced : data.period)} kg',
                    runningGreen,
                  ),
                  ToneBadge(
                    'Balance ${kg(data.balance)} kg',
                    data.balance > 0 ? pendingAmber : runningGreen,
                  ),
                  ToneBadge(
                    'Completion ${percent(data.produced, data.ordered)}',
                    millBlue,
                  ),
                  if (job && first != null)
                    ToneBadge(
                      data.programs.every((p) => p['completed'] == true)
                          ? 'Job completed'
                          : 'Job pending',
                      data.programs.every((p) => p['completed'] == true)
                          ? runningGreen
                          : pendingAmber,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (first == null) const Notice('No matching production records.'),
        if (data.byDia.isNotEmpty) ...[
          _ReportTable(
            title: 'DIA totals (kg)',
            columns: const ['DIA', 'Day', 'Night', 'Total'],
            records: [
              for (final dia in dias)
                if (data.byDia[dia] case final output?)
                  [
                    '$dia',
                    kg(output.$1),
                    kg(output.$2),
                    kg(output.$1 + output.$2),
                  ],
            ],
            numericFrom: 1,
          ),
          const SizedBox(height: 12),
        ],
        if (first != null) ...[
          _ReportTable(
            title: 'Program quantities (kg)',
            detail: job
                ? null
                : 'Ordered, produced and balance show lifetime totals. Period shows output within the selected filters.',
            columns: [
              'Job',
              'Party',
              'Yarn',
              'DIA',
              'Program',
              'Loop',
              'Design',
              'Remarks',
              'Ordered',
              if (!job) 'Period',
              'Produced',
              'Balance',
              'Completion',
              'Status',
            ],
            records: [
              for (final row in data.programs)
                [
                  for (final field in [
                    'job_number',
                    'party',
                    'yarn',
                    'dia',
                    'position',
                    'loop_length',
                    'specification',
                    'remarks',
                  ])
                    cellText(row[field]),
                  kg(grams(row['ordered_kg'])),
                  if (!job) kg(grams(row['period_kg'])),
                  kg(grams(row['produced_kg'])),
                  kg(grams(row['balance_kg'])),
                  percent(grams(row['produced_kg']), grams(row['ordered_kg'])),
                  jobStatus(row),
                ],
            ],
            numericFrom: 8,
          ),
          const SizedBox(height: 12),
        ],
        if (data.entries.isNotEmpty)
          _ReportTable(
            title: 'Production history',
            columns: const [
              'Date',
              'Shift',
              'Job',
              'Party',
              'DIA',
              'Program',
              'Design',
              'Output (kg)',
            ],
            records: [
              for (final row in data.entries)
                [
                  dbDateLabel(row['production_date']),
                  shiftName(row),
                  cellText(row['job_number']),
                  cellText(row['party']),
                  cellText(row['dia']),
                  cellText(row['program_position']),
                  cellText(row['specification']),
                  kg(grams(row['quantity_kg'])),
                ],
            ],
            numericFrom: 7,
          ),
      ],
    );
  }
}

class _ReportTable extends StatefulWidget {
  const _ReportTable({
    required this.title,
    required this.columns,
    required this.records,
    required this.numericFrom,
    this.detail,
  });
  final String title;
  final String? detail;
  final List<String> columns;
  final List<List<String>> records;
  final int numericFrom;
  @override
  State<_ReportTable> createState() => _ReportTableState();
}

class _ReportTableState extends State<_ReportTable> {
  final scroll = ScrollController();
  int page = 0;
  static const size = 20;

  @override
  void didUpdateWidget(covariant _ReportTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (page > 0 && page * size >= widget.records.length) page = 0;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleLarge),
          if (widget.detail != null) Text(widget.detail!),
          const SizedBox(height: 10),
          Scrollbar(
            controller: scroll,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.only(bottom: 10),
              child: DataTable(
                headingRowColor: const WidgetStatePropertyAll(millBlue),
                headingTextStyle: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
                dataRowMaxHeight: 80,
                columns: [
                  for (final (index, title) in widget.columns.indexed)
                    DataColumn(
                      label: Text(title),
                      numeric: index >= widget.numericFrom,
                    ),
                ],
                rows: [
                  for (final (index, row)
                      in widget.records.skip(page * size).take(size).indexed)
                    DataRow(
                      color: index.isEven
                          ? WidgetStatePropertyAll(
                              theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: .48),
                            )
                          : null,
                      cells: [
                        for (final cell in row)
                          DataCell(
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 220),
                              child: Tooltip(
                                message: cell,
                                child: Text(
                                  cell,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (widget.records.length > size)
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${page * size + 1}–${min((page + 1) * size, widget.records.length)} of ${widget.records.length}',
                ),
                IconButton(
                  onPressed: page == 0 ? null : () => setState(() => page--),
                  tooltip: 'Previous page',
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  onPressed: (page + 1) * size >= widget.records.length
                      ? null
                      : () => setState(() => page++),
                  tooltip: 'Next page',
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

enum _PdfAction { download, print, share }

class PdfReportScreen extends StatefulWidget {
  const PdfReportScreen({super.key, required this.report});
  final ReportData report;
  @override
  State<PdfReportScreen> createState() => _PdfReportScreenState();
}

class _PdfReportScreenState extends State<PdfReportScreen> {
  late Future<Uint8List> bytes = buildReportPdf(widget.report);
  bool busy = false;

  Future<void> act(_PdfAction action, Uint8List file) async {
    if (busy) return;
    final button = context.findRenderObject();
    final bounds = button is RenderBox && button.hasSize
        ? button.localToGlobal(Offset.zero) & button.size
        : null;
    setState(() => busy = true);
    final name = widget.report.request.filename;
    try {
      switch (action) {
        case _PdfAction.download:
          final bare = name.substring(0, name.length - 4);
          final path = kIsWeb
              ? await FileSaver.instance.saveFile(
                  name: bare,
                  bytes: file,
                  fileExtension: 'pdf',
                  mimeType: MimeType.pdf,
                )
              : await FileSaver.instance.saveAs(
                  name: bare,
                  bytes: file,
                  fileExtension: 'pdf',
                  mimeType: MimeType.pdf,
                );
          if (mounted && path != null && path.isNotEmpty) {
            notify(context, kIsWeb ? 'Download started.' : 'PDF saved.');
          }
        case _PdfAction.print:
          await Printing.layoutPdf(
            name: name,
            onLayout: (_) => file,
            format: reportFormat(widget.report.request.kind),
            dynamicLayout: false,
          );
        case _PdfAction.share:
          await SharePlus.instance.share(
            ShareParams(
              files: [XFile.fromData(file, mimeType: 'application/pdf')],
              fileNameOverrides: [name],
              sharePositionOrigin: bounds,
              subject: widget.report.request.kind.title,
            ),
          );
      }
    } catch (_) {
      if (mounted) {
        notify(
          context,
          'The PDF action could not finish. Try again or download the PDF.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PDF preview')),
    body: SafeArea(
      child: FutureBuilder<Uint8List>(
        future: bytes,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return PageBody(
              children: [
                Notice(
                  'Could not generate the PDF.',
                  action: FilledButton(
                    onPressed: () =>
                        setState(() => bytes = buildReportPdf(widget.report)),
                    child: const Text('Retry'),
                  ),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final file = snapshot.data!;
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  children: [
                    FilledButton.icon(
                      onPressed: busy
                          ? null
                          : () => act(_PdfAction.download, file),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Download'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => act(_PdfAction.print, file),
                      icon: const Icon(Icons.print_outlined),
                      label: const Text('Print'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => act(_PdfAction.share, file),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share'),
                    ),
                  ],
                ),
              ),
              if (busy) const LinearProgressIndicator(),
              Expanded(
                child: PdfPreview(
                  build: (_) async => file,
                  useActions: false,
                  canDebug: false,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  initialPageFormat: reportFormat(widget.report.request.kind),
                  maxPageWidth: 1040,
                  onError: (context, error) => const Center(
                    child: Text(
                      'Preview is unavailable here. Download the PDF to view it.',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
