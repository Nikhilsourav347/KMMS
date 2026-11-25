import 'package:web/web.dart' as web;

void clearRecoveryUrl() {
  final uri = Uri.base;
  web.window.history.replaceState(null, '', uri.path);
}
