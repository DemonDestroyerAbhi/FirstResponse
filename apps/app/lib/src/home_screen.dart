import 'package:core_rules/core_rules.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import 'diagnose_screen.dart';
import 'life_certificate_screen.dart';
import 'widgets.dart';

class HomeScreen extends StatelessWidget {
  final Engine engine;

  const HomeScreen({super.key, required this.engine});

  @override
  Widget build(BuildContext context) {
    void open(Widget screen) => Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => screen));

    return Scaffold(
      appBar: AppBar(title: const Text(appName)),
      body: PageBody(
        children: [
          Text(
            'What do you need help with?',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _Choice(
            icon: Icons.event_available,
            title: 'Life certificate deadline',
            subtitle: 'When to submit for a pensioner, and reminders',
            onTap: () => open(LifeCertificateScreen(engine: engine)),
          ),
          _Choice(
            icon: Icons.help_outline,
            title: 'Explain a rejection or error',
            subtitle: 'Paste the message you got; we tell you what to fix',
            onTap: () => open(DiagnoseScreen(engine: engine)),
          ),
          const SizedBox(height: 24),
          const Disclaimer(),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _Choice({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(icon, size: 32),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    ),
  );
}
