import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/domain.dart';
import '../../core/local_auth.dart';
import '../../core/repository.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.auth,
    this.onSignIn,
    this.theme = ThemeMode.light,
    this.onTheme,
  });
  final LocalAuth? auth;
  final ValueChanged<Staff>? onSignIn;
  final ThemeMode theme;
  final ValueChanged<ThemeMode>? onTheme;
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final pass = TextEditingController();
  StaffRole role = StaffRole.manager;
  bool visible = false;
  bool busy = false;
  String? error;

  Future<void> signIn() async {
    if (busy || widget.auth == null || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final staff = await widget.auth!.signIn(
        email.text,
        pass.text,
        role: role,
      );
      if (mounted) widget.onSignIn?.call(staff);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 28,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final wide = bounds.maxWidth >= 745;
                      final fields = Padding(
                        padding: EdgeInsets.all(wide ? 37 : 23),
                        child: Form(
                          key: form,
                          child: AutofillGroup(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (!wide) ...[
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Logo(size: 76),
                                  ),
                                  const SizedBox(height: 9),
                                  Text(companyName, style: text.titleLarge),
                                  const SizedBox(height: 24),
                                ],
                                Text('Sign in', style: text.headlineMedium),
                                const SizedBox(height: 5),
                                const Text(
                                  'Local testing · Use the account registered for Unique Knitting Mills.',
                                ),
                                const SizedBox(height: 20),
                                SegmentedButton<StaffRole>(
                                  showSelectedIcon: false,
                                  selected: {role},
                                  onSelectionChanged: busy
                                      ? null
                                      : (values) =>
                                            setState(() => role = values.first),
                                  segments: const [
                                    ButtonSegment(
                                      value: StaffRole.manager,
                                      label: Text('Manager Login'),
                                    ),
                                    ButtonSegment(
                                      value: StaffRole.admin,
                                      label: Text('Admin Login'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                TextFormField(
                                  controller: email,
                                  enabled: !busy,
                                  autofillHints: const [AutofillHints.username],
                                  keyboardType: TextInputType.emailAddress,
                                  textInputAction: TextInputAction.next,
                                  decoration: const InputDecoration(
                                    labelText: 'Work email',
                                    prefixIcon: Icon(Icons.mail_outline),
                                  ),
                                  validator: (value) => validEmail(value ?? '')
                                      ? null
                                      : 'Enter a valid work email.',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: pass,
                                  enabled: !busy,
                                  obscureText: !visible,
                                  autofillHints: const [AutofillHints.password],
                                  onFieldSubmitted: (_) => signIn(),
                                  validator: (value) => (value ?? '').isEmpty
                                      ? 'Enter your password.'
                                      : null,
                                  decoration: InputDecoration(
                                    labelText: 'Password',
                                    prefixIcon: const Icon(Icons.lock_outline),
                                    suffixIcon: IconButton(
                                      onPressed: () =>
                                          setState(() => visible = !visible),
                                      tooltip: visible
                                          ? 'Hide password'
                                          : 'Show password',
                                      icon: Icon(
                                        visible
                                            ? Icons.visibility_off_outlined
                                            : Icons.visibility_outlined,
                                      ),
                                    ),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: TextButton(
                                    onPressed: busy || widget.auth == null
                                        ? null
                                        : () async {
                                            await showDialog<void>(
                                              context: context,
                                              barrierDismissible: false,
                                              builder: (_) => _RecoveryDialog(
                                                auth: widget.auth!,
                                                initialEmail: email.text,
                                              ),
                                            );
                                          },
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                                if (error != null)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      error!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                FilledButton.icon(
                                  key: const ValueKey('sign-in-action'),
                                  onPressed: busy || widget.auth == null
                                      ? null
                                      : signIn,
                                  icon: busy
                                      ? const SizedBox.square(
                                          dimension: 17,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.arrow_forward),
                                  label: Text(busy ? 'Signing in…' : 'Sign in'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                      return Card(
                        clipBehavior: Clip.antiAlias,
                        child: wide
                            ? Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    width: bounds.maxWidth / 2,
                                    child: ColoredBox(
                                      color: millBlue,
                                      child: Padding(
                                        padding: const EdgeInsets.all(36),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Logo(size: 100),
                                            const SizedBox(height: 28),
                                            Text(
                                              companyName,
                                              style: text.headlineLarge
                                                  ?.copyWith(color: softCream),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: SizedBox(
                                      width: bounds.maxWidth / 2,
                                      child: fields,
                                    ),
                                  ),
                                ],
                              )
                            : fields,
                      );
                    },
                  ),
                ),
              ),
            ),
            if (widget.onTheme case final change?)
              Positioned(
                right: 10,
                top: 4,
                child: ThemeMenu(mode: widget.theme, onChanged: change),
              ),
          ],
        ),
      ),
    );
  }
}

class ThemeMenu extends StatelessWidget {
  const ThemeMenu({super.key, required this.mode, required this.onChanged});
  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;
  @override
  Widget build(BuildContext context) => PopupMenuButton<ThemeMode>(
    icon: const Icon(Icons.contrast),
    tooltip: 'Appearance',
    initialValue: mode,
    onSelected: onChanged,
    itemBuilder: (_) => const [
      PopupMenuItem(value: ThemeMode.light, child: Text('Light')),
      PopupMenuItem(value: ThemeMode.dark, child: Text('Dark')),
      PopupMenuItem(value: ThemeMode.system, child: Text('System')),
    ],
  );
}

class LocalSetupScreen extends StatefulWidget {
  const LocalSetupScreen({
    super.key,
    required this.auth,
    required this.onComplete,
  });
  final LocalAuth auth;
  final VoidCallback onComplete;
  @override
  State<LocalSetupScreen> createState() => _LocalSetupState();
}

class _AccountFields {
  final name = TextEditingController();
  final email = TextEditingController();
  final password = TextEditingController();
  AccountSetup get values => AccountSetup(name.text, email.text, password.text);
  void dispose() {
    name.dispose();
    email.dispose();
    password.dispose();
  }
}

class _LocalSetupState extends State<LocalSetupScreen> {
  final key = GlobalKey<FormState>();
  final admin = _AccountFields();

  bool busy = false;
  String? error;

  Future<void> save() async {
    if (busy || !key.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final codes = await widget.auth.setup(admin.values);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RecoveryKeys(codes: codes),
      );
      if (mounted) widget.onComplete();
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    admin.dispose();

    super.dispose();
  }

  Widget account(String label, _AccountFields fields) => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(label, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 12),
        TextFormField(
          controller: fields.name,
          enabled: !busy,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Full name'),
          validator: (text) => (text ?? '').trim().isEmpty
              ? 'Enter the staff member’s name.'
              : null,
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: fields.email,
          enabled: !busy,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Work email'),
          validator: (text) =>
              validEmail(text ?? '') ? null : 'Enter a valid work email.',
        ),
        const SizedBox(height: 10),
        TextFormField(
          controller: fields.password,
          enabled: !busy,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Password',
            helperText: 'At least 12 characters',
          ),
          validator: (text) =>
              (text?.length ?? 0) < 12 ? 'Use at least 12 characters.' : null,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(companyName),
      leading: const Padding(padding: EdgeInsets.all(8), child: Logo(size: 40)),
    ),
    body: SafeArea(
      child: Form(
        key: key,
        child: PageBody(
          children: [
            const SectionTitle(
              'Set up this installation',
              detail:
                  'Create the first administrator on this installation. Sign in as that administrator to add staff.',
            ),
            account('Administrator', admin),

            if (error case final message?)
              Text(
                message,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: busy ? null : save,
                icon: const Icon(Icons.lock_outline),
                label: Text(
                  busy ? 'Creating accounts…' : 'Create administrator',
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecoveryKeys extends StatelessWidget {
  const _RecoveryKeys({required this.codes});
  final List<RecoveryKey> codes;
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Save recovery keys'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Store these keys somewhere safe. Each key can reset its account’s password on this device.',
            ),
            for (final code in codes) ...[
              const SizedBox(height: 14),
              Text(
                code.role.label,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Row(
                children: [
                  Expanded(child: SelectableText(code.value)),
                  IconButton(
                    tooltip: 'Copy ${code.role.label} key',
                    icon: const Icon(Icons.copy_outlined),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: code.value));
                      if (context.mounted) {
                        notify(context, 'Recovery key copied.');
                      }
                    },
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('I saved the keys'),
        ),
      ],
    ),
  );
}

class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog({required this.auth, required this.initialEmail});
  final LocalAuth auth;
  final String initialEmail;
  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  late final email = TextEditingController(text: widget.initialEmail);
  final key = TextEditingController();
  final pass = TextEditingController();
  bool busy = false;
  String? replacement;
  String? error;

  Future<void> reset() async {
    if (busy) return;
    if (!validEmail(email.text) ||
        key.text.trim().isEmpty ||
        pass.text.length < 12) {
      setState(
        () => error =
            'Enter the work email, recovery key and a new password of at least 12 characters.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final code = await widget.auth.recover(email.text, key.text, pass.text);
      if (mounted) setState(() => replacement = code);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    key.dispose();
    pass.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: noBlock,
    child: AlertDialog(
      title: Text(
        replacement == null ? 'Reset password' : 'Save the new recovery key',
      ),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (replacement case final code?) ...[
                const Text(
                  'Your password changed. Keep this replacement key somewhere safe.',
                ),
                const SizedBox(height: 10),
                SelectableText(code),
              ] else ...[
                const Text(
                  'Use the recovery key saved when this account was created.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: email,
                  enabled: !busy,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Work email'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: key,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: 'Recovery key'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: pass,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'New password'),
                ),
              ],
              if (error case final message?) ...[
                const SizedBox(height: 8),
                Text(message),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (replacement == null) ...[
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: busy ? null : reset,
            child: Text(busy ? 'Updating…' : 'Reset password'),
          ),
        ] else
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('I saved the key'),
          ),
      ],
    ),
  );
  bool get noBlock => !busy && replacement == null;
}
