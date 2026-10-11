// Builds the static site into a folder.
//
//   dart run site:build --base-url https://example.in [--api-url URL]
//                       [--drafts] [--out build/site]
//
// --drafts makes a preview: draft rules included, every page noindex.
import 'dart:io';

import 'package:core_rules/io.dart';
import 'package:site/site.dart';

void main(List<String> args) {
  String? opt(String name) {
    final i = args.indexOf('--$name');
    return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
  }

  final base = opt('base-url');
  if (base == null) {
    stderr.writeln(
      'usage: build --base-url URL [--api-url URL] [--drafts] [--out DIR]',
    );
    exitCode = 64;
    return;
  }
  final api = opt('api-url');
  final out = Directory(opt('out') ?? 'build/site');
  final files = buildSite(
    loadRulebook(findRulesDir()),
    SiteOptions(
      baseUrl: Uri.parse(base),
      apiUrl: api == null ? null : Uri.parse(api),
      drafts: args.contains('--drafts'),
      builtAt: DateTime.now().toUtc(),
    ),
  );

  if (out.existsSync()) out.deleteSync(recursive: true);
  for (final MapEntry(key: path, value: content) in files.entries) {
    File('${out.path}/$path')
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }
  final pages = files.keys.where((p) => p.endsWith('.html')).length;
  stdout.writeln('Wrote $pages pages to ${out.path}');
}
