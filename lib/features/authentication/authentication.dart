import 'package:flutter/material.dart';

import '../../core/auth.dart';
import '../../core/domain.dart';
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

  final MillAuth auth;
  final ValueChanged<Staff>? onSignIn;
  final ThemeMode theme;
  final ValueChanged<ThemeMode>? onTheme;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController();
  final password = TextEditingController();
  StaffRole role = StaffRole.manager;
  bool visible = false;
  bool busy = false;
  late String? error = widget.auth.recoveryError;
  bool needsVerification = false;

  Future<void> signIn() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
      needsVerification = false;
    });
    try {
      final staff = await widget.auth.signIn(
        email.text,
        password.text,
        role: role,
      );
      if (mounted) widget.onSignIn?.call(staff);
    } catch (failure) {
      if (mounted) {
        setState(() {
          error = friendlyError(failure);
          needsVerification = failure is EmailVerificationRequired;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resendVerification() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await widget.auth.requestEmailVerification(email.text);
      if (mounted) {
        setState(() => error = 'Check your email for the verification link.');
      }
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
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
                  horizontal: 18,
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 940),
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      final wide = bounds.maxWidth >= 740;
                      final fields = Padding(
                        padding: EdgeInsets.all(wide ? 38 : 22),
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
                                  const SizedBox(height: 10),
                                  Text(companyName, style: text.titleLarge),
                                  const SizedBox(height: 22),
                                ],
                                Text('Sign in', style: text.headlineMedium),
                                const SizedBox(height: 5),
                                const Text(
                                  'Use your Unique Knitting Mills staff account.',
                                ),
                                const SizedBox(height: 20),
                                SegmentedButton<StaffRole>(
                                  direction: bounds.maxWidth < 290
                                      ? Axis.vertical
                                      : Axis.horizontal,
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
                                    labelText: 'Email address',
                                    prefixIcon: Icon(Icons.mail_outline),
                                  ),
                                  validator: (value) => validEmail(value ?? '')
                                      ? null
                                      : 'Enter a valid work email.',
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: password,
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
                                      onPressed: busy
                                          ? null
                                          : () => setState(
                                              () => visible = !visible,
                                            ),
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
                                    onPressed: busy
                                        ? null
                                        : () => showDialog<void>(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (_) =>
                                                ForgotPasswordDialog(
                                                  auth: widget.auth,
                                                  initialEmail: email.text,
                                                ),
                                          ),
                                    child: const Text('Forgot password?'),
                                  ),
                                ),
                                if (error case final message?)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Text(
                                      message,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                    ),
                                  ),
                                if (needsVerification)
                                  TextButton(
                                    onPressed: busy ? null : resendVerification,
                                    child: const Text(
                                      'Resend verification email',
                                    ),
                                  ),
                                FilledButton.icon(
                                  key: const ValueKey('sign-in-action'),
                                  onPressed: busy ? null : signIn,
                                  icon: busy
                                      ? const SizedBox.square(
                                          dimension: 17,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.login),
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
                            ? Row(
                                children: [
                                  Expanded(
                                    child: ColoredBox(
                                      color: millBlue,
                                      child: Padding(
                                        padding: const EdgeInsets.all(38),
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
                                  Expanded(child: fields),
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

class ForgotPasswordDialog extends StatefulWidget {
  const ForgotPasswordDialog({
    super.key,
    required this.auth,
    required this.initialEmail,
  });

  final MillAuth auth;
  final String initialEmail;

  @override
  State<ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<ForgotPasswordDialog> {
  late final email = TextEditingController(text: widget.initialEmail);
  final code = TextEditingController();
  final password = TextEditingController();
  bool busy = false;
  bool sent = false;
  bool useCode = false;
  bool completed = false;
  String? error;

  Future<void> send() async {
    if (busy || !validEmail(email.text)) {
      setState(() => error = 'Enter a valid work email.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.requestRecovery(email.text);
      if (mounted) setState(() => sent = true);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> resetWithCode() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.recoverWithCode(email.text, code.text, password.text);
      if (mounted) setState(() => completed = true);
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    email.dispose();
    code.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    scrollable: true,
    title: const Text('Reset password'),
    content: SizedBox(
      width: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            completed
                ? 'Password updated. Sign in with your new password.'
                : sent
                ? 'Check your inbox for a recovery link or one-time code.'
                : 'Enter your work email to request password recovery.',
          ),
          if (!completed && (!sent || useCode)) ...[
            const SizedBox(height: 14),
            TextField(
              controller: email,
              enabled: !busy,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email address'),
              onSubmitted: (_) {
                if (!useCode) send();
              },
            ),
          ],
          if (!completed && useCode) ...[
            const SizedBox(height: 12),
            TextField(
              controller: code,
              enabled: !busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              decoration: const InputDecoration(labelText: 'Recovery code'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: password,
              enabled: !busy,
              obscureText: true,
              autofillHints: const [AutofillHints.newPassword],
              decoration: const InputDecoration(labelText: 'New password'),
            ),
          ],
          if (error case final message?) ...[
            const SizedBox(height: 10),
            Text(
              message,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(completed || sent && !useCode ? 'Done' : 'Cancel'),
      ),
      if (!completed && !useCode)
        TextButton(
          onPressed: busy
              ? null
              : () => setState(() {
                  useCode = true;
                  error = null;
                }),
          child: const Text('Enter recovery code'),
        ),
      if (!sent && !useCode)
        FilledButton(
          onPressed: busy ? null : send,
          child: Text(busy ? 'Sending…' : 'Send recovery link'),
        ),
      if (useCode && !completed)
        FilledButton(
          onPressed: busy ? null : resetWithCode,
          child: Text(busy ? 'Updating…' : 'Update password'),
        ),
    ],
  );
}

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({
    super.key,
    required this.auth,
    required this.onComplete,
  });

  final MillAuth auth;
  final VoidCallback onComplete;

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final form = GlobalKey<FormState>();
  final password = TextEditingController();
  final confirmation = TextEditingController();
  bool visible = false;
  bool busy = false;
  String? error;

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.auth.completeRecovery(password.text);
      if (mounted) widget.onComplete();
    } catch (failure) {
      if (mounted) setState(() => error = friendlyError(failure));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    password.dispose();
    confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Panel(
              padding: const EdgeInsets.all(24),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Logo(size: 76),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      companyName,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Create a new password',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Use at least 12 characters. You will return to sign in after the password is updated.',
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: password,
                      enabled: !busy,
                      obscureText: !visible,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: InputDecoration(
                        labelText: 'New password',
                        suffixIcon: IconButton(
                          onPressed: busy
                              ? null
                              : () => setState(() => visible = !visible),
                          tooltip: visible ? 'Hide password' : 'Show password',
                          icon: Icon(
                            visible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                      validator: (value) => (value?.length ?? 0) < 12
                          ? 'Use at least 12 characters.'
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: confirmation,
                      enabled: !busy,
                      obscureText: !visible,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                      ),
                      validator: (value) => value != password.text
                          ? 'Passwords do not match.'
                          : null,
                      onFieldSubmitted: (_) => save(),
                    ),
                    if (error case final message?) ...[
                      const SizedBox(height: 10),
                      Text(
                        message,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: busy ? null : save,
                      child: Text(busy ? 'Updating…' : 'Update password'),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              try {
                                await widget.auth.signOut();
                                if (mounted) widget.onComplete();
                              } catch (failure) {
                                if (mounted) {
                                  setState(
                                    () => error = friendlyError(failure),
                                  );
                                }
                              }
                            },
                      child: const Text('Back to sign in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
