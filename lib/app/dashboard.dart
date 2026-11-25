import 'package:flutter/material.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/domain.dart';
import '../core/repository.dart';
import '../features/profile/profile.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/authentication/authentication.dart';
import '../features/job_entry/jobs.dart';
import '../features/machine_status/machines.dart';
import '../features/production_entry/production.dart';
import '../features/program_schedule/schedule.dart';
import '../features/reports/reports.dart';

extension on Module {
  IconData get icon => switch (this) {
    Module.machines => Icons.precision_manufacturing_outlined,
    Module.schedule => Icons.calendar_month_outlined,
    Module.jobs => Icons.assignment_outlined,
    Module.production => Icons.inventory_2_outlined,
    Module.reports => Icons.bar_chart_rounded,
    Module.profile => Icons.person_outline,
  };
  String get description => switch (this) {
    Module.machines => 'See which machines are running today.',
    Module.schedule => 'Review machine availability and bookings by date.',
    Module.jobs => 'Create jobs and manage their knitting programs.',
    Module.production => 'Record shift output and check remaining quantities.',
    Module.reports => 'Review production and export company reports.',
    Module.profile => 'Manage your account and settings.',
  };
}

class Dashboard extends StatefulWidget {
  const Dashboard({
    super.key,
    required this.staff,
    required this.logout,
    required this.theme,
    required this.onTheme,
    this.openModule,
  });
  final Staff staff;
  final Future<void> Function() logout;
  final ThemeMode theme;
  final ValueChanged<ThemeMode> onTheme;
  final ValueChanged<Module>? openModule;
  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  bool leaving = false;

  List<Module> get modules =>
      Module.values.where((m) => m.availableTo(widget.staff.role)).toList();

  void navigate(Module? module) {
    if (module == null || !module.availableTo(widget.staff.role)) return;
    if (widget.openModule case final open?) {
      open(module);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ModulePage(
          module: module,
          role: widget.staff.role,
          logout: () => logout(onProfile: true),
        ),
      ),
    );
  }

  Future<void> logout({bool onProfile = false}) async {
    if (leaving) return;
    final approved = await confirm(
      context,
      'Sign out?',
      'You will need your work credentials to sign in again.',
      action: 'Sign out',
    );
    if (!mounted || !approved) return;
    setState(() => leaving = true);
    if (onProfile) Navigator.of(context).popUntil((route) => route.isFirst);
    await widget.logout();
    if (mounted) setState(() => leaving = false);
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final wide = bounds.maxWidth >= 1030;

      return Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          title: Row(
            children: [
              if (!wide) ...[const Logo(size: 36), const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  wide ? 'Dashboard' : companyName,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          actions: [
            ThemeMenu(mode: widget.theme, onChanged: widget.onTheme),
            if (!wide)
              IconButton(
                tooltip: 'Sign out',
                onPressed: leaving ? null : logout,
                icon: const Icon(Icons.logout),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: SafeArea(
          child: Row(
            children: [
              if (wide)
                _Sidebar(
                  staff: widget.staff,
                  modules: modules,
                  selected: null,
                  onNavigate: navigate,
                  logout: leaving ? null : logout,
                ),
              Expanded(
                child: _Home(
                  staff: widget.staff,
                  modules: modules,
                  navigate: navigate,
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.staff,
    required this.modules,
    required this.selected,
    required this.onNavigate,
    required this.logout,
  });
  final Staff staff;
  final List<Module> modules;
  final Module? selected;
  final ValueChanged<Module?> onNavigate;
  final VoidCallback? logout;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 244,
      margin: const EdgeInsets.fromLTRB(12, 0, 0, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(5, 12, 4, 20),
            child: Row(
              children: [
                const Logo(size: 48),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(companyName, style: theme.textTheme.titleSmall),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                _link(context, 'Dashboard', Icons.dashboard_outlined, null),
                for (final module in modules)
                  _link(
                    context,
                    module.titleFor(staff.role),
                    module.icon,
                    module,
                  ),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 7),
            leading: const Icon(Icons.account_circle_outlined),
            title: Text(
              staff.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(staff.role.label),
            trailing: IconButton(
              tooltip: 'Sign out',
              onPressed: logout,
              icon: const Icon(Icons.logout),
            ),
          ),
        ],
      ),
    );
  }

  Widget _link(
    BuildContext context,
    String label,
    IconData icon,
    Module? module,
  ) {
    final color = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        dense: true,
        selected: selected == module,
        selectedTileColor: color.primary.withValues(alpha: .12),
        leading: Icon(icon, size: 21),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: () => onNavigate(module),
      ),
    );
  }
}

class _Home extends StatelessWidget {
  const _Home({
    required this.staff,
    required this.modules,
    required this.navigate,
  });
  final Staff staff;
  final List<Module> modules;
  final ValueChanged<Module> navigate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PageBody(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: millBlue,
            borderRadius: BorderRadius.circular(25),
          ),
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mill operations',
                  style: theme.textTheme.headlineLarge?.copyWith(
                    color: softCream,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  '${staff.name} · ${staff.role.label}',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
                const SizedBox(height: 23),
                IndiaClock(
                  builder: (context, window) => Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      _HeaderDetail(
                        Icons.today_outlined,
                        prettyDate(indiaToday()),
                      ),
                      _HeaderDetail(
                        Icons.schedule,
                        '${window.shift.label} shift · IST',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const _DashboardMachineSummary(),
        LayoutBuilder(
          builder: (context, bounds) {
            final columns = bounds.maxWidth >= 860
                ? 3
                : bounds.maxWidth >= 530
                ? 2
                : 1;
            final width = (bounds.maxWidth - (columns - 1) * 14) / columns;
            return Wrap(
              spacing: 14,
              runSpacing: 14,
              children: [
                for (final module in modules)
                  SizedBox(
                    width: width,
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: () => navigate(module),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(11),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primary
                                          .withValues(alpha: .11),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      module.icon,
                                      color: theme.colorScheme.primary,
                                      size: 26,
                                    ),
                                  ),
                                  Icon(
                                    Icons.arrow_outward,
                                    size: 19,
                                    color: theme.colorScheme.primary,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                module.titleFor(staff.role),
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                module.description,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _HeaderDetail extends StatelessWidget {
  const _HeaderDetail(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: .14),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: softCream),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

final _dashboardMachines = FutureProvider.autoDispose
    .family<List<RowData>, DateTime>((ref, date) {
      final repository = ref.watch(millDataProvider);
      if (repository == null) return const [];
      ref.watch(revisionsProvider(Dataset.machines));
      return repository.machineDay(date);
    });

class _DashboardMachineSummary extends ConsumerWidget {
  const _DashboardMachineSummary();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final machines = ref.watch(_dashboardMachines(indiaToday())).value;
    if (machines == null || (ref.watch(millDataProvider) == null)) {
      return const SizedBox.shrink();
    }
    final running = machines.where((row) => row['running'] == true).length;
    return Wrap(
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
    );
  }
}

class ModulePage extends StatelessWidget {
  const ModulePage({
    super.key,
    required this.module,
    required this.role,
    required this.logout,
  });
  final Module module;
  final StaffRole role;
  final Future<void> Function() logout;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(module.label)),
    body: SafeArea(
      child: switch (module) {
        Module.machines => MachineScreen(role: role),
        Module.schedule => ScheduleScreen(role: role),
        Module.jobs => const JobsScreen(),
        Module.production => const ProductionScreen(),
        Module.reports => const ReportsScreen(),
        Module.profile => ProfileScreen(logout: logout),
      },
    ),
  );
}
