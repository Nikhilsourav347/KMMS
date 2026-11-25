import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class ProductionScreen extends StatelessWidget {
  const ProductionScreen({super.key});

  @override
  Widget build(BuildContext context) => const DefaultTabController(
    length: 2,
    child: Column(
      children: [
        TabBar(
          tabs: [
            Tab(text: 'Record production'),
            Tab(text: 'Entry history'),
          ],
        ),
        Expanded(
          child: TabBarView(
            physics: NeverScrollableScrollPhysics(),
            children: [_ProductionForm(), _ProductionHistory()],
          ),
        ),
      ],
    ),
  );
}

class _ProductionForm extends ConsumerStatefulWidget {
  const _ProductionForm();
  @override
  ConsumerState<_ProductionForm> createState() => _ProductionFormState();
}

class _ProductionFormState extends ConsumerState<_ProductionForm>
    with AutomaticKeepAliveClientMixin {
  DateTime? date;
  Shift? shift;
  String? jobId;
  Future<RowData>? details;
  bool busy = false;
  @override
  bool get wantKeepAlive => true;

  void _read() {
    _sheetKey = GlobalKey<_SheetState>();
    final id = jobId;
    details = id == null || date == null || shift == null
        ? null
        : ref.read(repositoryProvider).productionSheet(id, date!, shift!);
  }

  Future<bool> save(List<RowData> changes) async {
    final approved = await confirm(
      context,
      'Save shift production?',
      '${changes.length} program(s) · ${prettyDate(date!)} · ${shift!.label} shift',
      action: 'Save',
    );
    if (!mounted || !approved) return false;
    setState(() => busy = true);
    try {
      await ref
          .read(repositoryProvider)
          .saveProduction(jobId!, date!, shift!, changes);
      if (mounted) {
        ref.invalidate(jobsProvider);
        setState(_read);
        notify(context, 'Production saved.');
      }
      return true;
    } catch (e) {
      if (mounted) notify(context, friendlyError(e));
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _changeFilters(VoidCallback change) async {
    if (busy) return;
    final sheet = _sheetKey.currentState;
    if (sheet?.changed == true) {
      final ok = await confirm(
        context,
        'Discard unsaved quantities?',
        'Changing the production selection will clear this draft.',
        action: 'Discard',
      );
      if (!mounted || !ok) return;
    }
    setState(() {
      change();
      _read();
    });
  }

  var _sheetKey = GlobalKey<_SheetState>();
  @override
  Widget build(BuildContext context) {
    super.build(context);
    final jobs = ref.watch(jobsProvider);
    return PageBody(
      children: [
        const SectionTitle(
          'Production Entry',
          detail:
              'The night shift is recorded against the date it started in IST.',
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  DateField(
                    'Production date',
                    date,
                    busy
                        ? null
                        : (value) => _changeFilters(() {
                            date = value;
                            shift = null;
                            jobId = null;
                          }),
                    last: indiaToday(),
                  ),
                  SegmentedButton<Shift>(
                    emptySelectionAllowed: shift == null,
                    segments: const [
                      ButtonSegment(value: Shift.morning, label: Text('Day')),
                      ButtonSegment(value: Shift.night, label: Text('Night')),
                    ],
                    selected: shift == null ? {} : {shift!},
                    onSelectionChanged: date == null || busy
                        ? null
                        : (value) => _changeFilters(() {
                            shift = value.firstOrNull;
                          }),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              loadView(
                jobs,
                (list) => SearchPicker(
                  label: 'Select job number',
                  value: jobId,
                  enabled: date != null && shift != null && !busy,
                  options: {
                    for (final j in list)
                      j['id'] as String: '${j['job_number']} · ${j['party']}',
                  },
                  onChanged: (value) => _changeFilters(() => jobId = value),
                ),
                () => ref.invalidate(jobsProvider),
              ),
            ],
          ),
        ),
        if (details == null)
          const Notice(
            'Select the production date, shift and job to load its programs.',
            icon: Icons.inventory_2_outlined,
          )
        else
          FutureBuilder<RowData>(
            future: details,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Notice(
                  friendlyError(snapshot.error!),
                  action: TextButton(
                    onPressed: () => setState(_read),
                    child: const Text('Retry'),
                  ),
                );
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              final result = snapshot.data!;
              final job = related(result, 'job');
              if (job == null) {
                return const Notice(
                  'This job is unavailable. Select another job.',
                );
              }
              return _Sheet(
                key: _sheetKey,
                job: job,
                programs: rows(result['programs']),
                shift: shift!,
                busy: busy,
                onSave: save,
                refresh: () => _changeFilters(() {}),
              );
            },
          ),
      ],
    );
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({
    super.key,
    required this.job,
    required this.programs,
    required this.shift,
    required this.busy,
    required this.onSave,
    required this.refresh,
  });
  final RowData job;
  final List<RowData> programs;
  final Shift shift;
  final bool busy;
  final Future<bool> Function(List<RowData>) onSave;
  final VoidCallback refresh;
  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  bool get changed => widget.programs.any((p) {
    final original = p['shift_kg'];
    final entry = fields[p['id']]?.text.trim() ?? '';
    return original == null
        ? entry.isNotEmpty
        : parseGrams(entry) != grams(original);
  });

  @override
  void initState() {
    super.initState();
    for (final p in widget.programs) {
      fields[p['id']] = TextEditingController(
        text: p['shift_kg'] == null ? '' : kg(grams(p['shift_kg'])),
      );
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> apply() async {
    if (!form.currentState!.validate()) return;
    final lines = <RowData>[];
    for (final p in widget.programs) {
      final text = fields[p['id']]!.text.trim();
      final parsed = parseGrams(text);
      if ((text.isNotEmpty && (parsed == null || parsed < 0)) ||
          (text.isEmpty && p['shift_kg'] != null)) {
        notify(context, 'Check the entered quantities for DIA ${p['dia']}.');
        return;
      }
      if (parsed == null) continue;
      if (p['shift_kg'] != null && parsed == grams(p['shift_kg'])) continue;
      lines.add({
        'program_id': p['id'],
        'quantity_kg': kg(parsed),
        'version': p['shift_version'],
      });
    }
    if (lines.isEmpty) {
      notify(context, 'Enter at least one new or corrected quantity.');
      return;
    }
    await widget.onSave(lines);
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Job ${widget.job['job_number']} · ${widget.job['party']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text('Yarn · ${widget.job['yarn']}'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reload job and production',
                onPressed: widget.busy ? null : widget.refresh,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        for (final dia
            in (widget.programs.map((p) => p['dia'] as int).toSet().toList()
              ..sort()))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'DIA $dia',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  for (final p in widget.programs.where(
                    (p) => p['dia'] == dia,
                  )) ...[
                    const Divider(height: 26),
                    _ProductionLine(
                      program: p,
                      field: fields[p['id']]!,
                      shift: widget.shift,
                      enabled: !widget.busy,
                    ),
                  ],
                ],
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            onPressed: widget.busy || fields.isEmpty ? null : apply,
            icon: const Icon(Icons.save_outlined),
            label: Text(widget.busy ? 'Saving…' : 'Confirm production'),
          ),
        ),
      ],
    ),
  );
}

class _ProductionLine extends StatelessWidget {
  const _ProductionLine({
    required this.program,
    required this.field,
    required this.shift,
    required this.enabled,
  });
  final RowData program;
  final TextEditingController field;
  final Shift shift;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final ordered = grams(program['ordered_kg']);
    final previous = grams(program['previous_kg']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Program ${program['position']} · ${program['specification']}',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        Text(
          'Loop length ${program['loop_length']} · Remarks ${cellText(program['remarks'])}',
        ),
        const SizedBox(height: 10),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: field,
          builder: (context, value, _) {
            final total = previous + (parseGrams(value.text) ?? 0);
            final balance = ordered - total;
            return Table(
              children: [
                TableRow(
                  children: [
                    for (final title in [
                      'DIA',
                      'Ordered',
                      'Production',
                      'Balance',
                    ])
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ),
                  ],
                ),
                TableRow(
                  children: [
                    Text('${program['dia']}'),
                    Text(kg(ordered)),
                    Text(kg(total)),
                    Text(
                      kg(balance),
                      style: TextStyle(color: balance < 0 ? stoppedRed : null),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 9),
        SizedBox(
          width: 290,
          child: TextFormField(
            controller: field,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: '${shift.label} Shift Production (KG)',
              helperText: program['shift_version'] == null
                  ? null
                  : 'Saved entry · edit to correct',
            ),
            validator: (value) {
              if ((value ?? '').trim().isEmpty) {
                return program['shift_version'] == null
                    ? null
                    : 'Enter 0 to correct a saved entry to zero.';
              }
              final number = parseGrams(value);
              return number == null || number < 0
                  ? 'Use a non-negative number with up to 3 decimals.'
                  : null;
            },
          ),
        ),
      ],
    );
  }
}

enum _HistoryGroup {
  date('Date'),
  party('Party'),
  job('Job number');

  const _HistoryGroup(this.label);
  final String label;
}

final _entriesProvider = FutureProvider.autoDispose
    .family<RowData, (DateTime, DateTime)>((ref, dates) {
      ref.watch(revisionsProvider(Dataset.production));
      return ref
          .read(repositoryProvider)
          .report(start: dates.$1, end: dates.$2);
    });

class _ProductionHistory extends ConsumerStatefulWidget {
  const _ProductionHistory();
  @override
  ConsumerState<_ProductionHistory> createState() => _ProductionHistoryState();
}

class _ProductionHistoryState extends ConsumerState<_ProductionHistory> {
  DateTime end = indiaToday();
  late DateTime start = DateTime(end.year, end.month, end.day - 6);
  _HistoryGroup group = _HistoryGroup.date;

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(_entriesProvider((start, end)));
    return PageBody(
      children: [
        const SectionTitle('Production history'),
        Panel(
          child: Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              DateField(
                'From',
                start,
                (value) => setState(() {
                  start = value;
                  if (end.isBefore(start)) end = start;
                }),
                last: indiaToday(),
              ),
              DateField(
                'To',
                end,
                (value) => setState(() => end = value),
                first: start,
                last: indiaToday(),
              ),
              DropdownButton<_HistoryGroup>(
                value: group,
                onChanged: (value) => setState(() => group = value!),
                items: [
                  for (final option in _HistoryGroup.values)
                    DropdownMenuItem(
                      value: option,
                      child: Text('Group by ${option.label}'),
                    ),
                ],
              ),
            ],
          ),
        ),
        loadView(result, (payload) {
          final entries = rows(payload['entries']);
          if (entries.isEmpty) {
            return const Notice('No production entries in this period.');
          }
          final grouped = <String, List<RowData>>{};
          final field = switch (group) {
            _HistoryGroup.date => 'production_date',
            _HistoryGroup.party => 'party',
            _HistoryGroup.job => 'job_number',
          };
          for (final entry in entries) {
            final title = group == _HistoryGroup.date
                ? dbDateLabel(entry[field])
                : entry[field] as String;
            (grouped[title] ??= []).add(entry);
          }
          return Panel(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                for (final groupEntries in grouped.entries)
                  ExpansionTile(
                    title: Text(groupEntries.key),
                    subtitle: Text(
                      '${kg(groupEntries.value.fold(0, (total, row) => total + grams(row['quantity_kg'])))} kg',
                    ),
                    children: [
                      for (final e in groupEntries.value)
                        ListTile(
                          title: Text(
                            '${e['job_number']} · ${e['party']} · DIA ${e['dia']}',
                          ),
                          subtitle: Text(
                            '${dbDateLabel(e['production_date'])} · ${Shift.values.byName(e['shift']).label} · ${e['specification']}',
                          ),
                          trailing: Text('${kg(grams(e['quantity_kg']))} kg'),
                        ),
                    ],
                  ),
              ],
            ),
          );
        }, () => ref.invalidate(_entriesProvider((start, end)))),
      ],
    );
  }
}
