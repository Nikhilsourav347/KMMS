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
  ref.watch(revisionsProvider(Dataset.jobs).select((update) => update.value));
  return ref.read(repositoryProvider).names('parties');
});

final _reportProvider = FutureProvider.autoDispose
    .family<ReportData, ReportRequest>((ref, filters) async {
      ref.watch(
        revisionsProvider(Dataset.production).select((update) => update.value),
      );
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

final _periodDiasProvider = FutureProvider.autoDispose
    .family<List<String>, (DateTime, DateTime)>((ref, period) {
      ref.watch(
        revisionsProvider(Dataset.production).select((update) => update.value),
      );
      return ref.watch(repositoryProvider).reportDias(period.$1, period.$2);
    });

enum _ReportScope {
  all('All Jobs and Parties'),
  job('Filter by Job Number'),
  party('Filter by Party Name');

  const _ReportScope(this.label);
  final String label;
}

const _noProduction = 'No production records found for the selected filters.';

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ReportKind kind = ReportKind.job;
  _ReportScope scope = _ReportScope.all;
  DateTime start = indiaToday();
  DateTime end = indiaToday();
  Shift shift = Shift.morning;
  String? jobId, partyId, dia;
  ReportRequest? request;

  void clearFilters() {
    scope = _ReportScope.all;
    jobId = null;
    partyId = null;
    dia = null;
  }

  void update(VoidCallback change) => setState(() {
    change();
    request = null;
  });

  void generate(ReportRequest filters) => setState(() => request = filters);

  @override
  Widget build(BuildContext context) {
    final range = kind == ReportKind.range;
    final jobReport = kind == ReportKind.job;
    final useJob = jobReport || (range && scope == _ReportScope.job);
    final useParty = range && scope == _ReportScope.party;
    final validDates = !range || !start.isAfter(end);
    final jobs = useJob
        ? ref.watch(jobsProvider)
        : const AsyncData(<RowData>[]);
    final parties = useParty
        ? ref.watch(_partiesProvider)
        : const AsyncData(<RowData>[]);
    final rangeKey = (start, end);
    final active = range
        ? ref.watch(activeDiasProvider)
        : const AsyncData(<String>[]);
    final historical = range && validDates
        ? ref.watch(_periodDiasProvider(rangeKey))
        : const AsyncData(<String>[]);
    final diaChoices = sortedDias([...?active.value, ...?historical.value]);
    final pickedJob = jobs.value?.where((j) => j['id'] == jobId).firstOrNull;
    final pickedParty = parties.value
        ?.where((p) => p['id'] == partyId)
        .firstOrNull;
    final filters = request;
    final provider = filters == null ? null : _reportProvider(filters);
    final snapshot = provider == null ? null : ref.watch(provider);

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
                      onSelected: (_) {
                        if (kind != option) {
                          update(() {
                            kind = option;
                            clearFilters();
                          });
                        }
                      },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              if (!jobReport)
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    DateField(
                      range ? 'From Date' : 'Production date',
                      start,
                      (date) => update(() => start = date),
                      last: range ? null : indiaToday(),
                    ),
                    if (range)
                      DateField(
                        'To Date',
                        end,
                        (date) => update(() => end = date),
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
              if (!validDates) ...[
                const SizedBox(height: 8),
                const Notice('From Date must be on or before To Date.'),
              ],
              if (range) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final value in _ReportScope.values)
                      ChoiceChip(
                        label: Text(value.label),
                        selected: scope == value,
                        onSelected: (_) {
                          if (scope != value) {
                            update(() {
                              scope = value;
                              jobId = null;
                              partyId = null;
                            });
                          }
                        },
                      ),
                  ],
                ),
              ],
              if (useJob) ...[
                const SizedBox(height: 10),
                loadView(
                  jobs,
                  (results) => SearchPicker(
                    label: 'Select job number',
                    value: jobId,
                    options: {
                      for (final j in results)
                        j['id'] as String: j['job_number'] as String,
                    },
                    onChanged: (value) => update(() => jobId = value),
                  ),
                  () => ref.invalidate(jobsProvider),
                ),
                if (pickedJob != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Party · ${pickedJob['party']}'),
                  ),
              ],
              if (useParty) ...[
                const SizedBox(height: 10),
                loadView(
                  parties,
                  (results) => SearchPicker(
                    label: 'Select party name',
                    value: partyId,
                    options: {
                      for (final p in results)
                        p['id'] as String: p['name'] as String,
                    },
                    onChanged: (value) => update(() => partyId = value),
                  ),
                  () => ref.invalidate(_partiesProvider),
                ),
              ],
              if (range) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: SearchPicker(
                      label: 'Filter by DIA',
                      value: dia ?? '',
                      options: {
                        '': 'All DIA',
                        if (dia != null && !diaChoices.contains(dia))
                          dia!: dia!,
                        for (final value in diaChoices) value: value,
                      },
                      allowClear: false,
                      onChanged: (value) =>
                          update(() => dia = value == '' ? null : value),
                    ),
                  ),
                ),
                if (historical.hasError || active.hasError)
                  Notice(
                    'Some DIA options could not be loaded.',
                    action: TextButton(
                      onPressed: () {
                        ref.invalidate(_periodDiasProvider(rangeKey));
                        ref.invalidate(registeredMachinesProvider);
                      },
                      child: const Text('Retry'),
                    ),
                  ),
              ],
              const SizedBox(height: 13),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (range)
                      TextButton(
                        onPressed: () => update(clearFilters),
                        child: const Text('Clear Filters'),
                      ),
                    FilledButton.icon(
                      icon: const Icon(Icons.summarize_outlined),
                      label: const Text('Generate Report'),
                      onPressed:
                          !validDates ||
                              (jobReport && pickedJob == null) ||
                              snapshot?.isLoading == true
                          ? null
                          : () => generate(
                              ReportRequest(
                                kind: kind,
                                start: jobReport ? null : start,
                                end: jobReport ? null : (range ? end : start),
                                shift: kind == ReportKind.shift ? shift : null,
                                jobId: pickedJob?['id'],
                                jobNumber: pickedJob?['job_number'],
                                partyId: pickedParty?['id'],
                                partyName:
                                    pickedParty?['name'] ?? pickedJob?['party'],
                                dia: range ? dia : null,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (snapshot != null)
          loadView(
            snapshot,
            (data) => _ReportResult(data: data),
            () => ref.invalidate(provider!),
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
    if (!data.hasData) return const Notice(_noProduction);
    final job = data.request.kind == ReportKind.job
        ? data.programs.firstOrNull
        : null;
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
                  label: const Text('Generate PDF'),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PdfReportScreen(report: data),
                    ),
                  ),
                ),
              ),
              if (job != null) ...[
                const SizedBox(height: 9),
                Text(
                  'Job date ${dbDateLabel(job['job_date'])} · Yarn ${cellText(job['yarn'])}',
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 7,
                runSpacing: 7,
                children: [
                  for (final (label, value) in data.productionSummary)
                    ToneBadge('$label · $value', millBlue),
                ],
              ),
            ],
          ),
        ),
        if (data.productionDays.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ReportTable(
            title: 'Date-wise production (kg)',
            columns: ['Date', ...data.productionColumns(dayProgramHeaders)],
            records: [
              for (final day in data.productionDays.entries) ...[
                for (final line in day.value)
                  [
                    dbDateLabel(day.key),
                    ...data.productionColumns(dayProgramCells(line)),
                  ],
                [
                  dbDateLabel(day.key),
                  ...data.subtotalCells(day.key, day.value),
                ],
              ],
            ],
            numericFrom: 7,
          ),
        ],
        if (data.programs.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ReportTable(
            title: 'Production Quantities (kg)',
            columns: const [
              'Job',
              'Party',
              'DIA',
              'Program',
              'Loop',
              'Specification',
              'Ordered',
              'Produced in report',
              'Remaining balance',
            ],
            records: [
              for (final row in data.programs)
                [
                  for (final field in [
                    'job_number',
                    'party',
                    'dia',
                    'position',
                    'loop_length',
                    'specification',
                  ])
                    cellText(row[field]),
                  kg(grams(row['ordered_kg'])),
                  kg(grams(row['period_kg'])),
                  kg(grams(row['balance_kg'])),
                ],
            ],
            numericFrom: 6,
          ),
        ],
        if (data.filteredEntries.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ReportTable(
            title: 'Production History',
            columns: const [
              'Date',
              'Shift',
              'Job',
              'Party',
              'DIA',
              'Program',
              'Loop',
              'Specification',
              'Production (kg)',
            ],
            records: [
              for (final row in data.filteredEntries)
                [
                  dbDateLabel(row['production_date']),
                  Shift.values.byName(row['shift']).label,
                  for (final field in [
                    'job_number',
                    'party',
                    'dia',
                    'program_position',
                    'loop_length',
                    'specification',
                  ])
                    cellText(row[field]),
                  kg(grams(row['quantity_kg'])),
                ],
            ],
            numericFrom: 8,
          ),
        ],
        const SizedBox(height: 12),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${data.totalLabel} · ${kg(data.period)} kg',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Text(data.balanceLabel),
            ],
          ),
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
  });
  final String title;
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
            format: reportFormat,
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
                  initialPageFormat: reportFormat,
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
