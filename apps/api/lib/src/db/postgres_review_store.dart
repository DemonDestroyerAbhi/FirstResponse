import 'package:postgres/postgres.dart' as pg;

import '../review_store.dart';

/// The review queue in Postgres. Ids keep the `rv_<n>` form the in-memory
/// store uses, so clients see no difference.
class PostgresReviewStore implements ReviewStore {
  final pg.Session db;

  /// A [pg.Pool] in the server; any [pg.Session] works.
  PostgresReviewStore(this.db);

  static const _columns =
      'id, created_at, input, portal, code, reason, candidates, status, '
      'resolved_rule_id, note, reviewer, resolved_at';

  @override
  Future<ReviewItem> add({
    required String input,
    required ReviewReason reason,
    required DateTime at,
    String? portal,
    String? code,
    List<String> candidates = const [],
  }) async {
    final rows = await db.execute(
      pg.Sql.named('''
        INSERT INTO review_items
          (created_at, input, portal, code, reason, candidates)
        VALUES (@at, @input, @portal, @code, @reason, @candidates)
        RETURNING $_columns'''),
      parameters: {
        'at': pg.TypedValue(pg.Type.timestampTz, at),
        'input': input,
        'portal': pg.TypedValue(pg.Type.text, portal),
        'code': pg.TypedValue(pg.Type.text, code),
        'reason': reason.name,
        'candidates': pg.TypedValue(pg.Type.textArray, candidates),
      },
    );
    return _item(rows.single);
  }

  @override
  Future<ReviewItem?> get(String id) async {
    final n = _number(id);
    if (n == null) return null;
    final rows = await db.execute(
      pg.Sql.named('SELECT $_columns FROM review_items WHERE id = @id'),
      parameters: {'id': n},
    );
    return rows.isEmpty ? null : _item(rows.single);
  }

  @override
  Future<List<ReviewItem>> list({ReviewStatus? status}) async {
    final rows = await db.execute(
      pg.Sql.named('''
        SELECT $_columns FROM review_items
        WHERE @status::text IS NULL OR status = @status::text
        ORDER BY created_at, id'''),
      parameters: {'status': pg.TypedValue(pg.Type.text, status?.name)},
    );
    return rows.map(_item).toList();
  }

  @override
  Future<ReviewItem?> resolve(
    String id, {
    required String? ruleId,
    required String reviewer,
    required DateTime at,
    String? note,
  }) async {
    final n = _number(id);
    if (n == null) return null;
    final rows = await db.execute(
      pg.Sql.named('''
        UPDATE review_items
        SET status = 'resolved', resolved_rule_id = @rule, reviewer = @reviewer,
            note = @note, resolved_at = @at
        WHERE id = @id
        RETURNING $_columns'''),
      parameters: {
        'id': n,
        'rule': pg.TypedValue(pg.Type.text, ruleId),
        'reviewer': reviewer,
        'note': pg.TypedValue(pg.Type.text, note),
        'at': pg.TypedValue(pg.Type.timestampTz, at),
      },
    );
    return rows.isEmpty ? null : _item(rows.single);
  }

  static int? _number(String id) =>
      id.startsWith('rv_') ? int.tryParse(id.substring(3)) : null;

  static ReviewItem _item(pg.ResultRow row) {
    final r = row.toColumnMap();
    return ReviewItem(
      id: 'rv_${r['id']}',
      createdAt: r['created_at'] as DateTime,
      input: r['input'] as String,
      portal: r['portal'] as String?,
      code: r['code'] as String?,
      reason: ReviewReason.values.byName(r['reason'] as String),
      candidates: (r['candidates'] as List).cast<String>(),
      status: ReviewStatus.values.byName(r['status'] as String),
      resolvedRuleId: r['resolved_rule_id'] as String?,
      note: r['note'] as String?,
      reviewer: r['reviewer'] as String?,
      resolvedAt: r['resolved_at'] as DateTime?,
    );
  }
}
