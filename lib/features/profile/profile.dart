import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/domain.dart';
import '../../core/auth.dart';
import '../../core/repository.dart';
import '../../core/widgets.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key, required this.logout});
  final Future<void> Function() logout;

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileState();
}

class _ProfileState extends ConsumerState<ProfileScreen> {
  MillData get repository => ref.read(repositoryProvider);
  late Future<RowData> profile = repository.auth.profile();
  Future<List<RowData>>? managers;

  void refresh() => setState(() {
    profile = repository.auth.profile();
    managers = null;
  });

  Future<bool> _form(
    String title,
    List<({String label, String value})> fields,
    Future<void> Function(List<String>) save,
  ) async {
    final changed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _EditDialog(title: title, fields: fields, save: save),
    );
    if (mounted && changed == true) refresh();
    return changed == true;
  }

  Future<void> addAccount(StaffRole role) async {
    final created = await _form(
      'Add ${role.label}',
      [
        (label: 'Name', value: ''),
        (label: 'Email address', value: ''),
        (label: 'Phone number', value: ''),
        (label: 'Initial password', value: ''),
      ],
      (v) async {
        await repository.auth.addAccount(
          role,
          AccountSetup(v[0], v[1], v[3]),
          phone: v[2],
        );
      },
    );
    if (!mounted || !created) return;
    notify(context, '${role.label} account created.');
  }

  Future<void> editMachine([RowData? machine]) => _form(
    machine == null ? 'Add Machine' : 'Edit Machine',
    [
      (
        label: 'Machine number',
        value: (machine?['number'] ?? machine?['name'] ?? '') as String,
      ),
      (label: 'DIA', value: machine?['dia']?.toString() ?? ''),
      (
        label: 'Machine type (optional)',
        value: machine?['type'] as String? ?? '',
      ),
      (
        label: 'Specifications (optional)',
        value: machine?['specifications'] as String? ?? '',
      ),
    ],
    (values) async {
      final dia = int.tryParse(values[1].trim());
      if (dia == null || dia < 1 || dia > 999) {
        throw const MillError('Enter a whole-number DIA from 1 to 999.');
      }
      await repository.saveMachine(
        id: machine?['id'],
        number: values[0],
        dia: dia,
        type: values[2],
        specifications: values[3],
      );
      if (mounted) ref.invalidate(_profileMachines);
    },
  );

  Future<void> removeMachine(RowData machine) async {
    if (!await confirm(
      context,
      'Remove ${machine['name']}?',
      'This removes the machine from active lists. Historical records are kept.',
      action: 'Remove',
    )) {
      return;
    }
    try {
      await repository.removeMachine(machine['id']);
      if (mounted) ref.invalidate(_profileMachines);
    } catch (error) {
      if (mounted) notify(context, friendlyError(error));
    }
  }

  Future<void> toggleManager(RowData manager) async {
    try {
      await repository.auth.setManagerEnabled(
        manager['email'],
        manager['disabled'] == true,
      );
      if (mounted) setState(() => managers = repository.auth.managers());
    } catch (error) {
      if (mounted) notify(context, friendlyError(error));
    }
  }

  @override
  Widget build(BuildContext context) => PageBody(
    children: [
      const SectionTitle('Profile'),
      FutureBuilder<RowData>(
        future: profile,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Notice(
              friendlyError(snapshot.error!),
              action: TextButton(
                onPressed: refresh,
                child: const Text('Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final row = snapshot.data!;
          final admin = row['role'] == StaffRole.admin.name;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            spacing: 14,
            children: [
              LayoutBuilder(
                builder: (context, sizes) {
                  const gap = 14.0;
                  final width = sizes.maxWidth < 640
                      ? sizes.maxWidth
                      : (sizes.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      SizedBox(width: width, child: _identity(row)),
                      SizedBox(width: width, child: _account(row)),
                      if (admin) SizedBox(width: width, child: _staff()),
                    ],
                  );
                },
              ),
              if (admin)
                loadView(
                  ref.watch(_profileMachines),
                  _machineRegister,
                  () => ref.invalidate(_profileMachines),
                ),
            ],
          );
        },
      ),
    ],
  );

  Widget _identity(RowData row) => _block('Profile details', [
    Text(
      row['full_name'] as String,
      style: Theme.of(context).textTheme.titleMedium,
    ),
    const Text(companyName),
    Text('Mill ID · ${row['mill_id']}'),
    Text('Email · ${row['email']}'),
    Text('Phone · ${cellText(row['phone'])}'),
    Text('Role · ${StaffRole.values.byName(row['role']).label}'),
  ]);

  Widget _account(RowData row) => _block('Account settings', [
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton(
          onPressed: () => _form('Edit profile', [
            (label: 'Name', value: row['full_name'] as String),
            (label: 'Email address', value: row['email'] as String),
            (label: 'Phone number', value: row['phone'] as String),
          ], (v) => repository.auth.editProfile(v[0], v[1], v[2])),
          child: const Text('Edit profile'),
        ),
        OutlinedButton(
          onPressed: () => _form('Change password', [
            (label: 'Current password', value: ''),
            (label: 'New password', value: ''),
          ], (v) => repository.auth.changePassword(v[0], v[1])),
          child: const Text('Change password'),
        ),
        OutlinedButton(onPressed: widget.logout, child: const Text('Logout')),
      ],
    ),
  ]);

  Widget _staff() => _block('Staff accounts', [
    Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        TextButton(
          onPressed: () => addAccount(StaffRole.admin),
          child: const Text('Add Admin'),
        ),
        TextButton(
          onPressed: () => addAccount(StaffRole.manager),
          child: const Text('Add Manager'),
        ),
        TextButton(
          onPressed: () =>
              setState(() => managers = repository.auth.managers()),
          child: const Text('Manage Manager Accounts'),
        ),
      ],
    ),
    if (managers != null)
      FutureBuilder<List<RowData>>(
        future: managers,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Text(friendlyError(snapshot.error!));
          if (!snapshot.hasData) return const LinearProgressIndicator();
          if (snapshot.data!.isEmpty) {
            return const Text('No manager accounts yet.');
          }
          return Column(
            children: [
              for (final manager in snapshot.data!)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(manager['full_name'] as String),
                  subtitle: Text(manager['email'] as String),
                  trailing: TextButton(
                    onPressed: () => toggleManager(manager),
                    child: Text(
                      manager['disabled'] == true ? 'Enable' : 'Disable',
                    ),
                  ),
                ),
            ],
          );
        },
      ),
  ]);

  Widget _machineRegister(List<RowData> machines) =>
      _block('Registered machines · ${machines.length}', [
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: editMachine,
            icon: const Icon(Icons.add),
            label: const Text('Add Machine'),
          ),
        ),
        if (machines.isEmpty)
          const Text('No registered machines.')
        else
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              horizontalMargin: 8,
              columnSpacing: 18,
              dataRowMaxHeight: 84,
              columns: const [
                DataColumn(label: Text('Machine number')),
                DataColumn(label: Text('DIA')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Specifications')),
                DataColumn(label: Text('Actions')),
              ],
              rows: [
                for (final machine in machines)
                  DataRow(
                    cells: [
                      DataCell(
                        Text((machine['number'] ?? machine['name']) as String),
                      ),
                      DataCell(Text(machine['dia']?.toString() ?? 'Not set')),
                      DataCell(Text(cellText(machine['type']))),
                      DataCell(
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            cellText(machine['specifications']),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Edit ${machine['name']}',
                              onPressed: () => editMachine(machine),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: 'Remove ${machine['name']}',
                              onPressed: () => removeMachine(machine),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
      ]);

  Widget _block(String title, List<Widget> children) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 5,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 4),
        ...children,
      ],
    ),
  );
}

final _profileMachines = FutureProvider.autoDispose<List<RowData>>((ref) {
  ref.watch(revisionsProvider(Dataset.machines));
  return ref.watch(repositoryProvider).registeredMachines();
});

class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.title,
    required this.fields,
    required this.save,
  });
  final String title;
  final List<({String label, String value})> fields;
  final Future<void> Function(List<String>) save;
  @override
  State<_EditDialog> createState() => _EditState();
}

class _EditState extends State<_EditDialog> {
  late final inputs = widget.fields
      .map((f) => TextEditingController(text: f.value))
      .toList();
  bool saving = false;
  String? error;

  Future<void> save() async {
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.save(inputs.map((input) => input.text).toList());
      if (mounted) Navigator.pop(context, true);
    } catch (failure) {
      if (mounted) {
        setState(() {
          saving = false;
          error = friendlyError(failure);
        });
      }
    }
  }

  @override
  void dispose() {
    for (final input in inputs) {
      input.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: AlertDialog(
      title: Text(widget.title),
      scrollable: true,
      content: SizedBox(
        width: 430,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          spacing: 10,
          children: [
            for (final (index, field) in widget.fields.indexed)
              TextField(
                controller: inputs[index],
                enabled: !saving,
                keyboardType: field.label == 'DIA'
                    ? TextInputType.number
                    : null,
                obscureText: field.label.toLowerCase().contains('password'),
                decoration: InputDecoration(labelText: field.label),
              ),
            if (error case final message?) Text(message),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: saving ? null : save,
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
