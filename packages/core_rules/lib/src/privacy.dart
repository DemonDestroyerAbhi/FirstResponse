/// Masks identity numbers in free text before it is stored or sent anywhere.
///
/// Diagnosis never needs the numbers themselves, so input is masked at
/// intake: Aadhaar and long account-like numbers keep their last 4 digits,
/// PAN keeps its last 4 characters. Masking too much is safe; too little is
/// not, so any 9 or more digit run is treated as an identifier.
library;

final _aadhaar = RegExp(r'(?<!\d)\d{4}[ -]?\d{4}[ -]?(\d{4})(?!\d)');
final _pan = RegExp(r'\b[A-Za-z]{5}\d{4}[A-Za-z]\b');
final _longNumber = RegExp(r'(?<!\d)\d{5,14}(\d{4})(?!\d)');

String maskIdentifiers(String text) => text
    .replaceAllMapped(_aadhaar, (m) => 'XXXX XXXX ${m[1]}')
    .replaceAllMapped(_pan, (m) => 'XXXXXX${m[0]!.substring(6).toUpperCase()}')
    .replaceAllMapped(_longNumber, (m) => 'XXXX${m[1]}');
