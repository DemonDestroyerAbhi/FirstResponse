import 'package:core_rules/core_rules.dart';
import 'package:test/test.dart';

RecordType rec(String id, [List<String> from = const []]) => RecordType(
  id: id,
  name: LocalizedText({'en': id}),
  fixedBy: 'x',
  copiesFrom: from,
);

void main() {
  final graph = [
    rec('aadhaar'),
    rec('pan', ['aadhaar']),
    rec('bank_kyc', ['aadhaar', 'pan']),
    rec('npci_mapper', ['bank_kyc']),
    rec('epfo_kyc', ['aadhaar', 'pan', 'bank_kyc']),
  ];
  final seq = FixSequencer(graph);
  List<String> plan(Set<String> broken, {Set<String>? involved}) => [
    for (final s in seq.plan(broken, involved: involved)) s.toString(),
  ];

  test('fixes the source of truth before records that copy it', () {
    expect(plan({'epfo_kyc', 'aadhaar'}), [
      'fix:aadhaar',
      'resync:pan <- aadhaar',
      'resync:bank_kyc <- aadhaar,pan',
      'fix:epfo_kyc',
      'resync:npci_mapper <- bank_kyc',
    ]);
  });

  test('a leaf fix needs no re-syncs', () {
    expect(plan({'npci_mapper'}), ['fix:npci_mapper']);
  });

  test('involved hides unrelated re-syncs but keeps propagation', () {
    expect(plan({'aadhaar'}, involved: {'npci_mapper'}), [
      'fix:aadhaar',
      // pan and bank_kyc are hidden, but the change still reaches npci.
      'resync:npci_mapper <- bank_kyc',
    ]);
  });

  test('reasons name only steps the user can see', () {
    expect(plan({'aadhaar'}, involved: {'bank_kyc'}), [
      'fix:aadhaar',
      'resync:bank_kyc <- aadhaar',
    ]);
  });

  test('rejects cycles and unknown records', () {
    expect(
      () => FixSequencer([
        rec('a', ['b']),
        rec('b', ['a']),
      ]),
      throwsA(isA<RecordGraphException>()),
    );
    expect(
      () => FixSequencer([
        rec('a', ['missing']),
      ]),
      throwsA(isA<RecordGraphException>()),
    );
    expect(() => seq.plan({'nope'}), throwsA(isA<RecordGraphException>()));
  });
}
