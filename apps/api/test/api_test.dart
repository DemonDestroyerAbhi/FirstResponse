import 'dart:convert';

import 'package:api/api.dart';
import 'package:core_rules/core_rules.dart';
import 'package:core_rules/io.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  final bundle = readBundle(findRulesDir());
  late Api api;
  late Handler handler;

  setUp(() {
    api = Api(
      engine: Engine(Rulebook.fromBundle(bundle)),
      bundle: bundle,
      reviews: InMemoryReviewStore(),
      adminToken: 'secret',
      clock: () => DateTime.utc(2026, 11, 23, 10),
    );
    handler = api.handler;
  });

  Future<(int, dynamic)> call(
    String method,
    String path, {
    Object? body,
    Map<String, String>? headers,
  }) async {
    final res = await handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        body: body == null ? null : jsonEncode(body),
        headers: headers,
      ),
    );
    final text = await res.readAsString();
    return (res.statusCode, text.isEmpty ? null : jsonDecode(text));
  }

  const admin = {'authorization': 'Bearer secret'};

  group('diagnose', () {
    test('answers a known message with fix steps and labels', () async {
      final (status, body) = await call(
        'POST',
        '/v1/diagnose',
        body: {'text': 'Error 300: Biometric data did not match'},
      );
      expect(status, 200);
      expect(body['decision'], 'answer');
      expect(body['rule']['id'], 'jeevan_pramaan.biometric_mismatch');
      expect(body['rule']['fix'][1]['actor'], {
        'id': 'aadhaar_centre',
        'label': 'Aadhaar centre',
      });
      expect(body['sequence'], [
        {'record': 'aadhaar', 'name': 'Aadhaar', 'kind': 'fix', 'because': []},
      ]);
      expect(body['audit']['freshness'], 'unverified');
      expect(body, isNot(contains('candidates')));
    });

    test('masks identity numbers before anything is returned', () async {
      final (_, body) = await call(
        'POST',
        '/v1/diagnose',
        body: {'text': 'Aadhaar 1234 5678 9012: biometric mismatch'},
      );
      expect(body['input'], 'Aadhaar XXXX XXXX 9012: biometric mismatch');
      expect(jsonEncode(body), isNot(contains('5678')));
    });

    test('offers candidates, then confirms the one picked', () async {
      const text = 'aadhar not linkd with pension acount';
      final (_, asked) = await call(
        'POST',
        '/v1/diagnose',
        body: {'text': text},
      );
      expect(asked['decision'], 'confirm');
      final ruleId = asked['candidates'][0]['ruleId'];

      final (status, body) = await call(
        'POST',
        '/v1/diagnose/confirm',
        body: {'text': text, 'ruleId': ruleId},
      );
      expect(status, 200);
      expect(body['decision'], 'answer');
      expect(body['audit']['confirmedByUser'], true);
    });

    test('refuses to confirm a rule that was not offered', () async {
      final (status, _) = await call(
        'POST',
        '/v1/diagnose/confirm',
        body: {
          'text': 'aadhar not linkd with pension acount',
          'ruleId': 'jeevan_pramaan.biometrics_locked',
        },
      );
      expect(status, 422);
    });

    test('an unknown message goes to the review queue', () async {
      final (_, body) = await call(
        'POST',
        '/v1/diagnose',
        body: {'text': 'Server busy, try after some time'},
      );
      expect(body['decision'], 'review');
      expect(body['reviewId'], 'rv_1');
      expect(body, isNot(contains('rule')));
    });

    test('rejecting every candidate also goes to review', () async {
      final (status, body) = await call(
        'POST',
        '/v1/diagnose/reject',
        body: {'text': 'aadhar not linkd with pension acount'},
      );
      expect(status, 201);
      final (_, list) = await call('GET', '/v1/admin/review', headers: admin);
      expect(list['items'].single['id'], body['reviewId']);
      expect(list['items'].single['reason'], 'userRejected');
      expect(
        list['items'].single['candidates'],
        contains('jeevan_pramaan.aadhaar_not_seeded_pension'),
      );
    });

    test('bad input is a 400 that does not echo the text', () async {
      for (final body in [
        null,
        'not json',
        {'text': ''},
        {'text': 'x' * (maxInputLength + 1)},
        {'text': 'ok', 'portal': 3},
      ]) {
        final (status, res) = await call('POST', '/v1/diagnose', body: body);
        expect(status, 400, reason: '$body');
        expect(res['error'], isA<String>());
      }
    });
  });

  group('rulebook', () {
    test('serves the bundle with an ETag and honours If-None-Match', () async {
      final res = await handler(
        Request('GET', Uri.parse('http://localhost/v1/rulebook')),
      );
      expect(res.statusCode, 200);
      final etag = res.headers['etag']!;
      expect(etag, contains('jeevan_pramaan@'));

      final again = await handler(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/rulebook'),
          headers: {'if-none-match': etag},
        ),
      );
      expect(again.statusCode, 304);
    });
  });

  test('life certificate returns the window and future reminders', () async {
    final (status, body) = await call(
      'GET',
      '/v1/life-certificate?dob=1960-05-05',
    );
    expect(status, 200);
    expect(body['opens'], '2026-11-01');
    expect(body['closes'], '2026-11-30');
    expect(body['open'], true);
    expect(body['daysLeft'], 7);
    expect(
      [for (final r in body['reminders']) r['date']],
      ['2026-11-23', '2026-11-28', '2026-11-30'],
    );
    expect((await call('GET', '/v1/life-certificate?dob=soon')).$1, 400);
  });

  group('admin', () {
    test('needs the token', () async {
      expect((await call('GET', '/v1/admin/review')).$1, 401);
      expect(
        (await call(
          'GET',
          '/v1/admin/review',
          headers: {'authorization': 'Bearer nope!'},
        )).$1,
        401,
      );
    });

    test('is off when no token is configured', () async {
      handler = Api(
        engine: api.engine,
        bundle: bundle,
        reviews: InMemoryReviewStore(),
      ).handler;
      expect((await call('GET', '/v1/admin/review', headers: admin)).$1, 403);
    });

    test('resolving a review item yields a golden case', () async {
      await call('POST', '/v1/diagnose', body: {'text': 'Pensioner not found'});
      await call('POST', '/v1/diagnose', body: {'text': 'Server busy'});

      final (status, item) = await call(
        'POST',
        '/v1/admin/review/rv_1/resolve',
        headers: admin,
        body: {
          'ruleId': 'jeevan_pramaan.ppo_mismatch',
          'reviewer': 'rk',
          'note': 'Portal wording for a PPO not on file',
        },
      );
      expect(status, 200);
      expect(item['status'], 'resolved');
      await call(
        'POST',
        '/v1/admin/review/rv_2/resolve',
        headers: admin,
        body: {'ruleId': null, 'reviewer': 'rk'},
      );

      final (_, open) = await call(
        'GET',
        '/v1/admin/review?status=open',
        headers: admin,
      );
      expect(open['items'], isEmpty);

      final (_, golden) = await call(
        'GET',
        '/v1/admin/review/golden',
        headers: admin,
      );
      expect(golden['cases'], [
        {
          'input': 'Pensioner not found',
          'expect': {
            'rule': 'jeevan_pramaan.ppo_mismatch',
            'decision': 'answer',
          },
          'fromReview': 'rv_1',
        },
        {
          'input': 'Server busy',
          'expect': {'rule': null, 'decision': 'review'},
          'fromReview': 'rv_2',
        },
      ]);
    });

    test('resolve validates rule, reviewer and id', () async {
      await call('POST', '/v1/diagnose', body: {'text': 'Server busy'});
      Future<int> resolve(String id, Map<String, Object?> body) async =>
          (await call(
            'POST',
            '/v1/admin/review/$id/resolve',
            headers: admin,
            body: body,
          )).$1;
      expect(
        await resolve('rv_1', {'ruleId': 'no.such', 'reviewer': 'rk'}),
        400,
      );
      expect(await resolve('rv_1', {'ruleId': null}), 400);
      expect(await resolve('rv_9', {'ruleId': null, 'reviewer': 'rk'}), 404);
    });
  });

  test('unknown routes are JSON 404s', () async {
    final (status, body) = await call('GET', '/nope');
    expect(status, 404);
    expect(body['error'], 'Not found');
  });

  group('CORS', () {
    const site = 'https://site.example';
    setUp(() {
      handler = Api(
        engine: api.engine,
        bundle: bundle,
        reviews: InMemoryReviewStore(),
        adminToken: 'secret',
        corsOrigins: {site},
      ).handler;
    });

    Future<Response> send(String method, String path, String origin) async =>
        handler(
          Request(
            method,
            Uri.parse('http://localhost$path'),
            headers: {'origin': origin},
            body: method == 'POST' ? jsonEncode({'text': 'Error 300'}) : null,
          ),
        );

    test('allows the listed origin on public routes', () async {
      final pre = await send('OPTIONS', '/v1/diagnose', site);
      expect(pre.statusCode, 204);
      expect(pre.headers['access-control-allow-origin'], site);
      final res = await send('POST', '/v1/diagnose', site);
      expect(res.statusCode, 200);
      expect(res.headers['access-control-allow-origin'], site);
    });

    test('never for other origins, admin or webhooks', () async {
      for (final (origin, path) in [
        ('https://evil.example', '/v1/diagnose'),
        (site, '/v1/admin/review'),
        (site, '/webhooks/whatsapp'),
      ]) {
        final res = await send('GET', path, origin);
        expect(
          res.headers['access-control-allow-origin'],
          isNull,
          reason: '$origin $path',
        );
      }
    });
  });
}
