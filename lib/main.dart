import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/localization/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final language = await AppLanguageController.load();
  runApp(AfterFrameApp(initialLanguage: language));
}
