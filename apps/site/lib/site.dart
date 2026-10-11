/// Generates the public static site from the rulebook: one page per rule,
/// so each rule people search for has a page that answers it.
///
/// Production builds publish verified rules only. A preview build
/// (`drafts: true`) adds drafts, marks every page `noindex`, and blocks
/// crawlers in robots.txt.
library;

import 'dart:convert';

import 'package:core_rules/core_rules.dart';

import 'src/assets.dart';

class SiteOptions {
  /// Where the site is served, for canonical links and the sitemap.
  final Uri baseUrl;

  /// API for the "check your message" box; the box is left out when null.
  final Uri? apiUrl;

  /// Include draft rules in a preview build.
  final bool drafts;

  final String siteName;

  /// The build date, for freshness notices.
  final DateTime builtAt;

  SiteOptions({
    required this.baseUrl,
    required this.builtAt,
    this.apiUrl,
    this.drafts = false,
    this.siteName = 'FirstResponse',
  });
}

/// Every file of the site, keyed by path (`jeevan-pramaan/ppo-mismatch/index.html`).
Map<String, String> buildSite(Rulebook book, SiteOptions o) =>
    _Site(book, o).build();

/// URL path of a rule's page. Changing a rule id changes its URL and loses
/// its search ranking, so ids should stay stable once published.
String rulePath(Rule rule) {
  // Rule ids are `<pack id>.<name>`, so the page sits under its pack's page.
  final dot = rule.id.indexOf('.');
  return '/${_slug(rule.id.substring(0, dot))}/'
      '${_slug(rule.id.substring(dot + 1))}/';
}

String packPath(PackInfo pack) => '/${_slug(pack.id)}/';

String _slug(String id) => id.replaceAll('_', '-');

/// Escapes for both text and quoted attributes, leaving `/` readable.
const _esc = HtmlEscape(
  HtmlEscapeMode(escapeLtGt: true, escapeQuot: true, escapeApos: true),
);
String _h(String s) => _esc.convert(s);

class _Site {
  final Rulebook book;
  final SiteOptions o;
  final Engine engine;

  _Site(this.book, this.o) : engine = Engine(book);

  bool _publish(Rule r) =>
      r.status == RuleStatus.verified ||
      (o.drafts && r.status == RuleStatus.draft);

  late final packs = [
    for (final p in book.packs)
      if (p.rules.any(_publish)) (p.info, p.rules.where(_publish).toList()),
  ];

  Map<String, String> build() {
    final files = <String, String>{
      'index.html': _index(),
      '404.html': _page(
        title: 'Page not found',
        description: 'This page does not exist.',
        path: null,
        body:
            '<h1>Page not found</h1>\n'
            '<p><a href="/">Go to the home page</a> to find your error.</p>',
      ),
      'style.css': styleCss,
      'site.js': _siteJs(),
      'robots.txt': o.drafts
          ? 'User-agent: *\nDisallow: /\n'
          : 'User-agent: *\nAllow: /\n\n'
                'Sitemap: ${o.baseUrl.resolve('/sitemap.xml')}\n',
    };
    final pages = <String>['/'];
    for (final (pack, rules) in packs) {
      files['${packPath(pack).substring(1)}index.html'] = _packPage(
        pack,
        rules,
      );
      pages.add(packPath(pack));
      for (final r in rules) {
        files['${rulePath(r).substring(1)}index.html'] = _rulePage(pack, r);
        pages.add(rulePath(r));
      }
    }
    if (!o.drafts) files['sitemap.xml'] = _sitemap(pages);
    return files;
  }

  String _index() {
    final b = StringBuffer()
      ..writeln('<h1>Why was I rejected, and what do I fix?</h1>')
      ..writeln(
        '<p class="lead">Find the exact error or rejection message you got. '
        'Each page explains what it means, who fixes it, what to bring, and '
        'in what order.</p>',
      )
      ..writeln(_diagnoseBox(null));
    if (packs.isEmpty) {
      b.writeln('<p>No guides are published yet.</p>');
    } else {
      b
        ..writeln('<label class="filter">Search the guides')
        ..writeln(
          '<input type="search" id="filter" '
          'placeholder="e.g. biometric, PPO, name mismatch"></label>',
        );
      for (final (pack, rules) in packs) {
        b
          ..writeln('<section class="pack">')
          ..writeln(
            '<h2><a href="${packPath(pack)}">${_h(pack.name.of('en'))}</a></h2>',
          )
          ..writeln(_ruleList(rules))
          ..writeln('</section>');
      }
    }
    return _page(
      title: '${o.siteName}: government rejections and errors explained',
      description:
          'Plain explanations of government rejection and error messages, '
          'with the steps to fix them in the right order.',
      path: '/',
      body: b.toString(),
    );
  }

  String _packPage(PackInfo pack, List<Rule> rules) => _page(
    title: '${pack.name.of('en')} errors and rejections explained',
    description:
        'What each ${pack.name.of('en')} error means and how to fix it.',
    path: packPath(pack),
    body:
        '${_crumbs([])}\n<h1>${_h(pack.name.of('en'))}</h1>\n'
        '<p class="lead">Pick the message you got.</p>\n'
        '${_ruleList(rules)}\n${_diagnoseBox(pack.portal)}',
  );

  String _ruleList(List<Rule> rules) => [
    '<ul class="rules">',
    for (final r in rules)
      '<li data-search="${_h(_searchText(r))}"><a href="${rulePath(r)}">'
          '${_h(r.title.of('en'))}</a>'
          '${r.match.patterns.isEmpty ? '' : '<br><small>“${_h(_sentence(r.match.patterns.first))}”</small>'}'
          '</li>',
    '</ul>',
  ].join('\n');

  String _rulePage(PackInfo pack, Rule r) {
    final b = StringBuffer()
      ..writeln(_crumbs([(pack.name.of('en'), packPath(pack))]));
    if (r.status != RuleStatus.verified) {
      b.writeln(
        '<p class="banner">Preview: this guide has not been verified yet and '
        'is hidden from search engines.</p>',
      );
    }
    b
      ..writeln('<h1>${_h(r.title.of('en'))}</h1>')
      ..writeln('<p class="lead">${_h(r.explain.of('en'))}</p>');

    final seen = [
      for (final p in r.match.patterns) '<li>“${_h(_sentence(p))}”</li>',
      for (final c in r.match.codes)
        '<li>Error code <code>${_h(c)}</code></li>',
    ];
    if (seen.isNotEmpty) {
      b
        ..writeln('<h2>Messages this covers</h2>')
        ..writeln('<ul class="quotes">${seen.join()}</ul>');
    }

    b.writeln(_freshness(r));

    final sequence = engine.sequenceFor(r);
    if (sequence.length > 1) {
      b
        ..writeln('<h2>Order to fix in</h2>')
        ..writeln('<ol>');
      for (final s in sequence) {
        b.writeln(
          '<li>${s.kind == StepKind.fix ? 'Correct' : 'Update'} '
          '${_h(s.record.name.of('en'))}'
          '${s.kind == StepKind.resync ? ' to match' : ''}</li>',
        );
      }
      b.writeln('</ol>');
    }

    b
      ..writeln('<h2>What to do</h2>')
      ..writeln('<ol class="steps">');
    for (final f in r.fix) {
      b.write(
        '<li><strong>${_h(book.label(f.actor))}</strong>'
        '<p>${_h(f.action.of('en'))}</p>',
      );
      if (f.form case final form?) {
        b.write('<p>Form: ${_h(book.label(form))}</p>');
      }
      if (f.bring.isNotEmpty) {
        b.write('<p>Bring: ${_h(f.bring.map(book.label).join(', '))}</p>');
      }
      if (f.typicalDays case final days?) {
        b.write('<p>Usually takes about $days days.</p>');
      }
      b.writeln('</li>');
    }
    b
      ..writeln('</ol>')
      ..writeln(_diagnoseBox(r.portal, heading: 'Got a different message?'))
      ..writeln('<h2>Sources</h2>')
      ..writeln('<ul>');
    for (final s in r.sources) {
      final checked = s.verifiedOn == null
          ? 'not yet checked'
          : 'checked ${_day(s.verifiedOn!)}';
      b.writeln(
        '<li><a href="${_h(s.url)}">${_h(s.title ?? s.url)}</a> '
        '<small>($checked)</small></li>',
      );
    }
    b
      ..writeln('</ul>')
      ..writeln('<p class="meta">Guide ${_h(r.id)} v${_h(r.version)}</p>');

    final quote = r.match.patterns.isEmpty
        ? r.title.of('en')
        : _sentence(r.match.patterns.first);
    final codes = r.match.codes.isEmpty
        ? ''
        : ' (error ${r.match.codes.join(', ')})';
    return _page(
      title: '$quote$codes: what it means and how to fix it',
      description: _clip(r.explain.of('en'), 155),
      path: rulePath(r),
      body: b.toString(),
      index: r.status == RuleStatus.verified,
    );
  }

  String _freshness(Rule r) => switch (r.freshnessAt(o.builtAt)) {
    Freshness.current =>
      '<p class="checked">Checked against the official source on '
          '${_day(r.sources.map((s) => s.verifiedOn).nonNulls.reduce((a, b) => a.isAfter(b) ? a : b))}.</p>',
    Freshness.stale =>
      '<p class="notice">The official rules may have changed since we last '
          'checked this guide. Confirm with the office before acting.</p>',
    Freshness.unverified =>
      '<p class="notice">This guide has not yet been checked against the '
          'official source. Confirm with the office before acting.</p>',
  };

  String _diagnoseBox(String? portal, {String heading = 'Check your message'}) {
    if (o.apiUrl == null) return '';
    return '<section class="diagnose">\n<h2>${_h(heading)}</h2>\n'
        '<form class="diagnose-form"${portal == null ? '' : ' data-portal="${_h(portal)}"'}>\n'
        '<label>Paste the exact message you got\n'
        '<textarea name="text" rows="3" maxlength="2000" required></textarea>'
        '</label>\n<button type="submit">Check</button>\n</form>\n'
        '<div class="result" aria-live="polite"></div>\n'
        '<p><small>Your message is sent to our server to match it. '
        'Aadhaar, PAN and account numbers are masked before anything is '
        'kept.</small></p>\n</section>';
  }

  String _crumbs(List<(String, String)> trail) => [
    '<nav class="crumbs" aria-label="Breadcrumb"><a href="/">Home</a>',
    for (final (name, href) in trail) ' › <a href="$href">${_h(name)}</a>',
    '</nav>',
  ].join();

  String _page({
    required String title,
    required String description,
    required String? path,
    required String body,
    bool index = true,
  }) {
    final indexable = index && !o.drafts;
    return '''
<!doctype html>
<html lang="en"${o.apiUrl == null ? '' : ' data-api="${_h(o.apiUrl.toString())}"'}>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${_h(title)} | ${_h(o.siteName)}</title>
<meta name="description" content="${_h(description)}">
${indexable ? '' : '<meta name="robots" content="noindex">\n'}${path == null ? '' : '<link rel="canonical" href="${_h(o.baseUrl.resolve(path).toString())}">\n'}<meta property="og:title" content="${_h(title)}">
<meta property="og:description" content="${_h(description)}">
<link rel="stylesheet" href="/style.css">
<script src="/site.js" defer></script>
</head>
<body>
<header><a class="brand" href="/">${_h(o.siteName)}</a></header>
<main>
$body
</main>
<footer>
<p>Not affiliated with any government body. Always verify with the office before acting.</p>
</footer>
</body>
</html>
''';
  }

  String _sitemap(List<String> paths) => [
    '<?xml version="1.0" encoding="UTF-8"?>',
    '<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">',
    for (final p in paths)
      '<url><loc>${_h(o.baseUrl.resolve(p).toString())}</loc></url>',
    '</urlset>',
    '',
  ].join('\n');

  /// site.js, with the published rule pages so API answers can link to them.
  String _siteJs() {
    final pages = {
      for (final (_, rules) in packs)
        for (final r in rules) r.id: rulePath(r),
    };
    return 'const RULE_PAGES = ${jsonEncode(pages)};\n$siteJs';
  }

  String _searchText(Rule r) => [
    r.title.of('en'),
    ...r.match.patterns,
    ...r.match.codes,
  ].join(' ').toLowerCase();
}

/// Patterns are stored lowercase; show them as a sentence.
String _sentence(String s) =>
    s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, s.lastIndexOf(' ', max - 1))}…';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', //
  'July', 'August', 'September', 'October', 'November', 'December',
];

String _day(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
