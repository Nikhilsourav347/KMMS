import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/domain.dart';
import '../core/local_auth.dart';
import '../core/local_database.dart';
import '../core/repository.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/authentication/authentication.dart';
import 'dashboard.dart';
import 'routing.dart';

const _onboardedKey = 'ukm_onboarding_complete_v1';
const _themeKey = 'ukm_theme';

class MillApp extends StatefulWidget {
  const MillApp({super.key});
  @override
  State<MillApp> createState() => _MillAppState();
}

class _MillAppState extends State<MillApp> {
  final preferences = SharedPreferencesAsync();
  late final router = MillRouter(
    home: (context) => AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 230),
      child: _destination(context),
    ),
    role: () => staff?.role,
    page: (context, module, role) => ModulePage(
      module: module,
      role: role,
      logout: () async {
        if (await confirm(
              context,
              'Sign out?',
              'Use your local credentials to sign in again.',
              action: 'Sign out',
            ) &&
            context.mounted) {
          await logout(context);
        }
      },
    ),
  );
  final backButton = RootBackButtonDispatcher();

  void refresh(VoidCallback update) {
    setState(update);
    router.refresh();
  }

  MillRepository? repository;
  Staff? staff;
  bool ready = false;
  bool onboarded = false;
  bool hasAccounts = false;
  bool saving = false;
  bool startupError = false;
  ThemeMode theme = ThemeMode.light;

  @override
  void initState() {
    super.initState();

    _initialize();
  }

  Future<void> _initialize() async {
    MillRepository? opening;
    try {
      final savedOnboarding = await preferences.getBool(_onboardedKey);
      final savedTheme = await preferences.getString(_themeKey);
      final db = await openMillDatabase();
      final auth = LocalAuth(db);
      opening = MillRepository(db, auth);

      final accountsExist = await auth.hasAccounts;
      final session = accountsExist ? await auth.restore() : null;
      if (!mounted) {
        await db.close();
        return;
      }
      refresh(() {
        repository = opening;
        staff = session;
        onboarded = savedOnboarding == true;
        theme = ThemeMode.values.asNameMap()[savedTheme] ?? ThemeMode.light;
        hasAccounts = accountsExist;
        ready = true;
      });
    } catch (_) {
      await opening?.db.close();
      if (mounted) refresh(() => startupError = true);
    }
  }

  Future<void> complete() async {
    if (saving) return;
    refresh(() => saving = true);
    try {
      await preferences.setBool(_onboardedKey, true);
      if (mounted) refresh(() => onboarded = true);
    } finally {
      if (mounted) refresh(() => saving = false);
    }
  }

  Future<void> changeTheme(ThemeMode next) async {
    refresh(() => theme = next);
    await preferences.setString(_themeKey, next.name);
  }

  Future<void> logout(BuildContext context) async {
    try {
      await repository!.auth.signOut();
      if (mounted) refresh(() => staff = null);
    } catch (error) {
      if (context.mounted) notify(context, friendlyError(error));
    }
  }

  @override
  void dispose() {
    router.dispose();
    unawaited(repository?.db.close());
    super.dispose();
  }

  Widget _destination(BuildContext context) {
    if (!ready) {
      return startupError
          ? _StartupError(
              retry: () {
                refresh(() => startupError = false);
                _initialize();
              },
            )
          : const SplashScreen();
    }
    if (!onboarded) {
      return OnboardingScreen(onContinue: complete, saving: saving);
    }
    final auth = repository!.auth;
    if (!hasAccounts) {
      return LocalSetupScreen(
        auth: auth,
        onComplete: () => refresh(() => hasAccounts = true),
      );
    }
    final user = repository?.auth.currentStaff ?? staff;
    if (user == null) {
      return LoginScreen(
        auth: auth,
        theme: theme,
        onTheme: changeTheme,
        onSignIn: (signedIn) => refresh(() => staff = signedIn),
      );
    }
    return Dashboard(
      key: ValueKey(user.role),
      staff: user,
      theme: theme,
      onTheme: changeTheme,
      logout: () => logout(context),
      openModule: (module) => router.open(context, module),
    );
  }

  @override
  Widget build(BuildContext context) => ProviderScope(
    overrides: [localRepositoryProvider.overrideWithValue(repository)],
    child: MaterialApp.router(
      title: companyName,
      debugShowCheckedModeBanner: false,
      theme: millTheme(Brightness.light),
      darkTheme: millTheme(Brightness.dark),
      themeMode: theme,
      routerDelegate: router,
      routeInformationParser: const MillRouteParser(),
      backButtonDispatcher: backButton,
    ),
  );
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.retry});
  final VoidCallback retry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: PageBody(
        children: [
          Notice(
            'The local database could not be opened. Try again.',
            icon: Icons.error_outline,
            action: FilledButton(onPressed: retry, child: const Text('Retry')),
          ),
        ],
      ),
    ),
  );
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: TweenAnimationBuilder<double>(
            duration: reduced
                ? Duration.zero
                : const Duration(milliseconds: 430),
            curve: Curves.easeOutCubic,
            tween: Tween(begin: .83, end: 1),
            builder: (context, progress, child) => Opacity(
              opacity: ((progress - .82) * 5.56).clamp(0.0, 1.0),
              child: Transform.scale(scale: progress, child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Logo(size: 106),
                const SizedBox(height: 24),
                Text(
                  companyName,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 24),
                Semantics(
                  label: 'Initializing',
                  child: const SizedBox(
                    width: 104,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      borderRadius: BorderRadius.all(Radius.circular(3)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({
    super.key,
    required this.onContinue,
    this.saving = false,
  });
  final Future<void> Function() onContinue;
  final bool saving;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: Panel(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Logo(size: 76),
                    const SizedBox(height: 12),
                    Text(
                      'Welcome to Unique Knitting Mills',
                      style: text.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Track machine status, schedule bookings and record daily production on this phone.',
                    ),
                    const SizedBox(height: 16),
                    const _Guide(
                      Icons.lock_outline,
                      'Secure access',
                      'Set up the first administrator, then use Profile to add staff. Keep their recovery keys safe and sign out on shared devices.',
                    ),
                    const _Guide(
                      Icons.sync_outlined,
                      'Offline storage',
                      'Your records stay on this device. Sign-in and data entry work without internet. Wait for the save confirmation before leaving a form.',
                    ),
                    const _Guide(
                      Icons.picture_as_pdf_outlined,
                      'PDF reports',
                      'Open Reports to preview, download, print or share a PDF. The app uses the device’s file, print or sharing tools when you choose an action.',
                    ),
                    const _Guide(
                      Icons.privacy_tip_outlined,
                      'Data and privacy',
                      'This device records who made changes. Save copies of important PDF reports outside the app and share them with authorized recipients.',
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: saving
                            ? null
                            : () async {
                                try {
                                  await onContinue();
                                } catch (_) {
                                  if (context.mounted) {
                                    notify(
                                      context,
                                      'Could not save your preference. Try again.',
                                    );
                                  }
                                }
                              },
                        icon: const Icon(Icons.arrow_forward),
                        label: Text(saving ? 'Saving…' : 'Get started'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide(this.icon, this.title, this.text);
  final IconData icon;
  final String title;
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 21, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 3),
              Text(text),
            ],
          ),
        ),
      ],
    ),
  );
}
