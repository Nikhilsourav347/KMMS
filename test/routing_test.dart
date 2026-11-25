import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ukm/app/routing.dart';
import 'package:ukm/core/domain.dart';

void main() {
  testWidgets(
    'system back exits module routes and direct admin-only URLs are guarded',
    (tester) async {
      final router = MillRouter(
        role: () => StaffRole.manager,
        home: (context) => Scaffold(
          body: TextButton(
            onPressed: () {
              final activeRouter =
                  Router.of(context).routerDelegate as MillRouter;
              activeRouter.open(context, Module.machines);
            },
            child: const Text('Open machines'),
          ),
        ),
        page: (_, module, _) =>
            Scaffold(appBar: AppBar(title: Text(module.label))),
      );
      await tester.pumpWidget(
        MaterialApp.router(
          routerDelegate: router,
          routeInformationParser: const MillRouteParser(),
          backButtonDispatcher: RootBackButtonDispatcher(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Open machines'));
      await tester.pumpAndSettle();
      expect(router.currentConfiguration, '/machines');
      expect(find.text('Machine Running Status'), findsOneWidget);
      expect(await tester.binding.handlePopRoute(), isTrue);
      await tester.pumpAndSettle();
      expect(router.currentConfiguration, '/');
      expect(find.text('Open machines'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();

      final guest = MillRouter(
        role: () => null,
        home: (_) => const SizedBox(),
        page: (_, _, _) => const SizedBox(),
      );
      await guest.setNewRoutePath('/profile');
      expect(guest.currentConfiguration, '/');
      guest.dispose();

      final admin = MillRouter(
        role: () => StaffRole.admin,
        home: (_) => const SizedBox(),
        page: (_, _, _) => const SizedBox(),
      );
      await admin.setNewRoutePath('/production');
      expect(admin.currentConfiguration, '/');
      admin.dispose();
    },
  );
}
