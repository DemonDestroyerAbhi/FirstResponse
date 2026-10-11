/// Data model for rules, rule packs and the record graph.
///
/// Everything here is parsed from JSON files under `rules/` and must stay free
/// of `dart:io` so the same code runs in the Flutter app (offline), on Flutter
/// web and on the server.
library;

/// Text in several languages, keyed by language code (`en`, `hi`, `mr`).
class LocalizedText {
  final Map<String, String> values;

  const LocalizedText(this.values);

  factory LocalizedText.fromJson(Object? json) {
    if (json is String) return LocalizedText({'en': json});
    if (json is Map) {
      return LocalizedText(
        json.map((k, v) => MapEntry(k as String, v as String)),
      );
    }
    throw FormatException('Expected a string or a language map, got $json');
  }

  /// Returns [lang] if present, otherwise English.
  String of(String lang) => values[lang] ?? values['en'] ?? '';

  Map<String, String> toJson() => values;
}

enum RuleStatus { draft, verified, retired }

enum Severity { low, medium, high }

/// Where an answer's freshness stands at a point in time.
enum Freshness {
  /// Verified by a reviewer and not past its re-verify date.
  current,

  /// Verified once, but the re-verify date has passed.
  stale,

  /// Never verified against an official source.
  unverified,
}

class MatchSpec {
  /// Exact portal codes, e.g. UIDAI auth error `300`.
  final List<String> codes;

  /// Plain phrases, matched after normalization.
  final List<String> patterns;

  /// Regular expressions, matched against normalized text.
  final List<String> regex;

  const MatchSpec({
    this.codes = const [],
    this.patterns = const [],
    this.regex = const [],
  });

  factory MatchSpec.fromJson(Map<String, dynamic> json) => MatchSpec(
    codes: _strings(json['codes']),
    patterns: _strings(json['patterns']),
    regex: _strings(json['regex']),
  );

  bool get isEmpty => codes.isEmpty && patterns.isEmpty && regex.isEmpty;
}

class FixStep {
  /// Who performs the step, e.g. `bank_branch`, `aadhaar_centre`, `self`.
  final String actor;
  final LocalizedText action;
  final String? form;
  final List<String> bring;
  final String? channel;
  final int? typicalDays;

  const FixStep({
    required this.actor,
    required this.action,
    this.form,
    this.bring = const [],
    this.channel,
    this.typicalDays,
  });

  factory FixStep.fromJson(Map<String, dynamic> json) => FixStep(
    actor: json['actor'] as String,
    action: LocalizedText.fromJson(json['action']),
    form: json['form'] as String?,
    bring: _strings(json['bring']),
    channel: json['channel'] as String?,
    typicalDays: json['typicalDays'] as int?,
  );
}

class RuleSource {
  final String url;
  final String? title;
  final DateTime? verifiedOn;
  final String? reviewer;

  const RuleSource({
    required this.url,
    this.title,
    this.verifiedOn,
    this.reviewer,
  });

  factory RuleSource.fromJson(Map<String, dynamic> json) => RuleSource(
    url: json['url'] as String,
    title: json['title'] as String?,
    verifiedOn: _date(json['verifiedOn']),
    reviewer: json['reviewer'] as String?,
  );
}

class Rule {
  final String id;
  final String version;
  final String portal;
  final RuleStatus status;
  final Severity severity;
  final LocalizedText title;
  final LocalizedText explain;
  final MatchSpec match;

  /// `<record>.<problem>`, e.g. `pension_account.aadhaar_not_seeded`.
  final String rootCause;

  /// Services this problem blocks, e.g. `pension.payment`.
  final List<String> blocks;
  final List<FixStep> fix;
  final List<RuleSource> sources;
  final DateTime? reverifyBy;

  /// A catch-all rule ("life certificate rejected") that yields to any
  /// specific rule matching the same input.
  final bool generic;

  /// Whether fixing this changes values other records copy. A biometric
  /// update does not, so nothing downstream needs a re-sync.
  final bool propagates;

  const Rule({
    required this.id,
    required this.version,
    required this.portal,
    required this.status,
    required this.severity,
    required this.title,
    required this.explain,
    required this.match,
    required this.rootCause,
    this.blocks = const [],
    this.fix = const [],
    this.sources = const [],
    this.reverifyBy,
    this.generic = false,
    this.propagates = true,
  });

  factory Rule.fromJson(Map<String, dynamic> json) => Rule(
    id: json['id'] as String,
    version: json['version'] as String,
    portal: json['portal'] as String,
    status: RuleStatus.values.byName(json['status'] as String? ?? 'draft'),
    severity: Severity.values.byName(json['severity'] as String? ?? 'medium'),
    title: LocalizedText.fromJson(json['title']),
    explain: LocalizedText.fromJson(json['explain']),
    match: MatchSpec.fromJson(json['match'] as Map<String, dynamic>),
    rootCause: json['rootCause'] as String,
    blocks: _strings(json['blocks']),
    fix: [
      for (final f in (json['fix'] as List? ?? const []))
        FixStep.fromJson(f as Map<String, dynamic>),
    ],
    sources: [
      for (final s in (json['sources'] as List? ?? const []))
        RuleSource.fromJson(s as Map<String, dynamic>),
    ],
    reverifyBy: _date(json['reverifyBy']),
    generic: json['generic'] as bool? ?? false,
    propagates: json['propagates'] as bool? ?? true,
  );

  /// The record this rule says is wrong.
  String get record => rootCause.split('.').first;

  Freshness freshnessAt(DateTime now) {
    if (status != RuleStatus.verified ||
        sources.every((s) => s.verifiedOn == null)) {
      return Freshness.unverified;
    }
    final due = reverifyBy;
    if (due != null && now.isAfter(due)) return Freshness.stale;
    return Freshness.current;
  }
}

/// A data store that can hold a wrong value, such as Aadhaar or a bank's KYC.
class RecordType {
  final String id;
  final LocalizedText name;

  /// Who corrects this record, e.g. `aadhaar_centre`.
  final String fixedBy;

  /// Records this one copies its values from. Aadhaar has none: it is the
  /// source of truth that everything else is checked against.
  final List<String> copiesFrom;

  const RecordType({
    required this.id,
    required this.name,
    required this.fixedBy,
    this.copiesFrom = const [],
  });

  factory RecordType.fromJson(Map<String, dynamic> json) => RecordType(
    id: json['id'] as String,
    name: LocalizedText.fromJson(json['name']),
    fixedBy: json['fixedBy'] as String,
    copiesFrom: _strings(json['copiesFrom']),
  );
}

class PackInfo {
  final String id;
  final String version;
  final String portal;
  final LocalizedText name;

  /// Records this portal's cases can touch. Re-sync steps outside this set
  /// are left out of a diagnosis. Empty means no limit.
  final Set<String> involves;

  const PackInfo({
    required this.id,
    required this.version,
    required this.portal,
    required this.name,
    this.involves = const {},
  });

  factory PackInfo.fromJson(Map<String, dynamic> json) => PackInfo(
    id: json['id'] as String,
    version: json['version'] as String,
    portal: json['portal'] as String,
    name: LocalizedText.fromJson(json['name']),
    involves: _strings(json['involves']).toSet(),
  );
}

List<String> _strings(Object? json) => [
  for (final s in (json as List? ?? const [])) s as String,
];

DateTime? _date(Object? json) =>
    json == null ? null : DateTime.parse(json as String);
