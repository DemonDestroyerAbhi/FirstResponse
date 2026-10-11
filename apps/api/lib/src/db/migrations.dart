import 'package:postgres/postgres.dart';

/// Schema changes, applied in order and never edited once shipped: add a new
/// entry instead. The index + 1 is the schema version.
const migrations = <String>[
  // 1: the review queue.
  '''
  CREATE TABLE review_items (
    id               bigserial PRIMARY KEY,
    created_at       timestamptz NOT NULL,
    input            text NOT NULL,
    portal           text,
    code             text,
    reason           text NOT NULL CHECK (reason IN ('noMatch', 'userRejected')),
    candidates       text[] NOT NULL DEFAULT '{}',
    status           text NOT NULL DEFAULT 'open'
                       CHECK (status IN ('open', 'resolved')),
    resolved_rule_id text,
    note             text,
    reviewer         text,
    resolved_at      timestamptz
  );
  CREATE INDEX review_items_open ON review_items (created_at)
    WHERE status = 'open';
  ''',
];

/// Arbitrary constant; any server starting at the same time waits on it.
const _lockId = 727001;

/// Applies pending [migrations] in one transaction and returns the version.
///
/// Safe to call from every instance at startup: an advisory lock makes a
/// second instance wait, then find nothing left to do.
Future<int> migrate(SessionExecutor db) => db.runTx((tx) async {
  await tx.execute('SELECT pg_advisory_xact_lock($_lockId)');
  await tx.execute('''
    CREATE TABLE IF NOT EXISTS schema_migrations (
      version    int PRIMARY KEY,
      applied_at timestamptz NOT NULL DEFAULT now()
    )''');
  final rows = await tx.execute(
    'SELECT coalesce(max(version), 0) FROM schema_migrations',
  );
  final current = rows.single.single! as int;
  if (current > migrations.length) {
    throw StateError(
      'Database is at schema $current but this build knows only '
      '${migrations.length}; deploy a newer build.',
    );
  }
  for (var v = current + 1; v <= migrations.length; v++) {
    // Multiple statements need the simple query protocol.
    await tx.execute(migrations[v - 1], queryMode: QueryMode.simple);
    await tx.execute(
      Sql.named('INSERT INTO schema_migrations (version) VALUES (@v)'),
      parameters: {'v': v},
    );
  }
  return migrations.length;
});
