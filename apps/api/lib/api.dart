/// HTTP API shared by the app, the web consoles, the WhatsApp bot and B2B
/// partners. Every answer comes from the rules engine; nothing here decides.
library;

import 'dart:convert';

import 'package:core_rules/core_rules.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'src/review_store.dart';
import 'src/serialize.dart';
import 'src/whatsapp/webhook.dart';

export 'src/db/migrations.dart';
export 'src/db/postgres_review_store.dart';
export 'src/review_store.dart';
export 'src/whatsapp/bot.dart';
export 'src/whatsapp/messages.dart';
export 'src/whatsapp/sessions.dart';
export 'src/whatsapp/webhook.dart';

/// Longest message we accept; real portal remarks are far shorter.
const maxInputLength = 2000;

class Api {
  final Engine engine;
  final ReviewStore reviews;

  /// The rulebook as served to apps for offline use (`rules bundle` output).
  final Map<String, dynamic> bundle;

  /// Bearer token for `/v1/admin`. Admin routes are off when null.
  final String? adminToken;

  final DateTime Function() clock;

  /// Mounted at `/webhooks/whatsapp` when configured.
  final WhatsAppWebhook? whatsapp;

  /// Browser origins (e.g. the static site) allowed to call the public
  /// routes. Admin and webhook routes are never open to browsers.
  final Set<String> corsOrigins;

  Api({
    required this.engine,
    required this.bundle,
    required this.reviews,
    this.adminToken,
    this.whatsapp,
    this.corsOrigins = const {},
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  Rulebook get _book => engine.rulebook;

  /// Changes whenever any pack's version changes, so apps re-download only
  /// when there is something new.
  String get rulebookVersion => _book.version;

  Handler get handler {
    final admin = Router()
      ..get('/review', _listReview)
      ..post('/review/<id>/resolve', _resolveReview)
      ..get('/review/golden', _goldenFromReview);

    final router = Router(notFoundHandler: (_) => _error(404, 'Not found'))
      ..get('/healthz', _health)
      ..get('/v1/rulebook', _rulebook)
      ..post('/v1/diagnose', _diagnose)
      ..post('/v1/diagnose/confirm', _confirm)
      ..post('/v1/diagnose/reject', _reject)
      ..get('/v1/life-certificate', _lifeCertificate)
      ..mount('/webhooks/whatsapp', whatsapp?.handler ?? _disabled)
      ..mount(
        '/v1/admin/',
        const Pipeline().addMiddleware(_requireAdmin).addHandler(admin.call),
      );

    return const Pipeline()
        .addMiddleware(_cors)
        .addMiddleware(_errors)
        .addHandler(router.call);
  }

  static bool _isPublic(String path) =>
      path.startsWith('v1/') && !path.startsWith('v1/admin');

  Handler _cors(Handler inner) => (req) async {
    final origin = req.headers['origin'];
    if (origin == null ||
        !corsOrigins.contains(origin) ||
        !_isPublic(req.url.path)) {
      return inner(req);
    }
    final headers = {'access-control-allow-origin': origin, 'vary': 'Origin'};
    if (req.method == 'OPTIONS') {
      return Response(
        204,
        headers: {
          ...headers,
          'access-control-allow-methods': 'GET, POST',
          'access-control-allow-headers': 'content-type',
          'access-control-max-age': '86400',
        },
      );
    }
    return (await inner(req)).change(headers: headers);
  };

  static Response _disabled(Request _) => _error(404, 'Not configured');

  Response _health(Request _) =>
      _json({'ok': true, 'rulebookVersion': rulebookVersion});

  Response _rulebook(Request req) {
    final etag = '"$rulebookVersion"';
    if (req.headers['if-none-match'] == etag) {
      return Response.notModified(headers: {'etag': etag});
    }
    return _json(bundle, headers: {'etag': etag});
  }

  Future<Response> _diagnose(Request req) async {
    final q = await _query(req);
    final d = engine.diagnose(
      q.text,
      portal: q.portal,
      code: q.code,
      now: clock(),
    );
    String? reviewId;
    if (d.decision == Decision.review) {
      reviewId = (await reviews.add(
        input: d.input,
        reason: ReviewReason.noMatch,
        at: clock(),
        portal: q.portal,
        code: q.code,
        candidates: [?d.rule?.id, ...d.alternatives.map((m) => m.rule.id)],
      )).id;
    }
    return _json(diagnosisJson(d, _book, lang: q.lang, reviewId: reviewId));
  }

  /// The user picked one of the candidates offered for a `confirm` decision.
  Future<Response> _confirm(Request req) async {
    final q = await _query(req);
    final ruleId = q.body['ruleId'];
    if (ruleId is! String) throw const _BadRequest('ruleId is required');
    final d = engine.diagnose(
      q.text,
      portal: q.portal,
      code: q.code,
      now: clock(),
    );
    // Only a rule the engine itself offered can be confirmed, so a client
    // cannot attach an arbitrary rule to an input.
    final picked = [
      ?d.match,
      ...d.alternatives,
    ].where((m) => m.rule.id == ruleId).firstOrNull;
    if (picked == null) {
      return _error(422, 'Rule $ruleId was not offered for this input');
    }
    return _json(
      diagnosisJson(
        engine.confirm(d, picked, now: clock()),
        _book,
        lang: q.lang,
      ),
    );
  }

  /// The user said none of the candidates fit.
  Future<Response> _reject(Request req) async {
    final q = await _query(req);
    final d = engine.diagnose(
      q.text,
      portal: q.portal,
      code: q.code,
      now: clock(),
    );
    final item = await reviews.add(
      input: d.input,
      reason: ReviewReason.userRejected,
      at: clock(),
      portal: q.portal,
      code: q.code,
      candidates: [?d.rule?.id, ...d.alternatives.map((m) => m.rule.id)],
    );
    return _json({'reviewId': item.id}, status: 201);
  }

  Response _lifeCertificate(Request req) {
    final dob = DateTime.tryParse(req.url.queryParameters['dob'] ?? '');
    if (dob == null) {
      throw const _BadRequest('dob is required, as YYYY-MM-DD');
    }
    final today = clock();
    final w = currentWindow(dob, today);
    return _json({
      'opens': isoDate(w.opens),
      'closes': isoDate(w.closes),
      'open': w.contains(today),
      'daysLeft': w.daysLeft(today),
      'reminders': [
        for (final r in remindersFor(w, today))
          {
            'date': isoDate(r.date),
            'kind': r.kind.name,
            'daysLeft': r.daysLeft,
          },
      ],
    });
  }

  Future<Response> _listReview(Request req) async {
    final status = req.url.queryParameters['status'];
    final items = await reviews.list(
      status: status == null ? null : _enum(ReviewStatus.values, status),
    );
    return _json({
      'items': [for (final i in items) i.toJson()],
    });
  }

  Future<Response> _resolveReview(Request req, String id) async {
    final body = await _body(req);
    final ruleId = body['ruleId'];
    final reviewer = body['reviewer'];
    if (ruleId != null && (ruleId is! String || _book.rule(ruleId) == null)) {
      throw _BadRequest('Unknown rule $ruleId; send null if none fits');
    }
    if (reviewer is! String || reviewer.trim().isEmpty) {
      throw const _BadRequest('reviewer is required');
    }
    final item = await reviews.resolve(
      id,
      ruleId: ruleId as String?,
      reviewer: reviewer.trim(),
      note: body['note'] as String?,
      at: clock(),
    );
    if (item == null) return _error(404, 'No review item $id');
    return _json(item.toJson());
  }

  /// Resolved items in the golden-case format, ready to paste into a pack's
  /// `golden/` folder. Most will fail until the rule gains a pattern for
  /// them, which is the point.
  Future<Response> _goldenFromReview(Request req) async {
    final items = await reviews.list(status: ReviewStatus.resolved);
    return _json({
      'cases': [
        for (final i in items)
          {
            'input': i.input,
            'code': ?i.code,
            'expect': {
              'rule': i.resolvedRuleId,
              'decision': i.resolvedRuleId == null ? 'review' : 'answer',
            },
            'fromReview': i.id,
          },
      ],
    });
  }

  Handler _requireAdmin(Handler inner) => (req) {
    final token = adminToken;
    if (token == null) return _error(403, 'Admin API is disabled');
    if (!_equalConstantTime(
      req.headers['authorization'] ?? '',
      'Bearer $token',
    )) {
      return _error(401, 'Admin token required');
    }
    return inner(req);
  };

  /// Turns bad input into 400s. Anything else is a 500 with no detail, so
  /// user text never leaks into error responses.
  Handler _errors(Handler inner) => (req) async {
    try {
      return await inner(req);
    } on _BadRequest catch (e) {
      return _error(400, e.message);
    }
  };

  Future<_Query> _query(Request req) async {
    final body = await _body(req);
    final text = body['text'];
    if (text is! String || text.trim().isEmpty) {
      throw const _BadRequest('text is required');
    }
    if (text.length > maxInputLength) {
      throw const _BadRequest('text is longer than $maxInputLength characters');
    }
    String? opt(String key) {
      final v = body[key];
      if (v != null && v is! String) throw _BadRequest('$key must be a string');
      return v as String?;
    }

    return _Query(
      body,
      text,
      portal: opt('portal'),
      code: opt('code'),
      lang: opt('lang') ?? 'en',
    );
  }

  static Future<Map<String, dynamic>> _body(Request req) async {
    try {
      final json = jsonDecode(await req.readAsString());
      if (json is Map<String, dynamic>) return json;
    } on FormatException {
      // Fall through.
    }
    throw const _BadRequest('Body must be a JSON object');
  }

  static T _enum<T extends Enum>(List<T> values, String name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    throw _BadRequest(
      'Expected one of ${values.map((v) => v.name).join(', ')}',
    );
  }
}

class _Query {
  final Map<String, dynamic> body;
  final String text;
  final String? portal;
  final String? code;
  final String lang;

  const _Query(
    this.body,
    this.text, {
    this.portal,
    this.code,
    required this.lang,
  });
}

class _BadRequest implements Exception {
  final String message;
  const _BadRequest(this.message);
}

const _jsonType = {'content-type': 'application/json; charset=utf-8'};

Response _json(
  Object body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode(body),
  headers: {..._jsonType, ...headers},
);

Response _error(int status, String message) =>
    _json({'error': message}, status: status);

bool _equalConstantTime(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}
