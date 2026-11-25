import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});
  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

enum _JobFilter { all, pending, completed }

class _JobsScreenState extends ConsumerState<JobsScreen> {
  var filter = _JobFilter.all;
  String query = '';

  Future<void> edit([RowData? job]) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _JobEditor(job: job),
    );
    if (saved == true && mounted) {
      ref.invalidate(jobsProvider);
      notify(context, job == null ? 'Job created.' : 'Job updated.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(jobsProvider);
    return PageBody(
      children: [
        SectionTitle(
          'Job Entry',
          detail: 'Manage orders and their individual knitting programs.',
          action: FilledButton.icon(
            onPressed: edit,
            icon: const Icon(Icons.add),
            label: const Text('New job'),
          ),
        ),
        Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                onChanged: (value) =>
                    setState(() => query = value.trim().toLowerCase()),
                decoration: const InputDecoration(
                  labelText: 'Search by job number or party',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final (option, label) in [
                    (_JobFilter.all, 'All jobs'),
                    (_JobFilter.pending, 'Pending'),
                    (_JobFilter.completed, 'Completed'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: filter == option,
                      onSelected: (_) => setState(() => filter = option),
                    ),
                ],
              ),
            ],
          ),
        ),
        loadView(data, (jobs) {
          final visible = jobs.where(
            (job) =>
                (filter == _JobFilter.all ||
                    (job['completed'] == true) ==
                        (filter == _JobFilter.completed)) &&
                ('${job['job_number']}'.toLowerCase().contains(query) ||
                    '${job['party']}'.toLowerCase().contains(query)),
          );
          if (visible.isEmpty) {
            return const Notice(
              'No jobs match these filters.',
              icon: Icons.assignment_outlined,
            );
          }
          return Panel(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Column(
              children: [
                for (final job in visible)
                  ListTile(
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (_) => _JobDetails(job: job),
                    ),
                    title: Text(
                      '${job['job_number']} · ${job['party']}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    subtitle: Text(
                      '${dbDateLabel(job['job_date'])} · ${kg(grams(job['produced_kg']))} / ${kg(grams(job['ordered_kg']))} kg',
                    ),
                    leading: const Icon(Icons.assignment_outlined),
                    trailing: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (MediaQuery.sizeOf(context).width >= 570)
                          ToneBadge(
                            job['completed'] == true ? 'Completed' : 'Pending',
                            job['completed'] == true
                                ? runningGreen
                                : pendingAmber,
                          ),
                        IconButton(
                          tooltip: 'Edit job ${job['job_number']}',
                          onPressed: () => edit(job),
                          icon: const Icon(Icons.edit_outlined),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        }, () => ref.invalidate(jobsProvider)),
      ],
    );
  }
}

class _JobDetails extends ConsumerStatefulWidget {
  const _JobDetails({required this.job});
  final RowData job;
  @override
  ConsumerState<_JobDetails> createState() => _JobDetailsState();
}

class _JobDetailsState extends ConsumerState<_JobDetails> {
  late Future<List<RowData>> details = ref
      .read(repositoryProvider)
      .programs(widget.job['id']);

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Job ${widget.job['job_number']}'),
    content: SizedBox(
      width: 555,
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${widget.job['party']} · ${dbDateLabel(widget.job['job_date'])}',
            ),
            Text('Yarn · ${widget.job['yarn']}'),
            Text(
              'Status · ${widget.job['completed'] == true ? 'Completed' : 'Pending'}',
            ),
            const SizedBox(height: 12),
            FutureBuilder<List<RowData>>(
              future: details,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Notice(
                    friendlyError(snapshot.error!),
                    action: TextButton(
                      onPressed: () => setState(
                        () => details = ref
                            .read(repositoryProvider)
                            .programs(widget.job['id']),
                      ),
                      child: const Text('Retry'),
                    ),
                  );
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                return Column(
                  children: [
                    for (final p in snapshot.data!)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Program ${p['position']} · DIA ${p['dia']}',
                        ),
                        subtitle: Text(
                          'Loop ${p['loop_length']} · ${p['specification']}\n'
                          'Remarks · ${cellText(p['remarks'])}\n'
                          'Ordered ${kg(grams(p['ordered_kg']))} kg · Produced ${kg(grams(p['produced_kg']))} kg · Balance ${kg(grams(p['balance_kg']))} kg',
                        ),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Close'),
      ),
    ],
  );
}

class _ProgramDraft {
  _ProgramDraft([RowData? row])
    : id = row?['id'],
      dia = row?['dia'],
      loop = TextEditingController(text: row?['loop_length']?.toString()),
      order = TextEditingController(text: row?['ordered_kg']?.toString()),
      spec = TextEditingController(text: row?['specification']),
      remarks = TextEditingController(text: row?['remarks']),
      hasHistory = row?['has_history'] == true;

  final String? id;
  int? dia;
  final bool hasHistory;
  final TextEditingController loop, order, spec, remarks;

  bool get empty =>
      id == null &&
      dia == null &&
      [loop, order, spec, remarks].every((field) => field.text.trim().isEmpty);
  bool get complete =>
      dia != null &&
      (parseGrams(loop.text) ?? 0) > 0 &&
      (parseGrams(order.text) ?? 0) > 0 &&
      spec.text.trim().isNotEmpty;

  RowData get data => {
    'id': id,
    'dia': dia,
    'loop_length': loop.text.trim(),
    'ordered_kg': order.text.trim(),
    'specification': spec.text.trim(),
    'remarks': remarks.text.trim(),
  };

  void dispose() {
    for (final field in [loop, order, spec, remarks]) {
      field.dispose();
    }
  }
}

class _JobEditor extends ConsumerStatefulWidget {
  const _JobEditor({this.job});
  final RowData? job;

  @override
  ConsumerState<_JobEditor> createState() => _JobEditorState();
}

class _JobEditorState extends ConsumerState<_JobEditor> {
  final form = GlobalKey<FormState>();
  late final number = TextEditingController(text: widget.job?['job_number']);
  late final party = TextEditingController(text: widget.job?['party']);
  late final yarn = TextEditingController(text: widget.job?['yarn']);
  late DateTime date = widget.job == null
      ? indiaToday()
      : DateTime.parse(widget.job!['job_date']);
  final programs = <_ProgramDraft>[];
  // Disposed with the editor after the removed cards unmount.
  final removed = <_ProgramDraft>[];
  List<String> parties = [];
  bool loading = true;
  bool busy = false;
  String? error;
  String? loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final repository = ref.read(repositoryProvider);
      final data = await Future.wait([
        repository.names('parties'),
        if (widget.job != null) repository.programs(widget.job!['id']),
      ]);
      if (!mounted) return;
      setState(() {
        parties = data[0].map((p) => p['name'] as String).toList();
        loadError = null;
        loading = false;
        if (widget.job == null) {
          programs.addAll(List.generate(5, (_) => _ProgramDraft()));
        } else {
          programs.addAll(data[1].map(_ProgramDraft.new));
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = friendlyError(e);
        });
      }
    }
  }

  @override
  void dispose() {
    number.dispose();
    party.dispose();
    yarn.dispose();
    for (final p in [...programs, ...removed]) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    final lines = programs.where((p) => !p.empty).toList();
    if (!form.currentState!.validate() || party.text.trim().isEmpty) {
      setState(
        () => error = 'Enter the job number, party name and yarn details.',
      );
      return;
    }
    if (lines.isEmpty || lines.any((p) => !p.complete)) {
      setState(
        () => error =
            'Add at least one complete program. Enter a DIA, positive loop length, ordered quantity and design. Use up to three decimal places.',
      );
      return;
    }
    final total = lines.fold(0, (n, p) => n + grams(p.order.text));
    final confirmed = await confirm(
      context,
      widget.job == null ? 'Create this job?' : 'Save job changes?',
      '${lines.length} program(s) · ${kg(total)} kg ordered.',
      action: 'Save',
    );
    if (!mounted || !confirmed) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(repositoryProvider)
          .saveJob(
            existing: widget.job,
            date: date,
            number: number.text,
            party: party.text,
            yarn: yarn.text,
            programs: lines.map((p) => p.data).toList(),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: Text(
        widget.job == null
            ? 'New job'
            : 'Edit job ${widget.job!['job_number']}',
      ),
      content: SizedBox(
        width: 690,
        child: loading
            ? const Center(heightFactor: 3, child: CircularProgressIndicator())
            : loadError != null
            ? Notice(
                loadError!,
                action: OutlinedButton(
                  onPressed: () {
                    setState(() => loading = true);
                    _load();
                  },
                  child: const Text('Retry'),
                ),
              )
            : SingleChildScrollView(
                child: Form(
                  key: form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: DateField(
                          'Job date',
                          date,
                          busy ? null : (value) => setState(() => date = value),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: number,
                        enabled: !busy,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Job number',
                          counterText: '',
                        ),
                        validator: (t) => (t ?? '').trim().isEmpty
                            ? 'Job number is required.'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      SearchableNameField(
                        label: 'Party name',
                        controller: party,
                        names: parties,
                        enabled: !busy,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: yarn,
                        enabled: !busy,
                        maxLength: 240,
                        decoration: const InputDecoration(
                          labelText: 'Yarn details',
                          counterText: '',
                        ),
                        validator: (t) => (t ?? '').trim().isEmpty
                            ? 'Yarn details are required.'
                            : null,
                      ),
                      const SizedBox(height: 18),
                      for (final (index, program) in programs.indexed)
                        Padding(
                          key: ObjectKey(program),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _program(index, program),
                        ),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          OutlinedButton.icon(
                            onPressed: busy
                                ? null
                                : () => setState(
                                    () => programs.add(_ProgramDraft()),
                                  ),
                            icon: const Icon(Icons.add),
                            label: const Text('Add program'),
                          ),
                          _OrderedQuantity(programs: programs),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
      actions: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: busy || loading || loadError != null ? null : save,
          child: Text(busy ? 'Saving…' : 'Save job'),
        ),
      ],
    ),
  );

  Widget _program(int index, _ProgramDraft p) {
    final theme = Theme.of(context);
    final hasOutput = p.hasHistory;
    return Panel(
      padding: const EdgeInsets.all(13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Program ${index + 1}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Remove program ${index + 1}',
                onPressed: busy || hasOutput
                    ? null
                    : () => setState(() {
                        programs.remove(p);
                        removed.add(p);
                      }),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          LayoutBuilder(
            builder: (context, bounds) {
              final columns = bounds.maxWidth >= 530
                  ? 3
                  : bounds.maxWidth >= 305
                  ? 2
                  : 1;
              final width = (bounds.maxWidth - (columns - 1) * 9) / columns;
              return Wrap(
                spacing: 9,
                runSpacing: 9,
                children: [
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<int>(
                      initialValue: p.dia,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'DIA'),
                      items: [
                        for (final value in dias)
                          DropdownMenuItem(value: value, child: Text('$value')),
                      ],
                      onChanged: busy || hasOutput
                          ? null
                          : (value) => setState(() => p.dia = value),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: TextField(
                      controller: p.loop,
                      enabled: !busy && !hasOutput,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Loop length',
                      ),
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: TextField(
                      controller: p.order,
                      enabled: !busy,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Quantity (kg)',
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 9),
          DropdownButtonFormField<String>(
            isExpanded: true,
            initialValue: p.spec.text.isEmpty ? null : p.spec.text,
            decoration: const InputDecoration(labelText: 'Design'),
            items: [
              for (final design in {
                ...designs,
                if (p.spec.text.isNotEmpty) p.spec.text,
              })
                DropdownMenuItem(
                  value: design,
                  child: Text(design, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: busy || hasOutput
                ? null
                : (value) => setState(() => p.spec.text = value ?? ''),
          ),
          const SizedBox(height: 9),
          TextField(
            controller: p.remarks,
            enabled: !busy,
            maxLength: 360,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Program remarks',
              counterText: '',
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderedQuantity extends StatelessWidget {
  const _OrderedQuantity({required this.programs});
  final List<_ProgramDraft> programs;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge(programs.map((p) => p.order)),
    builder: (context, _) {
      final sum = programs.fold(
        0,
        (total, program) => total + grams(program.order.text),
      );
      return Text(
        'Total ordered · ${kg(sum)} kg',
        style: Theme.of(context).textTheme.titleSmall,
      );
    },
  );
}
