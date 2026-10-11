import 'model.dart';

/// How a match was found, strongest first.
enum MatchMethod { code, phrase, regex, trigram }

/// What the client should do with a match, per the plan's thresholds.
enum Decision {
  /// Confidence 0.85 or higher: show the diagnosis.
  answer,

  /// 0.60 to 0.85: ask the user one confirming question first.
  confirm,

  /// Below 0.60 or no match: send to the human review queue.
  review,
}

class Match {
  final Rule rule;
  final double confidence;
  final MatchMethod method;

  /// The code, phrase or pattern that matched, for audit logs.
  final String evidence;

  const Match(this.rule, this.confidence, this.method, this.evidence);

  Decision get decision => decisionFor(confidence);

  @override
  String toString() =>
      'Match(${rule.id}, ${confidence.toStringAsFixed(2)}, ${method.name})';
}

const answerThreshold = 0.85;
const confirmThreshold = 0.60;

Decision decisionFor(double confidence) => confidence >= answerThreshold
    ? Decision.answer
    : confidence >= confirmThreshold
    ? Decision.confirm
    : Decision.review;

/// Lowercases, folds punctuation to spaces and collapses whitespace.
///
/// Devanagari letters and combining marks are kept, so Hindi and Marathi
/// remarks normalize the same way as English ones.
String normalize(String input) => input
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true), ' ')
    .trim();

Set<String> trigrams(String normalized) {
  final s = ' $normalized ';
  return {for (var i = 0; i + 3 <= s.length; i++) s.substring(i, i + 3)};
}

/// Matches free text against rules: exact code, then phrase and regex, then
/// trigram similarity. AI classification is not done here; callers send
/// [Decision.review] results to the AI fallback or the review queue.
class RuleMatcher {
  final List<Rule> rules;

  /// Phrases shorter than this are too ambiguous for fuzzy matching.
  static const _minFuzzyLength = 10;

  /// Below this, a trigram score is noise rather than a candidate.
  static const _minTrigramScore = 0.45;

  final Map<String, List<RegExp>> _regex;
  final Map<String, List<(String, Set<String>)>> _phrases;

  RuleMatcher(this.rules)
    : _regex = {
        for (final r in rules)
          r.id: [for (final p in r.match.regex) RegExp(p, unicode: true)],
      },
      _phrases = {
        for (final r in rules)
          r.id: [
            for (final p in r.match.patterns)
              (normalize(p), trigrams(normalize(p))),
          ],
      };

  /// Returns candidates sorted by confidence, best first.
  ///
  /// [portal] narrows matching to one portal's rules. [code] is a structured
  /// code when the input has one (e.g. from a parsed API response).
  List<Match> match(String text, {String? portal, String? code}) {
    final active = [
      for (final r in rules)
        if (r.status != RuleStatus.retired &&
            (portal == null || r.portal == portal))
          r,
    ];
    final norm = normalize(text);
    final tokens = norm.split(' ').toSet();
    final inputGrams = trigrams(norm);
    final best = <String, Match>{};

    void offer(Match m) {
      final prev = best[m.rule.id];
      if (prev == null || m.confidence > prev.confidence) best[m.rule.id] = m;
    }

    for (final rule in active) {
      for (final c in rule.match.codes) {
        if (code == c) {
          offer(Match(rule, 1.0, MatchMethod.code, c));
        } else if (_codeInText(c, tokens, norm)) {
          // A bare number in free text may be an amount or a date, so it
          // only earns a confirming question.
          offer(Match(rule, 0.75, MatchMethod.code, c));
        }
      }
      for (final (phrase, grams) in _phrases[rule.id]!) {
        if (phrase.isEmpty) continue;
        if (' $norm '.contains(' $phrase ')) {
          offer(Match(rule, 0.95, MatchMethod.phrase, phrase));
        } else if (phrase.length >= _minFuzzyLength) {
          final score = _coverage(grams, inputGrams);
          if (score >= _minTrigramScore) {
            // Scale so a near-complete fuzzy hit lands in the confirm band
            // and never reaches a direct answer on its own.
            offer(Match(rule, score * 0.84, MatchMethod.trigram, phrase));
          }
        }
      }
      for (final re in _regex[rule.id]!) {
        if (re.hasMatch(norm)) {
          offer(Match(rule, 0.92, MatchMethod.regex, re.pattern));
        }
      }
    }

    return best.values.toList()
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
  }

  /// Codes like `300` must appear as whole tokens, not inside `3000`.
  /// Multi-word codes (`K-100` normalizes to `k 100`) are matched as phrases.
  static bool _codeInText(String code, Set<String> tokens, String norm) {
    final c = normalize(code);
    return c.contains(' ') ? ' $norm '.contains(' $c ') : tokens.contains(c);
  }

  /// Share of the phrase's trigrams found in the input. Using coverage rather
  /// than Jaccard lets a short phrase match inside a long remark.
  static double _coverage(Set<String> phrase, Set<String> input) =>
      phrase.isEmpty ? 0 : phrase.intersection(input).length / phrase.length;
}
