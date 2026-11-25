import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/domain.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final _monthProvider = FutureProvider.autoDispose
    .family<List<MachineScheduleRow>, DateTime>((ref, month) {
      ref.watch(revisionsProvider(Dataset.schedule));
      return ref
          .watch(repositoryProvider)
          .machineSchedule(month, DateTime(month.year, month.month + 1, 0));
    });

const _dayWidth = 112.0;
const _rowHeight = 62.0;

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key, required this.role});
  final StaffRole role;

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleState();
}

class _ScheduleState extends ConsumerState<ScheduleScreen> {
  late DateTime month = _monthOf(indiaToday());
  final _datesController = ScrollController();
  final _pending = <(int, String)>{};
  int? _jumpDay;

  DateTime _monthOf(DateTime day) => DateTime(day.year, day.month);

  void _selectMonth(DateTime next, {int day = 1}) {
    setState(() {
      month = next;
      _jumpDay = day;
    });
  }

  void _scrollToDayAfterLayout() {
    final day = _jumpDay;
    if (day == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_datesController.hasClients || _jumpDay != day) return;
      _jumpDay = null;
      final position = _datesController.position;
      _datesController.jumpTo(
        ((day - 1) * _dayWidth).clamp(0.0, position.maxScrollExtent),
      );
    });
  }

  Future<void> _changeBooking(
    RowData machine,
    DateTime date,
    bool booked,
  ) async {
    final id = machine['id'] as int;
    final cell = (id, isoDate(date));
    if (!_pending.add(cell)) return;
    setState(() {});
    try {
      final approved = await confirm(
        context,
        booked ? 'Make this machine available?' : 'Schedule this machine?',
        '${machine['name']} · ${prettyDate(date)}',
        action: booked ? 'Make available' : 'Schedule',
      );
      if (!mounted || !approved) return;
      final repository = ref.read(repositoryProvider);
      if (booked) {
        await repository.cancelMachineSchedule(id, date);
      } else {
        await repository.scheduleMachine(id, date);
      }
      if (mounted) ref.invalidate(_monthProvider(_monthOf(date)));
    } catch (error) {
      if (mounted) notify(context, friendlyError(error));
    } finally {
      if (mounted) setState(() => _pending.remove(cell));
    }
  }

  @override
  void dispose() {
    _datesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(_monthProvider(month));
    return PageBody(
      children: [
        const SectionTitle('Machine Schedule'),
        Panel(
          padding: const EdgeInsets.all(10),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous month',
                onPressed: () =>
                    _selectMonth(DateTime(month.year, month.month - 1)),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                DateFormat.yMMMM().format(month),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: () =>
                    _selectMonth(DateTime(month.year, month.month + 1)),
                icon: const Icon(Icons.chevron_right),
              ),
              TextButton.icon(
                onPressed: () {
                  final today = indiaToday();
                  _selectMonth(_monthOf(today), day: today.day);
                },
                icon: const Icon(Icons.today_outlined),
                label: const Text('Today'),
              ),
            ],
          ),
        ),
        loadView(result, (rows) {
          if (rows.isEmpty) return const Notice('No registered machines.');
          _scrollToDayAfterLayout();
          return _calendar(rows);
        }, () => ref.invalidate(_monthProvider(month))),
      ],
    );
  }

  Widget _calendar(List<MachineScheduleRow> rows) {
    final theme = Theme.of(context);
    final today = isoDate(indiaToday());
    final days = [
      for (
        var day = 1;
        day <= DateTime(month.year, month.month + 1, 0).day;
        day++
      )
        DateTime(month.year, month.month, day),
    ];
    final manager = widget.role == StaffRole.manager;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final machineWidth = constraints.maxWidth < 465 ? 108.0 : 148.0;
          Widget header(String title, double width, {bool current = false}) =>
              _CalendarCell(
                width: width,
                color: current ? const Color(0xFF254E84) : millBlue,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  header('Machine / DIA', machineWidth),
                  for (final row in rows)
                    _CalendarCell(
                      width: machineWidth,
                      color: theme.colorScheme.surfaceContainerLow,
                      child: Tooltip(
                        message:
                            '${row.machine['name']} · ${machineDiaLabel(row.machine)}',
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                row.machine['name'] as String,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.labelLarge,
                              ),
                              Text(
                                machineDiaLabel(row.machine),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              Expanded(
                child: Scrollbar(
                  controller: _datesController,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _datesController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            for (final date in days)
                              header(
                                DateFormat('EEE dd').format(date),
                                _dayWidth,
                                current: isoDate(date) == today,
                              ),
                          ],
                        ),
                        for (final row in rows)
                          Row(
                            children: [
                              for (final date in days)
                                _bookingCell(row, date, manager),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _bookingCell(MachineScheduleRow row, DateTime date, bool manager) {
    final key = isoDate(date);
    final id = row.machine['id'] as int;
    final booked = row.bookedDates.contains(key);
    final busy = _pending.contains((id, key));
    final label = booked ? 'Scheduled' : 'Available';
    return _CalendarCell(
      width: _dayWidth,
      child: manager && !busy
          ? Semantics(
              label: '${row.machine['name']}, ${prettyDate(date)}, $label',
              excludeSemantics: false,
              child: TextButton(
                key: ValueKey('schedule-$id-$key'),
                onPressed: () => _changeBooking(row.machine, date, booked),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
                child: ToneBadge(
                  label,
                  booked ? runningGreen : unconfirmedGrey,
                ),
              ),
            )
          : ToneBadge(label, booked ? runningGreen : unconfirmedGrey),
    );
  }
}

class _CalendarCell extends StatelessWidget {
  const _CalendarCell({required this.width, required this.child, this.color});
  final double width;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: _rowHeight,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color,
      border: Border(
        bottom: BorderSide(color: Theme.of(context).dividerColor),
        right: BorderSide(color: Theme.of(context).dividerColor),
      ),
    ),
    child: child,
  );
}
