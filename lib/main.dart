import 'package:flutter/material.dart';
import 'package:sembast_web/sembast_web.dart';

import 'data/app_state.dart';
import 'l10n.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = await AppState.open(databaseFactoryWeb);
  runApp(WorshipStudioApp(state: state));
}

class WorshipStudioApp extends StatelessWidget {
  const WorshipStudioApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final s = state.settings;
        appLocale = s.locale;
        ThemeData theme(Brightness b) => ThemeData(
              colorScheme: ColorScheme.fromSeed(seedColor: Color(s.accent), brightness: b),
              visualDensity: VisualDensity.standard,
            );
        return MaterialApp(
          title: 'WorshipStudio',
          debugShowCheckedModeBanner: false,
          theme: theme(Brightness.light),
          darkTheme: theme(Brightness.dark),
          themeMode: switch (s.themeMode) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          home: HomePage(state: state),
        );
      },
    );
  }
}
