import 'package:core_rules/core_rules.dart';
import 'package:test/test.dart';

void main() {
  test('masks Aadhaar in any spacing, keeping the last 4 digits', () {
    expect(
      maskIdentifiers('Aadhaar 1234 5678 9012 failed'),
      'Aadhaar XXXX XXXX 9012 failed',
    );
    expect(maskIdentifiers('UID:123456789012.'), 'UID:XXXX XXXX 9012.');
    expect(maskIdentifiers('1234-5678-9012'), 'XXXX XXXX 9012');
  });

  test('masks PAN and long account numbers', () {
    expect(maskIdentifiers('PAN abcde1234f linked'), 'PAN XXXXXX234F linked');
    expect(maskIdentifiers('A/c 50100012345678'), 'A/c XXXX5678');
    expect(maskIdentifiers('PPO 123456789'), 'PPO XXXX6789');
  });

  test('leaves error codes, amounts and dates alone', () {
    const text = 'Error 300 on 30/11/2026, pension Rs 25000';
    expect(maskIdentifiers(text), text);
  });

  test('the engine never keeps an unmasked number', () {
    final book = Rulebook.fromJson({'records': <Object>[]}, []);
    expect(
      Engine(book).diagnose('Aadhaar 123456789012 failed').input,
      'Aadhaar XXXX XXXX 9012 failed',
    );
  });
}
