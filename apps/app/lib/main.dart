import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/home_screen.dart';
import 'src/services/api_client.dart';
import 'src/services/rulebook_service.dart';

/// Working name until the brand is decided.
const appName = 'FirstResponse';

/// Set with `--dart-define=API_URL=https://...`. Without it the app runs
/// fully offline on its bundled rules.
const apiUrl = String.fromEnvironment('API_URL');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Rules ship inside the app so diagnosis works with no connection.
  final rules = await RulebookService.load(
    assetJson: await rootBundle.loadString('assets/rulebook.json'),
    cache: PrefsBundleCache(),
    api: apiUrl.isEmpty ? null : ApiClient(Uri.parse(apiUrl)),
  );
  runApp(App(rules: rules));
  // Newer rules, if any, apply from the next diagnosis on.
  unawaited(rules.refresh());
}

class App extends StatelessWidget {
  final RulebookService rules;

  const App({super.key, required this.rules});

  @override
  Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF0F766E),
        brightness: b,
      ),
    );
    return MaterialApp(
      title: appName,
      theme: theme(Brightness.light),
      darkTheme: theme(Brightness.dark),
      home: HomeScreen(rules: rules),
    );
  }
}
