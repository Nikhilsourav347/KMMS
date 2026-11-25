import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/domain.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final _dayProvider = FutureProvider.autoDispose.family<List<RowData>, DateTime>(
  (ref, date) {
    ref.watch(revisionsProvider(Dataset.machines));
    return ref.watch(repositoryProvider).machineDay(date);
  },
);

class MachineScreen extends ConsumerStatefulWidget {
  const MachineScreen({super.key, required this.role});
  final StaffRole role;
  @override
  ConsumerState<MachineScreen> createState() => _DayState();
}

class _DayState extends ConsumerState<MachineScreen> {
  DateTime date = indiaToday();
  final pending = <int, bool>{};

  Future<void> update(RowData machine, bool value) async {
    final selected = date;
    final id = machine['id'] as int;

    setState(() => pending[id] = value);
    try {
      await ref.read(repositoryProvider).setRunning(id, selected, value);
      if (mounted) ref.invalidate(_dayProvider(selected));
    } catch (error) {
      if (mounted) notify(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => pending.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(_dayProvider(date));
    final manager = widget.role == StaffRole.manager;
    return PageBody(
      children: [
        const SectionTitle('Machine Running Status'),
        Align(
          alignment: Alignment.centerLeft,
          child: DateField(
            'Status date',
            date,
            pending.isEmpty ? (value) => setState(() => date = value) : null,
          ),
        ),
        loadView(rows, (machines) {
          final running = machines
              .where((m) => pending[m['id']] ?? m['running'] == true)
              .length;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ToneBadge('Total Machines · ${machines.length}', millBlue),
                  ToneBadge('Running Machines · $running', runningGreen),
                  ToneBadge(
                    'Stopped Machines · ${machines.length - running}',
                    unconfirmedGrey,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (machines.isEmpty)
                const Notice('No registered machines.')
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    const gap = 10.0;
                    final width = (constraints.maxWidth - gap) / 2;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final machine in machines)
                          SizedBox(
                            key: ValueKey('machine-card-${machine['id']}'),
                            width: width,
                            child: _MachineCard(
                              machine: machine,
                              running:
                                  pending[machine['id']] ??
                                  machine['running'] == true,
                              onChanged:
                                  manager && !pending.containsKey(machine['id'])
                                  ? (value) => update(machine, value)
                                  : null,
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          );
        }, () => ref.invalidate(_dayProvider(date))),
      ],
    );
  }
}

class _MachineCard extends StatelessWidget {
  const _MachineCard({
    required this.machine,
    required this.running,
    required this.onChanged,
  });
  final RowData machine;
  final bool running;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            machine['name'] as String,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          Text(machineDiaLabel(machine), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Row(
            children: [
              Flexible(
                child: Text(
                  running ? 'ON' : 'OFF',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: running ? runningGreen : unconfirmedGrey,
                  ),
                ),
              ),
              const Spacer(),
              Semantics(
                label: '${machine['name']} running',
                child: CupertinoSwitch(
                  value: running,
                  activeTrackColor: runningGreen,
                  inactiveTrackColor: unconfirmedGrey,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
