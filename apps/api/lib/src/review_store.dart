/// The human review queue: inputs the rulebook could not answer.
///
/// Each resolved item becomes a golden case, and usually a new pattern or
/// rule, so the queue is how the rulebook grows.
library;

enum ReviewReason {
  /// Nothing matched, or only below the confirm threshold.
  noMatch,

  /// The user said no to every candidate offered.
  userRejected,
}

enum ReviewStatus { open, resolved }

class ReviewItem {
  final String id;
  final DateTime createdAt;

  /// Already masked by the engine.
  final String input;
  final String? portal;
  final String? code;
  final ReviewReason reason;

  /// Rule ids the engine considered, best first.
  final List<String> candidates;

  final ReviewStatus status;

  /// The rule a reviewer says this input should map to; null means no
  /// existing rule fits and a new one is needed.
  final String? resolvedRuleId;
  final String? note;
  final String? reviewer;
  final DateTime? resolvedAt;

  const ReviewItem({
    required this.id,
    required this.createdAt,
    required this.input,
    required this.reason,
    this.portal,
    this.code,
    this.candidates = const [],
    this.status = ReviewStatus.open,
    this.resolvedRuleId,
    this.note,
    this.reviewer,
    this.resolvedAt,
  });

  ReviewItem resolved({
    required String? ruleId,
    required String reviewer,
    required DateTime at,
    String? note,
  }) => ReviewItem(
    id: id,
    createdAt: createdAt,
    input: input,
    reason: reason,
    portal: portal,
    code: code,
    candidates: candidates,
    status: ReviewStatus.resolved,
    resolvedRuleId: ruleId,
    note: note,
    reviewer: reviewer,
    resolvedAt: at,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'input': input,
    'portal': portal,
    'code': code,
    'reason': reason.name,
    'candidates': candidates,
    'status': status.name,
    'resolvedRuleId': resolvedRuleId,
    'note': note,
    'reviewer': reviewer,
    'resolvedAt': resolvedAt?.toUtc().toIso8601String(),
  };
}

/// Storage for the queue. In-memory for now; Postgres replaces it without
/// touching the routes.
abstract interface class ReviewStore {
  Future<ReviewItem> add({
    required String input,
    required ReviewReason reason,
    required DateTime at,
    String? portal,
    String? code,
    List<String> candidates,
  });

  Future<ReviewItem?> get(String id);

  /// Oldest first, so the 24-hour promise is kept in order.
  Future<List<ReviewItem>> list({ReviewStatus? status});

  Future<ReviewItem?> resolve(
    String id, {
    required String? ruleId,
    required String reviewer,
    required DateTime at,
    String? note,
  });
}

class InMemoryReviewStore implements ReviewStore {
  final _items = <String, ReviewItem>{};
  var _next = 1;

  @override
  Future<ReviewItem> add({
    required String input,
    required ReviewReason reason,
    required DateTime at,
    String? portal,
    String? code,
    List<String> candidates = const [],
  }) async {
    final item = ReviewItem(
      id: 'rv_${_next++}',
      createdAt: at,
      input: input,
      reason: reason,
      portal: portal,
      code: code,
      candidates: candidates,
    );
    return _items[item.id] = item;
  }

  @override
  Future<ReviewItem?> get(String id) async => _items[id];

  @override
  Future<List<ReviewItem>> list({ReviewStatus? status}) async => [
    for (final i in _items.values)
      if (status == null || i.status == status) i,
  ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  @override
  Future<ReviewItem?> resolve(
    String id, {
    required String? ruleId,
    required String reviewer,
    required DateTime at,
    String? note,
  }) async {
    final item = _items[id];
    if (item == null) return null;
    return _items[id] = item.resolved(
      ruleId: ruleId,
      reviewer: reviewer,
      at: at,
      note: note,
    );
  }
}
