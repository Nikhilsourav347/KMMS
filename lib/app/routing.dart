import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../core/domain.dart';

class MillRouteParser extends RouteInformationParser<String> {
  const MillRouteParser();

  @override
  Future<String> parseRouteInformation(RouteInformation routeInformation) =>
      SynchronousFuture(routeInformation.uri.path);

  @override
  RouteInformation restoreRouteInformation(String configuration) =>
      RouteInformation(uri: Uri(path: configuration));
}

class MillRouter extends RouterDelegate<String>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<String> {
  MillRouter({required this.home, required this.page, required this.role});

  final WidgetBuilder home;
  final Widget Function(BuildContext, Module, StaffRole) page;
  final StaffRole? Function() role;

  @override
  final navigatorKey = GlobalKey<NavigatorState>();
  Module? _module;

  @override
  String get currentConfiguration =>
      _module == null ? '/' : '/${_module!.name}';

  void open(BuildContext context, Module module) {
    final staffRole = role();
    if (staffRole == null || !module.availableTo(staffRole)) return;
    Router.navigate(context, () {
      _module = module;
      notifyListeners();
    });
  }

  void refresh() {
    if (role() == null) _module = null;
    notifyListeners();
  }

  @override
  Future<void> setNewRoutePath(String configuration) {
    final staffRole = role();
    _module = Module.values
        .where(
          (module) =>
              configuration == '/${module.name}' &&
              staffRole != null &&
              module.availableTo(staffRole),
        )
        .firstOrNull;
    return SynchronousFuture<void>(null);
  }

  @override
  Widget build(BuildContext context) {
    final module = _module;
    final staffRole = role();
    return Navigator(
      key: navigatorKey,
      pages: [
        MaterialPage<void>(
          key: const ValueKey('home'),
          name: '/',
          child: Builder(builder: home),
        ),
        if (module != null &&
            staffRole != null &&
            module.availableTo(staffRole))
          MaterialPage<void>(
            key: ValueKey(module),
            name: '/${module.name}',
            child: Builder(
              builder: (context) => page(context, module, staffRole),
            ),
          ),
      ],
      onDidRemovePage: (removed) {
        final current = _module;
        if (current != null && removed.key == ValueKey(current)) {
          _module = null;
          notifyListeners();
        }
      },
    );
  }
}
