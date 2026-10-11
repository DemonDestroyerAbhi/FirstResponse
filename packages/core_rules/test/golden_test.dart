// Runs every rule pack's golden cases, so CI blocks a merge that breaks one.
import 'package:core_rules/core_rules.dart';
import 'package:core_rules/io.dart';
import 'package:test/test.dart';

void main() {
  final dir = findRulesDir();
  final engine = Engine(loadRulebook(dir));

  for (final c in loadGoldenCases(dir)) {
    test('[${c.pack}] ${c.input}', () {
      final failure = c.check(engine);
      if (failure != null) fail(failure);
    });
  }
}
