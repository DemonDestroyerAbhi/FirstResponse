import 'dart:convert';

import 'package:core_rules/core_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/home_screen.dart';

/// Working name until the brand is decided.
const appName = 'FirstResponse';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Rules ship inside the app so diagnosis works with no connection.
  final bundle = jsonDecode(
    await rootBundle.loadString('assets/rulebook.json'),
  );
  final engine = Engine(Rulebook.fromBundle(bundle as Map<String, dynamic>));
  runApp(App(engine: engine));
}

class App extends StatelessWidget {
  final Engine engine;

  const App({super.key, required this.engine});

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
      home: HomeScreen(engine: engine),
    );
  }
}
