import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'features/watchdog/presentation/watchdog_screen.dart';

class MangoWatchdogApp extends StatelessWidget {
  const MangoWatchdogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'mango-watchdog',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: const WatchdogScreen(),
      );
}
