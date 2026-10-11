// The same contract for every ReviewStore. The Postgres run needs
// TEST_DATABASE_URL, e.g.
//   postgresql://postgres:dev@localhost:5432/firstresponse?sslmode=disable
// and is skipped without it.
import 'dart:io';

import 'package:api/api.dart';
import 'package:postgres/postgres.dart' as pg;
import 'package:test/test.dart';

void main() {
  group('in memory', () => contract(() async => InMemoryReviewStore()));

  final url = Platform.environment['TEST_DATABASE_URL'];
  group('postgres', () {
    late pg.Pool<void> pool;

    setUpAll(() async {
      pool = pg.Pool.withUrl(url!);
      await migrate(pool);
    });
    tearDownAll(() => pool.close());

    contract(() async {
      await pool.execute('TRUNCATE review_items RESTART IDENTITY');
      return PostgresReviewStore(pool);
    });

    test('migrating again, even concurrently, is a no-op', () async {
      final versions = await Future.wait([migrate(pool), migrate(pool)]);
      expect(versions, [migrations.length, migrations.length]);
      final rows = await pool.execute('SELECT count(*) FROM schema_migrations');
      expect(rows.single.single, migrations.length);
    });
  }, skip: url == null ? 'TEST_DATABASE_URL not set' : null);
}

void contract(Future<ReviewStore> Function() make) {
  late ReviewStore store;
  final t0 = DateTime.utc(2026, 11, 23, 10);

  setUp(() async => store = await make());

  test('adds and reads back every field', () async {
    final added = await store.add(
      input: 'Server busy',
      reason: ReviewReason.userRejected,
      at: t0,
      portal: 'jeevan_pramaan',
      code: '998',
      candidates: ['a.b', 'c.d'],
    );
    expect(added.id, 'rv_1');
    final got = (await store.get('rv_1'))!;
    expect(got.toJson(), added.toJson());
    expect(got.toJson(), {
      'id': 'rv_1',
      'createdAt': '2026-11-23T10:00:00.000Z',
      'input': 'Server busy',
      'portal': 'jeevan_pramaan',
      'code': '998',
      'reason': 'userRejected',
      'candidates': ['a.b', 'c.d'],
      'status': 'open',
      'resolvedRuleId': null,
      'note': null,
      'reviewer': null,
      'resolvedAt': null,
    });
  });

  test('optional fields may be empty', () async {
    await store.add(input: 'x', reason: ReviewReason.noMatch, at: t0);
    final got = (await store.get('rv_1'))!;
    expect(got.portal, isNull);
    expect(got.candidates, isEmpty);
  });

  test('lists oldest first and filters by status', () async {
    await store.add(input: 'later', reason: ReviewReason.noMatch, at: t0);
    await store.add(
      input: 'earlier',
      reason: ReviewReason.noMatch,
      at: t0.subtract(const Duration(hours: 1)),
    );
    expect((await store.list()).map((i) => i.input), ['earlier', 'later']);

    await store.resolve('rv_1', ruleId: null, reviewer: 'rk', at: t0);
    expect((await store.list(status: ReviewStatus.open)).map((i) => i.input), [
      'earlier',
    ]);
    expect(
      (await store.list(status: ReviewStatus.resolved)).map((i) => i.input),
      ['later'],
    );
  });

  test('resolve records rule, reviewer, note and time', () async {
    await store.add(input: 'x', reason: ReviewReason.noMatch, at: t0);
    final at = t0.add(const Duration(hours: 2));
    final r = (await store.resolve(
      'rv_1',
      ruleId: 'jeevan_pramaan.ppo_mismatch',
      reviewer: 'rk',
      note: 'new wording',
      at: at,
    ))!;
    expect(r.status, ReviewStatus.resolved);
    expect(r.resolvedRuleId, 'jeevan_pramaan.ppo_mismatch');
    expect(r.reviewer, 'rk');
    expect(r.note, 'new wording');
    expect(r.resolvedAt, at);
    expect((await store.get('rv_1'))!.toJson(), r.toJson());
  });

  test('unknown or malformed ids are null, not errors', () async {
    for (final id in ['rv_99', 'rv_x', '42', '']) {
      expect(await store.get(id), isNull, reason: id);
      expect(
        await store.resolve(id, ruleId: null, reviewer: 'rk', at: t0),
        isNull,
        reason: id,
      );
    }
  });
}
