import 'dart:convert';
import 'dart:io';

import 'package:app/main.dart';
import 'package:app/src/life_certificate_screen.dart';
import 'package:core_rules/core_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The same bundle the app ships; run `rules bundle` first.
  final engine = Engine(
    Rulebook.fromBundle(
      jsonDecode(File('assets/rulebook.json').readAsStringSync())
          as Map<String, dynamic>,
    ),
  );

  Future<void> openDiagnose(WidgetTester tester, String message) async {
    await tester.pumpWidget(App(engine: engine));
    await tester.tap(find.text('Explain a rejection or error'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), message);
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
  }

  testWidgets('a known message shows the fix and an unverified warning', (
    tester,
  ) async {
    await openDiagnose(tester, 'Error 300: Biometric data did not match');
    expect(find.text('Fingerprint or iris did not match Aadhaar'), findsOne);
    expect(find.textContaining('not yet been checked'), findsOne);
    expect(find.text('Aadhaar centre'), findsOne);
  });

  testWidgets('a misspelt message asks before answering', (tester) async {
    await openDiagnose(tester, 'aadhar not linkd with pension acount');
    expect(find.text('Is this your problem?'), findsOne);
    await tester.tap(find.text('Yes, that is it'));
    await tester.pumpAndSettle();
    expect(find.text('Is this your problem?'), findsNothing);
    expect(
      find.text(
        'Bring: Aadhaar card, Bank passbook, '
        'PPO booklet or pension slip',
      ),
      findsOne,
    );
  });

  testWidgets('an unknown message says so instead of guessing', (tester) async {
    await openDiagnose(tester, 'Server busy, try after some time');
    expect(find.textContaining("don't recognise"), findsOne);
  });

  testWidgets('life certificate shows the window and days left', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LifeCertificateScreen(
          engine: engine,
          today: () => DateTime(2026, 11, 23),
        ),
      ),
    );
    await tester.tap(find.text("Enter pensioner's date of birth"));
    await tester.pumpAndSettle();
    // Date picker opens in year mode; switch to typing the date.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '05/05/1960');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('7 days left to submit'), findsOne);
    expect(find.text('Window: 1 Nov 2026 to 30 Nov 2026'), findsOne);
  });
}
