import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/auth.dart';
import '../core/domain.dart';
import '../core/repository.dart';
import '../core/supabase_backend.dart';
import '../core/theme.dart';
import '../core/widgets.dart';
import '../features/authentication/authentication.dart';
import 'dashboard.dart';
import 'routing.dart';

const _themeKey = 'ukm_theme';
typedef BackendOpener = Future<MillData> Function();

class MillApp extends StatefulWidget {
  const MillApp({super.key, this.openBackend = openSupabaseBackend});
  final BackendOpener openBackend;

  @override
  State<MillApp> createState() => _MillAppState();
}

class _MillAppState extends State<MillApp> {
  late final preferences = SharedPreferences.getInstance();
  final backButton = RootBackButtonDispatcher();
  late final router = MillRouter(
    home: (context) => AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 230),
      child: _destination(context),
    ),
    role: () => recovery ? null : staff?.role,
    page: (context, module, role) => ModulePage(
      module: module,
      role: role,
      logout: () async {
        if (await confirm(
              context,
              'Sign out?',
              'Use your work credentials to sign in again.',
              action: 'Sign out',
            ) &&
            context.mounted) {
          await logout(context);
        }
      },
    ),
  );

  MillData? repository;
  StreamSubscription<AuthFlow>? authEvents;
  Staff? staff;
  bool ready = false;
  bool initializing = false;
  bool recovery = false;
  String? startupError;
  ThemeMode theme = ThemeMode.light;

  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  void refresh(VoidCallback update) {
    if (!mounted) return;
    setState(update);
    router.refresh();
  }

  Future<void> _initialize() async {
    if (initializing) return;
    initializing = true;
    MillData? opening;
    try {
      opening = await widget.openBackend();
      final auth = opening.auth;
      final session = await auth.restore();
      final savedTheme = (await preferences).getString(_themeKey);
      if (!mounted) {
        await opening.close();
        return;
      }
      authEvents = auth.stateChanges.listen(_handleAuthFlow);
      refresh(() {
        repository = opening;
        staff = session;
        recovery = auth.isPasswordRecovery;
        theme = ThemeMode.values.asNameMap()[savedTheme] ?? ThemeMode.light;
        startupError = null;
        ready = true;
      });
    } catch (error) {
      await opening?.close();
      if (mounted) {
        refresh(() {
          repository = null;
          staff = null;
          ready = false;
          startupError = friendlyError(error);
        });
      }
    } finally {
      initializing = false;
    }
  }

  void _handleAuthFlow(AuthFlow flow) {
    refresh(() {
      staff = null;
      recovery = false;
    });
  }

  Future<void> changeTheme(ThemeMode next) async {
    refresh(() => theme = next);
    await (await preferences).setString(_themeKey, next.name);
  }

  Future<void> logout(BuildContext context) async {
    try {
      await repository!.auth.signOut();
      if (mounted) {
        refresh(() {
          staff = null;
          recovery = false;
        });
      }
    } catch (error) {
      if (context.mounted) notify(context, friendlyError(error));
    }
  }

  @override
  void dispose() {
    router.dispose();
    unawaited(authEvents?.cancel());
    unawaited(repository?.close());
    super.dispose();
  }

  Widget _destination(BuildContext context) {
    final error = startupError;
    if (!ready) {
      return error == null
          ? const SplashScreen()
          : _StartupError(
              message: error,
              retry: () {
                refresh(() => startupError = null);
                unawaited(_initialize());
              },
            );
    }
    final auth = repository!.auth;
    if (recovery || auth.isPasswordRecovery) {
      return PasswordRecoveryScreen(
        auth: auth,
        onComplete: () => refresh(() {
          staff = null;
          recovery = false;
        }),
      );
    }
    final user = auth.currentStaff ?? staff;
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
    overrides: [millDataProvider.overrideWithValue(repository)],
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
  const _StartupError({required this.message, required this.retry});
  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: PageBody(
            children: [
              const Center(child: Logo(size: 92)),
              Notice(
                'Supabase is unavailable. $message',
                icon: Icons.cloud_off_outlined,
                action: FilledButton.icon(
                  onPressed: retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry connection'),
                ),
              ),
            ],
          ),
        ),
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
                const SizedBox(
                  width: 104,
                  child: LinearProgressIndicator(
                    minHeight: 3,
                    borderRadius: BorderRadius.all(Radius.circular(3)),
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
