import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

typedef _CardStatus = ({RowData machine, bool running, bool saving});
typedef _MachineDay = ({
  AsyncValue<List<int>> ids,
  Map<int, _CardStatus> cards,
});

final _dayProvider = NotifierProvider.autoDispose
    .family<_MachineDayController, _MachineDay, DateTime>(
      _MachineDayController.new,
    );

class _MachineDayController extends Notifier<_MachineDay> {
  _MachineDayController(this.date);
  final DateTime date;
  final _confirmed = <int, MachineStatus>{};
  final _pending = <int, bool>{};
  final _machines = <int, RowData>{};
  bool _reading = false;
  bool _refreshAgain = false;

  @override
  _MachineDay build() {
    final day = isoDate(date);
    final subscription = ref
        .read(repositoryProvider)
        .machineStatusUpdates
        .listen((event) {
          if (event == null) {
            unawaited(refresh());
          } else if (event.date == day && _accept(event.id, event.status)) {
            _publishCard(event.id);
          }
        });
    ref.onDispose(subscription.cancel);
    unawaited(Future.microtask(refresh));
    return (ids: const AsyncLoading(), cards: const {});
  }

  bool _accept(int id, MachineStatus status, {bool snapshot = false}) {
    final previous = _confirmed[id];
    if (previous != null &&
        (status.revision < previous.revision ||
            (status.revision == previous.revision &&
                (!snapshot || status.revision != 0)))) {
      return false;
    }
    _confirmed[id] = status;
    return true;
  }

  _CardStatus _card(int id) => (
    machine: _machines[id]!,
    running: _pending[id] ?? _confirmed[id]?.running ?? false,
    saving: _pending.containsKey(id),
  );

  void _publishCard(int id) {
    if (!_machines.containsKey(id)) return;
    final card = _card(id);
    if (card == state.cards[id]) return;
    state = (ids: state.ids, cards: {...state.cards, id: card});
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    if (_reading) {
      _refreshAgain = true;
      return;
    }
    _reading = true;
    if (state.ids.hasError) {
      state = (ids: const AsyncLoading(), cards: state.cards);
    }
    try {
      do {
        _refreshAgain = false;
        try {
          final rows = await ref.read(repositoryProvider).machineDay(date);
          if (!ref.mounted) return;
          final next = <int, RowData>{};
          for (final row in rows) {
            final id = row['id'] as int;
            _accept(id, (
              running: row['running'] == true,
              revision: row['status_revision'] as int? ?? 0,
            ), snapshot: true);
            final metadata = {...row}
              ..remove('running')
              ..remove('status_revision');
            next[id] = mapEquals(_machines[id], metadata)
                ? _machines[id]!
                : metadata;
          }
          _machines
            ..clear()
            ..addAll(next);
          final ids = next.keys.toList();
          final cards = {for (final id in ids) id: _card(id)};
          if (!listEquals(state.ids.value, ids) ||
              !mapEquals(state.cards, cards)) {
            state = (
              ids: listEquals(state.ids.value, ids)
                  ? state.ids
                  : AsyncData(ids),
              cards: cards,
            );
          }
        } catch (error, stack) {
          if (!ref.mounted) return;
          if (!state.ids.hasValue) {
            state = (ids: AsyncError(error, stack), cards: state.cards);
          }
        }
      } while (_refreshAgain);
    } finally {
      _reading = false;
    }
  }

  Future<void> setRunning(int id, bool running) async {
    if (_pending.containsKey(id) ||
        !_machines.containsKey(id) ||
        _confirmed[id]?.running == running) {
      return;
    }
    final keepAlive = ref.keepAlive();
    _pending[id] = running;
    _publishCard(id);
    try {
      final confirmed = await ref
          .read(repositoryProvider)
          .setRunning(id, date, running);
      if (ref.mounted) _accept(id, confirmed);
    } catch (_) {
      // Reconcile an ambiguous network failure after restoring the confirmed UI.
      if (ref.mounted) unawaited(refresh());
      rethrow;
    } finally {
      _pending.remove(id);
      if (ref.mounted) _publishCard(id);
      keepAlive.close();
    }
  }
}

class MachineScreen extends StatefulWidget {
  const MachineScreen({super.key, required this.role});
  final StaffRole role;

  @override
  State<MachineScreen> createState() => _DayState();
}

class _DayState extends State<MachineScreen> {
  DateTime date = indiaToday();

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      const SectionTitle('Machine Running Status'),
      Align(
        alignment: Alignment.centerLeft,
        child: DateField(
          'Status date',
          date,
          (value) => setState(() => date = value),
        ),
      ),
      _DayMachines(key: ValueKey(date), date: date, role: widget.role),
    ],
  );
}

class _DayMachines extends ConsumerWidget {
  const _DayMachines({super.key, required this.date, required this.role});
  final DateTime date;
  final StaffRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = ref.watch(_dayProvider(date).select((day) => day.ids));
    return loadView(
      ids,
      (machines) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MachineStatusCounts(date: date),
          const SizedBox(height: 12),
          if (machines.isEmpty)
            const Notice('No registered machines.')
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 10.0;
                final columns = switch (constraints.maxWidth) {
                  >= 750 => 3,
                  >= 304 => 2,
                  _ => 1,
                };
                final width =
                    (constraints.maxWidth - (columns - 1) * gap) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final id in machines)
                      SizedBox(
                        key: ValueKey('machine-card-$id'),
                        width: width,
                        child: _MachineCard(id: id, date: date, role: role),
                      ),
                  ],
                );
              },
            ),
        ],
      ),
      () => ref.read(_dayProvider(date).notifier).refresh(),
    );
  }
}

class MachineStatusCounts extends ConsumerWidget {
  const MachineStatusCounts({super.key, required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(millDataProvider) == null) return const SizedBox.shrink();
    final counts = ref.watch(
      _dayProvider(date).select((day) {
        if (!day.ids.hasValue) return null;
        return (
          total: day.cards.length,
          running: day.cards.values.where((card) => card.running).length,
        );
      }),
    );
    if (counts == null) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ToneBadge('Total Machines · ${counts.total}', millBlue),
        ToneBadge('Running Machines · ${counts.running}', runningGreen),
        ToneBadge(
          'Stopped Machines · ${counts.total - counts.running}',
          unconfirmedGrey,
        ),
      ],
    );
  }
}

class _MachineCard extends ConsumerWidget {
  const _MachineCard({
    required this.id,
    required this.date,
    required this.role,
  });
  final int id;
  final DateTime date;
  final StaffRole role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final card = ref.watch(_dayProvider(date).select((day) => day.cards[id]));
    if (card == null) return const SizedBox.shrink();
    final (:machine, :running, :saving) = card;
    final theme = Theme.of(context);
    final admin = role == StaffRole.admin;
    final type = (machine['type'] as String?)?.trim();
    final specifications = (machine['specifications'] as String?)?.trim();
    final number = machine['number'] ?? id;
    return Panel(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(machine['name'] as String, style: theme.textTheme.titleMedium),
          if (admin)
            Text('Machine no. $number', style: theme.textTheme.bodySmall),
          Text(machineDiaLabel(machine), style: theme.textTheme.bodyMedium),
          if (admin && type != null && type.isNotEmpty)
            Text(type, style: theme.textTheme.bodySmall),
          if (admin && specifications != null && specifications.isNotEmpty)
            Text(specifications, style: theme.textTheme.bodySmall),
          const SizedBox(height: 6),
          if (admin)
            _StatusIndicator(running: running)
          else
            Row(
              children: [
                Expanded(
                  child: Text(
                    running ? 'ON' : 'OFF',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: running ? runningGreen : unconfirmedGrey,
                    ),
                  ),
                ),
                Semantics(
                  label: '${machine['name']} running',
                  child: AbsorbPointer(
                    absorbing: saving,
                    child: CupertinoSwitch(
                      value: running,
                      activeTrackColor: runningGreen,
                      inactiveTrackColor: unconfirmedGrey,
                      onChanged: (value) async {
                        try {
                          await ref
                              .read(_dayProvider(date).notifier)
                              .setRunning(id, value);
                        } catch (error) {
                          if (context.mounted) {
                            notify(context, friendlyError(error));
                          }
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _StatusIndicator extends StatefulWidget {
  const _StatusIndicator({required this.running});
  final bool running;

  @override
  State<_StatusIndicator> createState() => _StatusIndicatorState();
}

class _StatusIndicatorState extends State<_StatusIndicator>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  void _syncMotion() {
    if (widget.running && !MediaQuery.disableAnimationsOf(context)) {
      if (!_rotation.isAnimating) _rotation.repeat();
    } else {
      _rotation.reset();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void didUpdateWidget(covariant _StatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncMotion();
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.running ? runningGreen : const Color(0xFFAA3530);
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .09),
        border: Border.all(color: color.withValues(alpha: .28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RotationTransition(
            turns: _rotation,
            child: Icon(Icons.settings, color: color, size: 20),
          ),
          const SizedBox(width: 6),
          Icon(Icons.circle, color: color, size: 8),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              widget.running ? 'Running' : 'Stopped',
              style: TextStyle(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
