import 'package:flutter/material.dart';

import 'screens/home_shell.dart';
import 'theme.dart';

class AfterFrameApp extends StatelessWidget {
  const AfterFrameApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AfterFrame · 余帧',
      debugShowCheckedModeBanner: false,
      theme: AfterFrameTheme.dark,
      home: const HomeShell(),
    );
  }
}
