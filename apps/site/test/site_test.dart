import 'package:core_rules/core_rules.dart';
import 'package:core_rules/io.dart';
import 'package:site/site.dart';
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
    'bank_branch': 'Bank branch',
    'self': 'You',
  },
};

Map<String, dynamic> rule(
  String id, {
  bool verified = false,
  String title = 'Title',
}) => {
  'id': 'demo_portal.$id',
  'version': '1.0.0',
  'portal': 'demo',
  'status': verified ? 'verified' : 'draft',
  'title': title,
  'explain': 'Explain $id',
  'match': {
    'patterns': ['$id happened'],
    'codes': ['42'],
  },
  'rootCause': 'aadhaar.$id',
  'fix': [
    {'actor': 'aadhaar_centre', 'action': 'Fix it'},
  ],
  'sources': [
    {
      'url': 'https://example.gov/x',
      'title': 'Example',
      if (verified) 'verifiedOn': '2026-10-01',
      if (verified) 'reviewer': 'rk',
    },
  ],
  if (verified) 'reverifyBy': '2027-04-01',
};

final book = Rulebook.fromJson(records, [
  (
    {
      'id': 'demo_portal',
      'version': '1.0.0',
      'portal': 'demo',
      'name': 'Demo portal',
      'involves': ['aadhaar', 'bank_kyc'],
    },
    [
      rule('live_one', verified: true, title: 'Name <script>x</script> & co'),
      rule('draft_one'),
    ],
  ),
]);

Map<String, String> site({bool drafts = false, String? api}) => buildSite(
  book,
  SiteOptions(
    baseUrl: Uri.parse('https://site.example'),
    apiUrl: api == null ? null : Uri.parse(api),
    drafts: drafts,
    builtAt: DateTime.utc(2026, 11, 1),
  ),
);

/// Every `href="/..."` must point at a generated file.
List<String> brokenLinks(Map<String, String> files) => [
  for (final MapEntry(key: path, value: html) in files.entries)
    if (path.endsWith('.html'))
      for (final m in RegExp(r'(?:href|src)="(/[^"]*)"').allMatches(html))
        if (!files.containsKey(
          m[1]!.endsWith('/')
              ? '${m[1]!.substring(1)}index.html'
              : m[1]!.substring(1),
        ))
          '$path -> ${m[1]}',
];

void main() {
  test('production publishes verified rules only', () {
    final files = site();
    expect(files.keys, contains('demo-portal/live-one/index.html'));
    expect(files.keys, isNot(contains('demo-portal/draft-one/index.html')));
    expect(
      files['sitemap.xml'],
      contains('https://site.example/demo-portal/live-one/'),
    );
    expect(files['sitemap.xml'], isNot(contains('draft-one')));
    expect(
      files['robots.txt'],
      contains('Sitemap: https://site.example/sitemap.xml'),
    );
    expect(files['site.js'], isNot(contains('draft_one')));
    expect(brokenLinks(files), isEmpty);
  });

  test(
    'a verified page is indexable, canonical and says when it was checked',
    () {
      final html = site()['demo-portal/live-one/index.html']!;
      expect(html, isNot(contains('noindex')));
      expect(
        html,
        contains(
          '<link rel="canonical" href="https://site.example/demo-portal/live-one/">',
        ),
      );
      expect(
        html,
        contains('<title>Live_one happened (error 42): what it means'),
      );
      expect(
        html,
        contains('Checked against the official source on 1 October 2026'),
      );
      expect(html, contains('<li>Correct Aadhaar</li>'));
      expect(html, contains('<li>Update Bank KYC to match</li>'));
      expect(html, contains('Not affiliated with any government body'));
    },
  );

  test('rule text is escaped', () {
    final files = site();
    for (final html in files.values) {
      expect(html, isNot(contains('<script>x</script>')));
    }
    expect(
      files['demo-portal/live-one/index.html'],
      contains('Name &lt;script&gt;x&lt;/script&gt; &amp; co'),
    );
  });

  test('a preview includes drafts but hides everything from search', () {
    final files = site(drafts: true);
    expect(files.keys, contains('demo-portal/draft-one/index.html'));
    expect(files.keys, isNot(contains('sitemap.xml')));
    expect(files['robots.txt'], contains('Disallow: /'));
    for (final MapEntry(key: path, value: html) in files.entries) {
      if (path.endsWith('.html')) {
        expect(html, contains('noindex'), reason: path);
      }
    }
    expect(
      files['demo-portal/draft-one/index.html'],
      allOf(
        contains('Preview: this guide has not been verified'),
        contains('has not yet been checked'),
      ),
    );
    expect(brokenLinks(files), isEmpty);
  });

  test('the check box appears only with an API URL', () {
    expect(site()['index.html'], isNot(contains('diagnose-form')));
    final files = site(api: 'https://api.example');
    expect(files['index.html'], contains('data-api="https://api.example"'));
    expect(
      files['demo-portal/live-one/index.html'],
      contains('<form class="diagnose-form" data-portal="demo">'),
    );
    expect(
      files['site.js'],
      startsWith(
        'const RULE_PAGES = {"demo_portal.live_one":"/demo-portal/live-one/"};',
      ),
    );
  });

  test('builds the real rulebook as a preview with no broken links', () {
    final files = buildSite(
      loadRulebook(findRulesDir()),
      SiteOptions(
        baseUrl: Uri.parse('https://site.example'),
        apiUrl: Uri.parse('https://api.example'),
        drafts: true,
        builtAt: DateTime.utc(2026, 11, 1),
      ),
    );
    expect(
      files.keys.where((p) => p.startsWith('jeevan-pramaan/')),
      hasLength(8), // pack page + 7 rules
    );
    expect(brokenLinks(files), isEmpty);
  });
}
