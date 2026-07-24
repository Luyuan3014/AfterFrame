import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'localization/app_localizations.dart';
import 'screens/home_shell.dart';
import 'theme.dart';

class AfterFrameApp extends StatefulWidget {
  const AfterFrameApp({super.key, this.initialLanguage = AppLanguage.chinese});

  final AppLanguage initialLanguage;

  @override
  State<AfterFrameApp> createState() => _AfterFrameAppState();
}

class _AfterFrameAppState extends State<AfterFrameApp> {
  late final AppLanguageController _language = AppLanguageController(
    widget.initialLanguage,
  );

  @override
  void dispose() {
    _language.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppLanguageScope(
    controller: _language,
    child: AnimatedBuilder(
      animation: _language,
      builder: (_, _) => MaterialApp(
        title: 'AfterFrame',
        debugShowCheckedModeBanner: false,
        theme: AfterFrameTheme.dark,
        locale: Locale(_language.language.code),
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('zh'), Locale('en')],
        home: const HomeShell(),
      ),
    ),
  );
}
