import 'dart:convert';
import 'dart:io';

import 'package:app/main.dart';
import 'package:app/src/life_certificate_screen.dart';
import 'package:app/src/services/api_client.dart';
import 'package:app/src/services/rulebook_service.dart';
import 'package:core_rules/core_rules.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The bundle the app ships; run `rules bundle` first.
final assetJson = File('assets/rulebook.json').readAsStringSync();

/// The shipped bundle with one more phrase on the PPO rule and the pack
/// version bumped, as if a reviewer had added it on the server.
String newerBundle({String version = '9.0.0'}) {
  final b = jsonDecode(assetJson) as Map<String, dynamic>;
  final pack = (b['packs'] as List).first as Map<String, dynamic>;
  pack['pack']['version'] = version;
  final ppo = (pack['rules'] as List).firstWhere(
    (r) => r['id'] == 'jeevan_pramaan.ppo_mismatch',
  );
  (ppo['match']['patterns'] as List).add('pensioner record not found');
  return jsonEncode(b);
}

String versionOf(String json) =>
    Rulebook.fromBundle(jsonDecode(json) as Map<String, dynamic>).version;

/// A fake API: serves [bundle] and records what the app sent.
class FakeServer {
  String bundle;
  String diagnoseDecision = 'review';
  bool offline = false;
  final calls = <String>[];
  final bodies = <Map<String, dynamic>>[];

  FakeServer(this.bundle);

  ApiClient client() => ApiClient(
    Uri.parse('https://api.test'),
    client: MockClient((req) async {
      if (offline) throw http.ClientException('offline');
      calls.add('${req.method} ${req.url.path}');
      if (req.body.isNotEmpty) bodies.add(jsonDecode(req.body));
      switch (req.url.path) {
        case '/v1/rulebook':
          final etag = '"${versionOf(bundle)}"';
          if (req.headers['if-none-match'] == etag) {
            return http.Response('', 304);
          }
          return http.Response(bundle, 200, headers: {'etag': etag});
        case '/v1/diagnose':
          return http.Response(jsonEncode({'decision': diagnoseDecision}), 200);
        case '/v1/diagnose/reject':
          return http.Response('{"reviewId":"rv_1"}', 201);
      }
      return http.Response('', 404);
    }),
  );
}

void main() {
  group('rulebook service', () {
    test('starts from the shipped rules, offline', () async {
      final rules = await RulebookService.load(
        assetJson: assetJson,
        cache: MemoryBundleCache(),
      );
      expect(rules.version, 'jeevan_pramaan@0.1.0');
      expect(await rules.refresh(), isFalse);
    });

    test('downloads newer rules once, then asks with its ETag', () async {
      final server = FakeServer(newerBundle());
      final cache = MemoryBundleCache();
      final rules = await RulebookService.load(
        assetJson: assetJson,
        cache: cache,
        api: server.client(),
      );
      var notified = 0;
      rules.addListener(() => notified++);

      expect(await rules.refresh(), isTrue);
      expect(rules.version, 'jeevan_pramaan@9.0.0');
      expect(notified, 1);
      expect(await rules.refresh(), isFalse, reason: '304 the second time');

      // The next launch starts from the download, without the network.
      final next = await RulebookService.load(
        assetJson: assetJson,
        cache: cache,
      );
      expect(next.version, 'jeevan_pramaan@9.0.0');
    });

    test('nothing to download when the server has the same rules', () async {
      final server = FakeServer(assetJson);
      final rules = await RulebookService.load(
        assetJson: assetJson,
        cache: MemoryBundleCache(),
        api: server.client(),
      );
      expect(await rules.refresh(), isFalse);
    });

    test('ignores a download that fails validation', () async {
      final bad = jsonDecode(newerBundle()) as Map<String, dynamic>;
      ((bad['packs'] as List).first['rules'] as List).first['rootCause'] =
          'nowhere.x';
      final cache = MemoryBundleCache();
      final rules = await RulebookService.load(
        assetJson: assetJson,
        cache: cache,
        api: FakeServer(jsonEncode(bad)).client(),
      );
      expect(await rules.refresh(), isFalse);
      expect(rules.version, 'jeevan_pramaan@0.1.0');
      expect(cache.value, isNull);
    });

    test('drops a download made by an older app build', () async {
      final cache = MemoryBundleCache()
        ..value = CachedBundle(
          json: newerBundle(),
          etag: '"x"',
          assetVersion: 'jeevan_pramaan@0.0.1',
        );
      final rules = await RulebookService.load(
        assetJson: assetJson,
        cache: cache,
      );
      expect(rules.version, 'jeevan_pramaan@0.1.0');
      expect(cache.value, isNull);
    });

    test('offline refresh keeps the current rules', () async {
      final server = FakeServer(newerBundle())..offline = true;
      final rules = await RulebookService.load(
        assetJson: assetJson,
        cache: MemoryBundleCache(),
        api: server.client(),
      );
      expect(await rules.refresh(), isFalse);
      expect(rules.version, 'jeevan_pramaan@0.1.0');
    });
  });

  group('screens', () {
    late FakeServer server;

    Future<RulebookService> load({bool online = true}) => RulebookService.load(
      assetJson: assetJson,
      cache: MemoryBundleCache(),
      api: online ? server.client() : null,
    );

    setUp(() => server = FakeServer(assetJson));

    Future<void> openDiagnose(
      WidgetTester tester,
      RulebookService rules,
      String message,
    ) async {
      await tester.pumpWidget(App(rules: rules));
      await tester.tap(find.text('Explain a rejection or error'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), message);
      await tester.tap(find.text('Check'));
      await tester.pumpAndSettle();
    }

    testWidgets('a known message shows the fix without the network', (
      tester,
    ) async {
      final rules = await tester.runAsync(() => load(online: false));
      await openDiagnose(
        tester,
        rules!,
        'Error 300: Biometric data did not match',
      );
      expect(find.text('Fingerprint or iris did not match Aadhaar'), findsOne);
      expect(find.textContaining('not yet been checked'), findsOne);
      expect(find.text('Aadhaar centre'), findsOne);
    });

    testWidgets('a misspelt message asks before answering', (tester) async {
      final rules = await tester.runAsync(() => load(online: false));
      await openDiagnose(
        tester,
        rules!,
        'aadhar not linkd with pension acount',
      );
      expect(find.text('Is this your problem?'), findsOne);
      await tester.tap(find.text('Yes, that is it'));
      await tester.pumpAndSettle();
      expect(find.text('Is this your problem?'), findsNothing);
      expect(
        find.text(
          'Bring: Aadhaar card, Bank passbook, PPO booklet or pension slip',
        ),
        findsOne,
      );
    });

    testWidgets('an unknown message goes to the review queue, masked', (
      tester,
    ) async {
      final rules = await tester.runAsync(load);
      await tester.runAsync(
        () => openDiagnose(tester, rules!, 'Server busy for 123456789012'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("we've sent it to our team"), findsOne);
      expect(server.calls, ['POST /v1/diagnose']);
      expect(server.bodies.single['text'], 'Server busy for XXXX XXXX 9012');
    });

    testWidgets('if the server knows the message, the app updates its rules', (
      tester,
    ) async {
      final rules = await tester.runAsync(load);
      server
        ..bundle = newerBundle()
        ..diagnoseDecision = 'answer';
      await tester.runAsync(
        () => openDiagnose(tester, rules!, 'Pensioner record not found'),
      );
      await tester.pumpAndSettle();
      expect(server.calls, ['POST /v1/diagnose', 'GET /v1/rulebook']);
      expect(find.text('PPO number does not match'), findsOne);
      expect(rules!.version, 'jeevan_pramaan@9.0.0');
    });

    testWidgets('turning down every suggestion queues the message', (
      tester,
    ) async {
      final rules = await tester.runAsync(load);
      await openDiagnose(
        tester,
        rules!,
        'aadhar not linkd with pension acount',
      );
      await tester.runAsync(() async {
        await tester.tap(find.text('No'));
        await Future<void>.delayed(Duration.zero);
      });
      await tester.pumpAndSettle();
      expect(server.calls, ['POST /v1/diagnose/reject']);
      expect(find.textContaining("we've sent it to our team"), findsOne);
    });

    testWidgets('offline, an unknown message says so without promising', (
      tester,
    ) async {
      server.offline = true;
      final rules = await tester.runAsync(load);
      await tester.runAsync(
        () => openDiagnose(tester, rules!, 'Server busy, try after some time'),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining("don't recognise"), findsOne);
      expect(find.textContaining("we've sent it"), findsNothing);
    });

    testWidgets('life certificate shows the window and days left', (
      tester,
    ) async {
      final rules = await tester.runAsync(() => load(online: false));
      await tester.pumpWidget(
        MaterialApp(
          home: LifeCertificateScreen(
            rules: rules!,
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
  });
}
