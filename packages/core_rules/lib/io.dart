/// Loads the rulebook and golden cases from the `rules/` folder on disk.
///
/// Kept apart from `core_rules.dart` because it imports `dart:io`, which
/// Flutter web cannot use. The app loads the same files from bundled assets.
library;

import 'dart:convert';
import 'dart:io';

import 'core_rules.dart';

Rulebook loadRulebook(Directory rulesDir) =>
    Rulebook.fromBundle(readBundle(rulesDir));

/// Reads every pack into the single-object form `Rulebook.fromBundle` takes.
Map<String, dynamic> readBundle(Directory rulesDir) => {
  'records': _json(File('${rulesDir.path}/records.json')),
  'packs': [
    for (final dir in _sorted(
      Directory('${rulesDir.path}/packs').listSync().whereType<Directory>(),
    ))
      {
        'pack': _json(File('${dir.path}/pack.json')),
        'rules': [
          for (final f in _sorted(
            Directory('${dir.path}/rules').listSync().whereType<File>().where(
              (f) => f.path.endsWith('.json'),
            ),
          ))
            _json(f),
        ],
      },
  ],
};

class GoldenCase {
  final String pack;
  final String input;
  final String? code;
  final String? expectRule;
  final Decision expectDecision;

  const GoldenCase(
    this.pack,
    this.input,
    this.code,
    this.expectRule,
    this.expectDecision,
  );

  /// Returns a description of the mismatch, or null when the engine agrees.
  String? check(Engine engine) {
    final d = engine.diagnose(input, portal: pack, code: code);
    final rule = d.decision == Decision.review ? null : d.rule?.id;
    if (rule == expectRule && d.decision == expectDecision) return null;
    return '[$pack] "$input": expected ${expectRule ?? 'no rule'} '
        '(${expectDecision.name}), got ${rule ?? 'no rule'} '
        '(${d.decision.name}${d.match == null ? '' : ', ${d.match}'})';
  }
}

List<GoldenCase> loadGoldenCases(Directory rulesDir) => [
  for (final dir in _sorted(
    Directory('${rulesDir.path}/packs').listSync().whereType<Directory>(),
  ))
    for (final f in _sorted(
      Directory(
        '${dir.path}/golden',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.json')),
    ))
      for (final c in jsonDecode(f.readAsStringSync()) as List)
        GoldenCase(
          dir.uri.pathSegments.where((s) => s.isNotEmpty).last,
          c['input'] as String,
          c['code'] as String?,
          c['expect']['rule'] as String?,
          Decision.values.byName(c['expect']['decision'] as String),
        ),
];

/// Finds the repo's `rules/` folder by walking up from the current directory.
Directory findRulesDir([Directory? from]) {
  var dir = (from ?? Directory.current).absolute;
  while (true) {
    final candidate = Directory('${dir.path}/rules');
    if (File('${candidate.path}/records.json').existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('No rules/records.json above ${Directory.current.path}');
    }
    dir = parent;
  }
}

Map<String, dynamic> _json(File f) =>
    jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

List<T> _sorted<T extends FileSystemEntity>(Iterable<T> items) =>
    items.toList()..sort((a, b) => a.path.compareTo(b.path));
