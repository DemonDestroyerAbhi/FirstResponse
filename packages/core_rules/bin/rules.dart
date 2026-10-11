// Rulebook tool for reviewers and CI.
//
//   dart run core_rules:rules validate           Load and validate every pack
//   dart run core_rules:rules golden             Run every golden case
//   dart run core_rules:rules diagnose "<text>"  [--portal p] [--code c]
//   dart run core_rules:rules bundle <out.json>  Write the app's offline bundle
import 'dart:convert';
import 'dart:io';

import 'package:core_rules/core_rules.dart';
import 'package:core_rules/io.dart';

void main(List<String> args) {
  if (args.isEmpty) return _usage();
  final Rulebook book;
  try {
    book = loadRulebook(findRulesDir());
  } on RulebookException catch (e) {
    stderr.writeln('Rulebook is invalid:\n  ${e.problems.join('\n  ')}');
    exitCode = 1;
    return;
  }

  switch (args.first) {
    case 'validate':
      final now = DateTime.now();
      for (final pack in book.packs) {
        final counts = <Freshness, int>{};
        for (final r in pack.rules) {
          counts.update(r.freshnessAt(now), (n) => n + 1, ifAbsent: () => 1);
        }
        stdout.writeln(
          '${pack.info.id} ${pack.info.version}: '
          '${pack.rules.length} rules '
          '(${counts.entries.map((e) => '${e.value} ${e.key.name}').join(', ')})',
        );
      }
    case 'golden':
      final engine = Engine(book);
      final cases = loadGoldenCases(findRulesDir());
      final failures = [for (final c in cases) ?c.check(engine)];
      failures.forEach(stderr.writeln);
      stdout.writeln(
        '${cases.length - failures.length}/${cases.length} '
        'golden cases pass',
      );
      if (failures.isNotEmpty) exitCode = 1;
    case 'bundle' when args.length == 2:
      // Validated above, so a broken rulebook never reaches a bundle.
      File(args[1])
        ..parent.createSync(recursive: true)
        ..writeAsStringSync(jsonEncode(readBundle(findRulesDir())));
      stdout.writeln(
        'Wrote ${book.rules.length} rules from '
        '${book.packs.length} packs to ${args[1]}',
      );
    case 'diagnose' when args.length >= 2:
      String? opt(String name) {
        final i = args.indexOf('--$name');
        return i >= 0 && i + 1 < args.length ? args[i + 1] : null;
      }
      final d = Engine(
        book,
      ).diagnose(args[1], portal: opt('portal'), code: opt('code'));
      stdout.writeln(
        const JsonEncoder.withIndent('  ').convert({
          ...d.toAuditJson(),
          'title': d.rule?.title.of('en'),
          'sequence': [for (final s in d.sequence) s.toString()],
          'fix': [
            for (final f in d.rule?.fix ?? const <FixStep>[])
              '${f.actor}: ${f.action.of('en')}',
          ],
        }),
      );
    default:
      _usage();
  }
}

void _usage() {
  stderr.writeln(
    'usage: rules validate | golden | bundle <out.json> | '
    'diagnose "<text>" [--portal p] [--code c]',
  );
  exitCode = 64;
}
