import 'dart:async';
import 'dart:convert';
import 'dart:io' show stderr;

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'bot.dart';
import 'messages.dart';

class WhatsAppConfig {
  /// Chosen by us and entered in the Meta app dashboard; Meta echoes it when
  /// it verifies the webhook URL.
  final String verifyToken;

  /// The Meta app secret, used to check `X-Hub-Signature-256`.
  final String appSecret;

  const WhatsAppConfig({required this.verifyToken, required this.appSecret});
}

/// Sends replies. The Cloud API in production, a fake in tests.
abstract interface class WhatsAppSender {
  Future<void> send(String to, Outgoing message);
}

class CloudApiSender implements WhatsAppSender {
  final String accessToken;
  final String phoneNumberId;

  /// Graph API version. Meta retires old versions, so keep this current.
  final String graphVersion;
  final http.Client _client;

  CloudApiSender({
    required this.accessToken,
    required this.phoneNumberId,
    this.graphVersion = 'v23.0',
    http.Client? client,
  }) : _client = client ?? http.Client();

  @override
  Future<void> send(String to, Outgoing message) async {
    final res = await _client.post(
      Uri.https('graph.facebook.com', '/$graphVersion/$phoneNumberId/messages'),
      headers: {
        'authorization': 'Bearer $accessToken',
        'content-type': 'application/json',
      },
      body: jsonEncode(message.toJson(to)),
    );
    if (res.statusCode >= 300) {
      // The response names the problem; it does not echo the message.
      throw http.ClientException(
        'WhatsApp send failed: ${res.statusCode} ${res.body}',
      );
    }
  }
}

/// `GET` and `POST /webhooks/whatsapp`.
///
/// Meta expects a 200 within seconds and retries otherwise, so the webhook
/// acknowledges first and replies in the background.
class WhatsAppWebhook {
  final WhatsAppConfig config;
  final Bot bot;
  final WhatsAppSender sender;

  /// Insertion-ordered, so the oldest id is dropped first.
  final _seen = <String>{};
  final _pending = <Future<void>>{};

  WhatsAppWebhook({
    required this.config,
    required this.bot,
    required this.sender,
  });

  Handler get handler =>
      (Router()
            ..get('/', _verify)
            ..post('/', _receive))
          .call;

  /// Completes when every reply started so far has been sent. For tests and
  /// graceful shutdown.
  Future<void> idle() => Future.wait([..._pending]);

  /// Meta's subscription handshake: echo the challenge if the token matches.
  Response _verify(Request req) {
    final q = req.url.queryParameters;
    if (q['hub.mode'] == 'subscribe' &&
        q['hub.verify_token'] == config.verifyToken) {
      return Response.ok(q['hub.challenge'] ?? '');
    }
    return Response.forbidden('');
  }

  Future<Response> _receive(Request req) async {
    final raw = await req.read().expand((chunk) => chunk).toList();
    if (!_signedByMeta(raw, req.headers['x-hub-signature-256'])) {
      return Response.forbidden('');
    }
    final List<Incoming> messages;
    try {
      messages = Incoming.parseWebhook(
        jsonDecode(utf8.decode(raw)) as Map<String, dynamic>,
      );
    } catch (_) {
      // Signed but malformed: retrying will not help, so do not ask Meta to.
      stderr.writeln('whatsapp: unreadable webhook body');
      return Response.ok('');
    }
    for (final m in messages) {
      if (!_firstTime(m.id)) continue;
      late final Future<void> task;
      task = _reply(m).whenComplete(() => _pending.remove(task));
      _pending.add(task);
    }
    return Response.ok('');
  }

  Future<void> _reply(Incoming m) async {
    try {
      for (final out in await bot.handle(m)) {
        await sender.send(m.from, out);
      }
    } catch (e) {
      // No message text or phone number in logs.
      final why = e is http.ClientException ? e.message : '${e.runtimeType}';
      stderr.writeln('whatsapp: reply to ${m.id} failed: $why');
    }
  }

  /// Meta redelivers a message if our 200 was slow; answer each once.
  bool _firstTime(String id) {
    if (!_seen.add(id)) return false;
    if (_seen.length > 5000) _seen.remove(_seen.first);
    return true;
  }

  bool _signedByMeta(List<int> body, String? header) {
    if (header == null || !header.startsWith('sha256=')) return false;
    final expected =
        'sha256=${Hmac(sha256, utf8.encode(config.appSecret)).convert(body)}';
    if (expected.length != header.length) return false;
    var diff = 0;
    for (var i = 0; i < expected.length; i++) {
      diff |= expected.codeUnitAt(i) ^ header.codeUnitAt(i);
    }
    return diff == 0;
  }
}
