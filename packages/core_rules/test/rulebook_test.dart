import 'package:core_rules/core_rules.dart';
import 'package:test/test.dart';

final records = {
  'records': [
    {'id': 'aadhaar', 'name': 'Aadhaar', 'fixedBy': 'aadhaar_centre'},
    {
      'id': 'bank_kyc',
      'name': 'Bank KYC',
      'fixedBy': 'bank_branch',
      'copiesFrom': ['aadhaar'],
    },
  ],
  'labels': {
    'aadhaar_centre': 'Aadhaar centre',
    'bank_branch': 'Bank',
    'self': 'You',
  },
};

const pack = {
  'id': 'demo',
  'version': '1.0.0',
  'portal': 'demo',
  'name': 'Demo',
  'involves': ['bank_kyc'],
};

Map<String, dynamic> rule(String id, {Map<String, dynamic> extra = const {}}) =>
    {
      'id': 'demo.$id',
      'version': '1.0.0',
      'portal': 'demo',
      'title': 'Title $id',
      'explain': 'Explain $id',
      'match': {
        'patterns': ['$id happened'],
      },
      'rootCause': 'aadhaar.$id',
      'fix': [
        {'actor': 'self', 'action': 'Do it'},
      ],
      'sources': [
        {'url': 'https://example.org'},
      ],
      ...extra,
    };

List<String> problems(
  List<Map<String, dynamic>> rules, {
  Map<String, dynamic> packJson = pack,
}) {
  try {
    Rulebook.fromJson(records, [(packJson, rules)]);
    return [];
  } on RulebookException catch (e) {
    return e.problems;
  }
}

void main() {
  test('a well-formed pack loads', () {
    expect(problems([rule('a'), rule('b')]), isEmpty);
  });

  test('reports every problem at once', () {
    final p = problems([
      rule('a', extra: {'id': 'other.a'}),
      rule('b', extra: {'rootCause': 'nowhere.b', 'version': '1.0'}),
      rule(
        'c',
        extra: {
          'match': {
            'regex': ['(unclosed'],
          },
          'fix': <Object>[],
        },
      ),
      rule('d'),
      rule('d'),
    ]);
    expect(p, hasLength(6));
    expect(
      p.join('\n'),
      allOf([
        contains('id must start with "demo."'),
        contains('not in records.json'),
        contains('version is not semver'),
        contains('bad regex'),
        contains('no fix steps'),
        contains('duplicate rule id'),
      ]),
    );
  });

  test('a verified rule must name its reviewer and re-verify date', () {
    final p = problems([
      rule('a', extra: {'status': 'verified'}),
    ]);
    expect(p.join('\n'), contains('verifiedOn and reviewer'));
    expect(p.join('\n'), contains('reverifyBy'));
  });

  test('every actor and document in a fix step needs a label', () {
    final p = problems([
      rule(
        'a',
        extra: {
          'fix': [
            {
              'actor': 'courier',
              'action': 'Send it',
              'bring': ['form_x'],
            },
          ],
        },
      ),
    ]);
    expect(p, [contains('no label for "courier"'), contains('"form_x"')]);
  });

  test('pack involves must name known records', () {
    expect(
      problems(
        [rule('a')],
        packJson: {
          ...pack,
          'involves': ['ghost'],
        },
      ),
      [contains('involves unknown record "ghost"')],
    );
  });

  test('freshness: unverified, current, then stale', () {
    final draft = Rule.fromJson(rule('a'));
    final verified = Rule.fromJson(
      rule(
        'a',
        extra: {
          'status': 'verified',
          'reverifyBy': '2027-01-01',
          'sources': [
            {
              'url': 'https://example.org',
              'verifiedOn': '2026-10-01',
              'reviewer': 'rk',
            },
          ],
        },
      ),
    );
    final now = DateTime.utc(2026, 11, 1);
    expect(draft.freshnessAt(now), Freshness.unverified);
    expect(verified.freshnessAt(now), Freshness.current);
    expect(verified.freshnessAt(DateTime.utc(2027, 2, 1)), Freshness.stale);
  });

  test('engine records rule and pack versions for audit', () {
    final book = Rulebook.fromJson(records, [
      (pack, [rule('a')]),
    ]);
    final d = Engine(book).diagnose('Oh no, a happened!');
    expect(d.toAuditJson(), containsPair('ruleId', 'demo.a'));
    expect(d.toAuditJson(), containsPair('ruleVersion', '1.0.0'));
    expect(d.toAuditJson(), containsPair('packVersion', '1.0.0'));
    expect(
      [for (final s in d.sequence) s.toString()],
      ['fix:aadhaar', 'resync:bank_kyc <- aadhaar'],
    );
  });

  test('a user-confirmed match is answered and marked in the audit', () {
    final book = Rulebook.fromJson(records, [
      (pack, [rule('alpha')]),
    ]);
    final engine = Engine(book);
    final d = engine.diagnose('alpha happend');
    expect(d.decision, Decision.confirm);
    final c = engine.confirm(d, d.match!);
    expect(c.decision, Decision.answer);
    expect(c.toAuditJson(), containsPair('confirmedByUser', true));
    expect(c.sequence, isNotEmpty);
  });
}
