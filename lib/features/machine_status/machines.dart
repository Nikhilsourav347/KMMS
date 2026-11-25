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
                Panel(
                  padding: const EdgeInsets.all(12),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1),
                      1: FlexColumnWidth(.85),
                      2: FlexColumnWidth(.95),
                    },
                    defaultVerticalAlignment: TableCellVerticalAlignment.middle,
                    border: TableBorder(
                      horizontalInside: BorderSide(
                        color: Theme.of(context).dividerColor,
                      ),
                    ),
                    children: [
                      const TableRow(
                        children: [
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Machine'),
                          ),
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Date'),
                          ),
                          Padding(
                            padding: EdgeInsets.all(6),
                            child: Text('Status'),
                          ),
                        ],
                      ),
                      for (final machine in machines)
                        TableRow(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 12,
                              ),
                              child: Text(machine['name']),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                              ),
                              child: Text(prettyDate(date)),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Semantics(
                                label: '${machine['name']} running',
                                child: CupertinoSwitch(
                                  value:
                                      pending[machine['id']] ??
                                      machine['running'] == true,
                                  activeTrackColor: runningGreen,
                                  inactiveTrackColor: unconfirmedGrey,
                                  onChanged:
                                      manager &&
                                          !pending.containsKey(machine['id'])
                                      ? (value) => update(machine, value)
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
            ],
          );
        }, () => ref.invalidate(_dayProvider(date))),
      ],
    );
  }
}
