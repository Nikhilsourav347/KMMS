import 'package:flutter/material.dart';

import 'app/startup.dart';
import 'core/supabase_backend.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final launchUri = Uri.base;
  runApp(MillApp(openBackend: () => openSupabaseBackend(launchUri: launchUri)));
}
