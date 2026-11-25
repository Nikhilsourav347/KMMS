import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/domain.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final _dayProvider = FutureProvider.autoDispose.family<List<RowData>, DateTime>(
  (ref, date) {
    ref.watch(revisionsProvider(Dataset.schedule));
    return ref.watch(repositoryProvider).scheduleDay(date);
  },
);

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key, required this.role});
  final StaffRole role;
  @override
  ConsumerState<ScheduleScreen> createState() => _DayState();
}

class _DayState extends ConsumerState<ScheduleScreen> {
  DateTime date = indiaToday();
  final pending = <int, bool>{};

  Future<void> update(RowData machine, bool value) async {
    final selected = date;
    final id = machine['id'] as int;
    final approved = await confirm(
      context,
      'Schedule ${machine['name']}?',
      'Reserve this machine for ${prettyDate(selected)}.',
      action: 'Schedule',
    );
    if (!mounted || !approved) return;
    setState(() => pending[id] = value);
    try {
      await ref.read(repositoryProvider).scheduleMachine(id, selected);
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
        const SectionTitle('Machine Schedule'),
        Align(
          alignment: Alignment.centerLeft,
          child: DateField(
            'Schedule date',
            date,
            pending.isEmpty ? (value) => setState(() => date = value) : null,
          ),
        ),
        loadView(rows, (machines) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                              child:
                                  machine['scheduled'] == true ||
                                      pending.containsKey(machine['id'])
                                  ? const ToneBadge('Scheduled', millBlue)
                                  : manager
                                  ? TextButton(
                                      onPressed: () => update(machine, true),
                                      child: const Text('Available'),
                                    )
                                  : const ToneBadge('Available', runningGreen),
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
