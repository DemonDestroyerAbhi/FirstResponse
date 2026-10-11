import 'package:core_rules/core_rules.dart';

/// The API's view of a diagnosis: rule text and labels resolved into [lang],
/// plus the audit fields.
Map<String, Object?> diagnosisJson(
  Diagnosis d,
  Rulebook book, {
  String lang = 'en',
  String? reviewId,
}) {
  final rule = d.rule;
  final answered = d.decision == Decision.answer && rule != null;
  return {
    'decision': d.decision.name,
    'input': d.input,
    if (answered) 'rule': ruleJson(rule, book, lang: lang),
    if (answered)
      'sequence': [
        for (final s in d.sequence)
          {
            'record': s.record.id,
            'name': s.record.name.of(lang),
            'kind': s.kind.name,
            'because': s.because,
          },
      ],
    // Only offered when asking; an answer should not show runners-up.
    if (d.decision == Decision.confirm)
      'candidates': [
        for (final m in [?d.match, ...d.alternatives])
          {
            'ruleId': m.rule.id,
            'title': m.rule.title.of(lang),
            'explain': m.rule.explain.of(lang),
          },
      ],
    'reviewId': ?reviewId,
    'audit': d.toAuditJson(),
  };
}

Map<String, Object?> ruleJson(Rule r, Rulebook book, {String lang = 'en'}) {
  Map<String, String> labelled(String id) => {
    'id': id,
    'label': book.label(id, lang),
  };
  return {
    'id': r.id,
    'version': r.version,
    'portal': r.portal,
    'severity': r.severity.name,
    'title': r.title.of(lang),
    'explain': r.explain.of(lang),
    'fix': [
      for (final f in r.fix)
        {
          'actor': labelled(f.actor),
          'action': f.action.of(lang),
          if (f.form case final form?) 'form': labelled(form),
          'bring': [for (final b in f.bring) labelled(b)],
          'channel': ?f.channel,
          'typicalDays': ?f.typicalDays,
        },
    ],
    'sources': [
      for (final s in r.sources)
        {
          'url': s.url,
          'title': ?s.title,
          'verifiedOn': ?s.verifiedOn?.toIso8601String().substring(0, 10),
        },
    ],
  };
}

String isoDate(DateTime d) => d.toIso8601String().substring(0, 10);
