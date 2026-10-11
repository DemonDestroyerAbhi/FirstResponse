import 'dart:convert';

import 'package:http/http.dart' as http;

/// A rulebook download: the raw bundle and its version tag.
class RulebookDownload {
  final String json;
  final String etag;

  const RulebookDownload(this.json, this.etag);
}

/// Talks to the API. Every call can fail (offline, server down); callers
/// treat failure as "carry on with what we have".
class ApiClient {
  final Uri baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 10);

  ApiClient(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  /// The current rulebook, or null when [etag] is already current.
  Future<RulebookDownload?> fetchRulebook({String? etag}) async {
    final res = await _client
        .get(baseUrl.resolve('/v1/rulebook'), headers: {'if-none-match': ?etag})
        .timeout(_timeout);
    if (res.statusCode == 304) return null;
    _check(res);
    final tag = res.headers['etag'];
    if (tag == null) throw const FormatException('Rulebook has no ETag');
    return RulebookDownload(res.body, tag);
  }

  /// Server-side diagnosis. When the server cannot match the message either,
  /// it queues it for review.
  Future<String> diagnose(String text, {String? portal}) async {
    final body = await _post('/v1/diagnose', {'text': text, 'portal': ?portal});
    return body['decision'] as String;
  }

  /// The user turned down every suggestion; queue the message for review.
  Future<void> reject(String text, {String? portal}) =>
      _post('/v1/diagnose/reject', {'text': text, 'portal': ?portal});

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object> body,
  ) async {
    final res = await _client
        .post(
          baseUrl.resolve(path),
          headers: {'content-type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(_timeout);
    _check(res);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static void _check(http.Response res) {
    if (res.statusCode >= 300) {
      throw http.ClientException('HTTP ${res.statusCode}', res.request?.url);
    }
  }
}
