import 'model.dart';
import 'sequencer.dart';

class RulebookException implements Exception {
  final List<String> problems;
  const RulebookException(this.problems);
  @override
  String toString() => 'RulebookException:\n  ${problems.join('\n  ')}';
}

class RulePack {
  final PackInfo info;
  final List<Rule> rules;
  const RulePack(this.info, this.rules);
}

/// The full set of record types and rule packs, validated on load.
///
/// Loading is from already-decoded JSON so the caller decides where files
/// come from: disk in the CLI and server, bundled assets in the app.
class Rulebook {
  final Map<String, RecordType> records;
  final List<RulePack> packs;
  final FixSequencer sequencer;

  /// Display names for actor, document and form ids used in fix steps.
  final Map<String, LocalizedText> labels;

  Rulebook._(this.records, this.packs, this.sequencer, this.labels);

  /// Display name for an actor, document or form id.
  String label(String id, [String lang = 'en']) => labels[id]?.of(lang) ?? id;

  Iterable<Rule> get rules => packs.expand((p) => p.rules);

  /// Every pack's id and version, e.g. `jeevan_pramaan@0.1.0`. Changes when
  /// any pack changes, so it serves as the download version (ETag).
  late final String version = [
    for (final p in packs) '${p.info.id}@${p.info.version}',
  ].join(',');

  Rule? rule(String id) {
    for (final r in rules) {
      if (r.id == id) return r;
    }
    return null;
  }

  PackInfo packOf(Rule rule) =>
      packs.firstWhere((p) => p.rules.contains(rule)).info;

  /// [recordsJson] is `rules/records.json`. Each pack is its `pack.json`
  /// plus the decoded contents of every file in its `rules/` folder.
  factory Rulebook.fromJson(
    Map<String, dynamic> recordsJson,
    List<(Map<String, dynamic> pack, List<Map<String, dynamic>> rules)> packs,
  ) {
    final problems = <String>[];

    final recordList = [
      for (final r in recordsJson['records'] as List)
        RecordType.fromJson(r as Map<String, dynamic>),
    ];
    final records = {for (final r in recordList) r.id: r};
    if (records.length != recordList.length) {
      problems.add('records.json has duplicate record ids');
    }
    FixSequencer? sequencer;
    try {
      sequencer = FixSequencer(recordList);
    } on RecordGraphException catch (e) {
      problems.add(e.message);
    }

    final labels = {
      for (final e in (recordsJson['labels'] as Map? ?? const {}).entries)
        e.key as String: LocalizedText.fromJson(e.value),
    };
    for (final r in recordList) {
      if (!labels.containsKey(r.fixedBy)) {
        problems.add('record ${r.id}: no label for fixedBy "${r.fixedBy}"');
      }
    }

    final loaded = <RulePack>[];
    final seen = <String>{};
    for (final (packJson, ruleJsons) in packs) {
      final info = PackInfo.fromJson(packJson);
      if (!_semver.hasMatch(info.version)) {
        problems.add(
          'pack ${info.id}: version "${info.version}" is not semver',
        );
      }
      for (final id in info.involves) {
        if (!records.containsKey(id)) {
          problems.add('pack ${info.id}: involves unknown record "$id"');
        }
      }
      final rules = <Rule>[];
      for (final json in ruleJsons) {
        final where = 'pack ${info.id}, rule ${json['id'] ?? '(no id)'}';
        final Rule rule;
        try {
          rule = Rule.fromJson(json);
        } catch (e) {
          problems.add('$where: cannot parse: $e');
          continue;
        }
        problems.addAll(_check(rule, info, records).map((p) => '$where: $p'));
        for (final f in rule.fix) {
          for (final id in [f.actor, ?f.form, ...f.bring]) {
            if (!labels.containsKey(id)) {
              problems.add('$where: no label for "$id"');
            }
          }
        }
        if (!seen.add(rule.id)) problems.add('$where: duplicate rule id');
        rules.add(rule);
      }
      loaded.add(RulePack(info, rules));
    }

    if (problems.isNotEmpty) throw RulebookException(problems);
    return Rulebook._(records, loaded, sequencer!, labels);
  }

  /// Loads a bundle written by `rules bundle`: one JSON object holding
  /// `records` and every pack, as shipped in the app and sent over the air.
  factory Rulebook.fromBundle(Map<String, dynamic> bundle) =>
      Rulebook.fromJson(bundle['records'] as Map<String, dynamic>, [
        for (final p in bundle['packs'] as List)
          (
            p['pack'] as Map<String, dynamic>,
            [for (final r in p['rules'] as List) r as Map<String, dynamic>],
          ),
      ]);

  static final _semver = RegExp(r'^\d+\.\d+\.\d+$');

  static List<String> _check(
    Rule rule,
    PackInfo pack,
    Map<String, RecordType> records,
  ) {
    final p = <String>[];
    if (!rule.id.startsWith('${pack.id}.')) {
      p.add('id must start with "${pack.id}."');
    }
    if (rule.portal != pack.portal) {
      p.add(
        'portal "${rule.portal}" differs from pack portal "${pack.portal}"',
      );
    }
    if (!_semver.hasMatch(rule.version)) p.add('version is not semver');
    if (rule.match.isEmpty) p.add('match has no codes, patterns or regex');
    for (final re in rule.match.regex) {
      try {
        RegExp(re, unicode: true);
      } on FormatException catch (e) {
        p.add('bad regex "$re": ${e.message}');
      }
    }
    if (!rule.rootCause.contains('.')) {
      p.add('rootCause must be "<record>.<problem>"');
    } else if (!records.containsKey(rule.record)) {
      p.add('rootCause record "${rule.record}" is not in records.json');
    }
    if (rule.fix.isEmpty) p.add('no fix steps');
    if (rule.sources.isEmpty) p.add('no sources');
    if (rule.status == RuleStatus.verified) {
      if (rule.sources.any((s) => s.verifiedOn == null || s.reviewer == null)) {
        p.add('verified rule needs verifiedOn and reviewer on every source');
      }
      if (rule.reverifyBy == null) p.add('verified rule needs reverifyBy');
    }
    if (rule.title.values['en'] == null || rule.explain.values['en'] == null) {
      p.add('title and explain need English text');
    }
    return p;
  }
}
