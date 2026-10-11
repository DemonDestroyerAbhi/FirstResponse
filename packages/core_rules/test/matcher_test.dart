import 'package:core_rules/core_rules.dart';
import 'package:test/test.dart';

Rule rule(String id, MatchSpec match, {bool generic = false}) => Rule(
  id: id,
  version: '1.0.0',
  portal: id.split('.').first,
  status: RuleStatus.draft,
  severity: Severity.medium,
  title: const LocalizedText({'en': 't'}),
  explain: const LocalizedText({'en': 'e'}),
  match: match,
  rootCause: 'aadhaar.$id',
  generic: generic,
);

void main() {
  final matcher = RuleMatcher([
    rule(
      'uidai.bio',
      const MatchSpec(
        codes: ['300'],
        patterns: ['biometric data did not match'],
      ),
    ),
    rule('uidai.k100', const MatchSpec(codes: ['K-100'])),
    rule(
      'epfo.name',
      const MatchSpec(regex: [r'name (?:does not|not) match(?:ing)?']),
    ),
  ]);

  test('normalize folds case, punctuation and spacing', () {
    expect(
      normalize('  Error-300:  Biometric DATA!! '),
      'error 300 biometric data',
    );
    expect(normalize('आधार  लिंक नहीं!'), 'आधार लिंक नहीं');
  });

  test('a structured code is certain; the same code in text only asks', () {
    expect(matcher.match('x', code: '300').single.confidence, 1.0);
    expect(
      matcher.match('Error 300 occurred').single.decision,
      Decision.confirm,
    );
  });

  test('codes match whole tokens only', () {
    expect(matcher.match('Paid Rs 3000'), isEmpty);
    expect(matcher.match('Error K-100').single.rule.id, 'uidai.k100');
  });

  test('regex runs on normalized text', () {
    expect(matcher.match('NAME NOT MATCHING!').single.rule.id, 'epfo.name');
  });

  test('a misspelt phrase lands in the confirm band, never answer', () {
    final m = matcher.match('biometrc data didnt match').single;
    expect(m.method, MatchMethod.trigram);
    expect(m.decision, Decision.confirm);
  });

  test('portal filter narrows the rules', () {
    expect(matcher.match('name not matching', portal: 'uidai'), isEmpty);
  });
}
