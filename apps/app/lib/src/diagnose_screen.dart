import 'package:core_rules/core_rules.dart';
import 'package:flutter/material.dart';

import 'widgets.dart';

/// Paste an error or rejection message; get the cause and the fix.
class DiagnoseScreen extends StatefulWidget {
  final Engine engine;

  /// Limits matching to one portal's rules, when the user came from a
  /// specific flow such as the life certificate.
  final String? portal;

  const DiagnoseScreen({super.key, required this.engine, this.portal});

  @override
  State<DiagnoseScreen> createState() => _DiagnoseScreenState();
}

class _DiagnoseScreenState extends State<DiagnoseScreen> {
  final _input = TextEditingController();
  Diagnosis? _result;

  /// Index into the candidates being offered in a confirming question.
  int _asking = 0;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _check() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _result = widget.engine.diagnose(text, portal: widget.portal);
      _asking = 0;
    });
  }

  List<Match> get _candidates => [?_result?.match, ...?_result?.alternatives];

  void _answer(bool yes) => setState(() {
    if (yes) {
      _result = widget.engine.confirm(_result!, _candidates[_asking]);
    } else {
      _asking++;
    }
  });

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Explain a message')),
      body: PageBody(
        children: [
          TextField(
            controller: _input,
            minLines: 3,
            maxLines: 6,
            decoration: const InputDecoration(
              labelText: 'Paste or type the exact message',
              hintText: 'e.g. Biometric data did not match',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _check,
            icon: const Icon(Icons.search),
            label: const Text('Check'),
          ),
          const SizedBox(height: 24),
          if (result != null) ..._resultView(result),
          const SizedBox(height: 24),
          const Disclaimer(),
        ],
      ),
    );
  }

  List<Widget> _resultView(Diagnosis d) {
    if (d.decision == Decision.answer) {
      return [DiagnosisView(diagnosis: d, rulebook: widget.engine.rulebook)];
    }
    if (d.decision == Decision.confirm && _asking < _candidates.length) {
      final candidate = _candidates[_asking].rule;
      return [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Is this your problem?',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  candidate.title.of('en'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(candidate.explain.of('en')),
                const SizedBox(height: 16),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => _answer(true),
                      child: const Text('Yes, that is it'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton(
                      onPressed: () => _answer(false),
                      child: const Text('No'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ];
    }
    // No match, or the user turned down every candidate.
    // TODO: send to the review queue once the API exists.
    return const [
      Notice(
        icon: Icons.manage_search,
        text:
            "We don't recognise this message yet. Check that it is copied "
            'exactly, or ask at the office that showed it.',
      ),
    ];
  }
}

class DiagnosisView extends StatelessWidget {
  final Diagnosis diagnosis;
  final Rulebook rulebook;

  const DiagnosisView({
    super.key,
    required this.diagnosis,
    required this.rulebook,
  });

  @override
  Widget build(BuildContext context) {
    final rule = diagnosis.rule!;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(rule.title.of('en'), style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(rule.explain.of('en'), style: text.bodyLarge),
        if (diagnosis.freshness != Freshness.current) ...[
          const SizedBox(height: 16),
          Notice(
            icon: Icons.warning_amber,
            text: diagnosis.freshness == Freshness.stale
                ? 'The official rules may have changed since we last checked '
                      'this answer. Confirm with the office.'
                : 'This answer has not yet been checked against the '
                      'official source. Confirm with the office.',
          ),
        ],
        if (diagnosis.sequence.length > 1) ...[
          const SizedBox(height: 24),
          Text('Order to fix in', style: text.titleMedium),
          const SizedBox(height: 8),
          for (final (i, s) in diagnosis.sequence.indexed)
            ListTile(
              dense: true,
              leading: CircleAvatar(radius: 14, child: Text('${i + 1}')),
              title: Text(
                s.kind == StepKind.fix
                    ? 'Correct ${s.record.name.of('en')}'
                    : 'Update ${s.record.name.of('en')} to match',
              ),
            ),
        ],
        const SizedBox(height: 24),
        Text('What to do', style: text.titleMedium),
        const SizedBox(height: 8),
        for (final (i, step) in rule.fix.indexed)
          Card(
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(rulebook.label(step.actor)),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(step.action.of('en')),
                  if (step.form case final form?)
                    Text('Form: ${rulebook.label(form)}'),
                  if (step.bring.isNotEmpty)
                    Text('Bring: ${step.bring.map(rulebook.label).join(', ')}'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        Text('Sources', style: text.titleSmall),
        for (final s in rule.sources)
          SelectableText(s.title == null ? s.url : '${s.title}: ${s.url}'),
        const SizedBox(height: 8),
        Text(
          'Rule ${rule.id} v${rule.version}',
          style: text.bodySmall?.copyWith(color: Theme.of(context).hintColor),
        ),
      ],
    );
  }
}
