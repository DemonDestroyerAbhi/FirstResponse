import 'package:core_rules/core_rules.dart';
import 'package:flutter/material.dart';

import 'diagnose_screen.dart';
import 'widgets.dart';

/// Module #9: when a pensioner must submit, and when to remind them.
class LifeCertificateScreen extends StatefulWidget {
  final Engine engine;

  /// Fixed in tests; the real clock otherwise.
  final DateTime Function() today;

  const LifeCertificateScreen({
    super.key,
    required this.engine,
    this.today = DateTime.now,
  });

  @override
  State<LifeCertificateScreen> createState() => _LifeCertificateScreenState();
}

class _LifeCertificateScreenState extends State<LifeCertificateScreen> {
  DateTime? _dob;

  Future<void> _pickDob() async {
    final today = widget.today();
    final picked = await showDatePicker(
      context: context,
      helpText: "Pensioner's date of birth",
      initialDatePickerMode: DatePickerMode.year,
      initialDate: _dob ?? DateTime(today.year - 70),
      firstDate: DateTime(1900),
      lastDate: today,
    );
    if (picked != null) setState(() => _dob = picked);
  }

  @override
  Widget build(BuildContext context) {
    final dob = _dob;
    return Scaffold(
      appBar: AppBar(title: const Text('Life certificate')),
      body: PageBody(
        children: [
          const Text(
            'Central government pensioners must submit a life certificate '
            'every November to keep the pension coming. Pensioners aged 80 '
            'or more can submit from 1 October.',
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _pickDob,
            icon: const Icon(Icons.cake_outlined),
            label: Text(
              dob == null
                  ? "Enter pensioner's date of birth"
                  : 'Born ${formatDate(dob)} (change)',
            ),
          ),
          if (dob != null) ...[
            const SizedBox(height: 24),
            _Season(dob: dob, today: widget.today()),
          ],
          const SizedBox(height: 24),
          TextButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => DiagnoseScreen(
                  engine: widget.engine,
                  portal: 'jeevan_pramaan',
                ),
              ),
            ),
            icon: const Icon(Icons.help_outline),
            label: const Text('Certificate rejected? Find out why'),
          ),
          const SizedBox(height: 24),
          const Disclaimer(),
        ],
      ),
    );
  }
}

class _Season extends StatelessWidget {
  final DateTime dob;
  final DateTime today;

  const _Season({required this.dob, required this.today});

  @override
  Widget build(BuildContext context) {
    final window = currentWindow(dob, today);
    final left = window.daysLeft(today);
    final open = window.contains(today);
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              open
                  ? (left == 0
                        ? 'Last day to submit is today'
                        : '$left days left to submit')
                  : 'Submission opens ${formatDate(window.opens)}',
              style: text.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              'Window: ${formatDate(window.opens)} to '
              '${formatDate(window.closes)}',
            ),
            const SizedBox(height: 16),
            Text('Reminder dates', style: text.titleMedium),
            for (final r in remindersFor(window, today))
              ListTile(
                dense: true,
                leading: const Icon(Icons.notifications_outlined),
                title: Text(formatDate(r.date)),
                subtitle: Text(switch (r.kind) {
                  ReminderKind.windowOpens => 'Submission opens',
                  ReminderKind.beforeDeadline => '${r.daysLeft} days left',
                  ReminderKind.deadlineDay => 'Last day',
                }),
              ),
          ],
        ),
      ),
    );
  }
}
