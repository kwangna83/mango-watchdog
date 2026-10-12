import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app.dart';
import 'core/config/app_config.dart';
import 'core/config/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final config = AppConfig.fromEnvironment();
    await Supabase.initialize(url: config.supabaseUrl, publishableKey: config.publishableKey);
    await FirebaseBootstrap.initialize(config);
    runApp(const MangoWatchdogApp());
  } on AppConfigException catch (error) {
    runApp(MaterialApp(home: Scaffold(body: Center(child: Text(error.message)))));
  }
}
