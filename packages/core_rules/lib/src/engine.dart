import 'matcher.dart';
import 'model.dart';
import 'rulebook.dart';
import 'sequencer.dart';

/// One answer, with enough provenance to audit it later.
class Diagnosis {
  final String input;
  final Decision decision;

  /// Best match, or null when nothing matched at all.
  final Match? match;

  /// Other candidates, for the confirming question or the reviewer.
  final List<Match> alternatives;

  /// Fix and re-sync steps across records, for [match]'s root cause.
  final List<SequenceStep> sequence;
  final Freshness? freshness;
  final String? packVersion;

  /// True when the user picked [match] in answer to a confirming question.
  final bool confirmedByUser;

  const Diagnosis({
    required this.input,
    required this.decision,
    this.match,
    this.alternatives = const [],
    this.sequence = const [],
    this.freshness,
    this.packVersion,
    this.confirmedByUser = false,
  });

  Rule? get rule => match?.rule;

  /// Stored with every case so any advice can be traced to a rule version.
  Map<String, Object?> toAuditJson() => {
    'decision': decision.name,
    'ruleId': rule?.id,
    'ruleVersion': rule?.version,
    'packVersion': packVersion,
    'confidence': match?.confidence,
    'method': match?.method.name,
    'evidence': match?.evidence,
    'freshness': freshness?.name,
    'confirmedByUser': confirmedByUser,
    'alternatives': [for (final a in alternatives) a.rule.id],
  };
}

class Engine {
  final Rulebook rulebook;
  final RuleMatcher _matcher;

  Engine(this.rulebook) : _matcher = RuleMatcher(rulebook.rules.toList());

  Diagnosis diagnose(
    String text, {
    String? portal,
    String? code,
    DateTime? now,
  }) {
    final matches = _matcher.match(text, portal: portal, code: code);
    if (matches.isEmpty) {
      return Diagnosis(input: text, decision: Decision.review);
    }
    // A specific rule beats a catch-all one that matched the same input,
    // unless the specific match is in a weaker band than the catch-all.
    final top = matches.first;
    final specific = matches.where((m) => !m.rule.generic).firstOrNull;
    final best =
        specific != null && specific.decision.index <= top.decision.index
        ? specific
        : top;
    final rest = [
      for (final m in matches)
        if (m != best &&
            (m.decision != Decision.review || best.decision == Decision.review))
          m,
    ].take(3).toList();

    // Two strong specific rules pointing at different root causes means the
    // input is ambiguous; ask instead of guessing.
    var decision = best.decision;
    final rival = rest.where((m) => !m.rule.generic).firstOrNull;
    if (decision == Decision.answer &&
        rival != null &&
        rival.decision == Decision.answer &&
        rival.rule.rootCause != best.rule.rootCause) {
      decision = Decision.confirm;
    }

    return _build(text, best, decision, rest, now: now);
  }

  /// The user confirmed [match] (from [d] or its alternatives) is their
  /// problem, so answer with it.
  Diagnosis confirm(Diagnosis d, Match match, {DateTime? now}) => _build(
    d.input,
    match,
    Decision.answer,
    const [],
    now: now,
    confirmedByUser: true,
  );

  Diagnosis _build(
    String text,
    Match best,
    Decision decision,
    List<Match> rest, {
    DateTime? now,
    bool confirmedByUser = false,
  }) {
    final pack = rulebook.packOf(best.rule);
    return Diagnosis(
      input: text,
      decision: decision,
      match: best,
      alternatives: rest,
      sequence: switch (decision) {
        Decision.review => const [],
        _ when !best.rule.propagates => [
          SequenceStep(rulebook.records[best.rule.record]!, StepKind.fix),
        ],
        _ => rulebook.sequencer.plan({
          best.rule.record,
        }, involved: pack.involves.isEmpty ? null : pack.involves),
      },
      freshness: best.rule.freshnessAt(now ?? DateTime.now()),
      packVersion: pack.version,
      confirmedByUser: confirmedByUser,
    );
  }
}
