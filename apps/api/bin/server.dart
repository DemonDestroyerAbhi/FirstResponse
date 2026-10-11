// Runs the API.
//
//   PORT          Port to listen on (default 8080)
//   RULES_DIR     Path to the repo's rules/ folder (default: found upwards)
//   ADMIN_TOKEN   Bearer token for /v1/admin; admin routes are off without it
//
// WhatsApp, all four or none (the webhook is off without them):
//   WHATSAPP_VERIFY_TOKEN      Our token, entered in the Meta dashboard
//   WHATSAPP_APP_SECRET        Meta app secret, for webhook signatures
//   WHATSAPP_ACCESS_TOKEN      System-user token for sending
//   WHATSAPP_PHONE_NUMBER_ID   Business phone number id
//   WHATSAPP_GRAPH_VERSION     Optional, default in CloudApiSender
import 'dart:io';

import 'package:api/api.dart';
import 'package:core_rules/core_rules.dart';
import 'package:core_rules/io.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

Future<void> main() async {
  final env = Platform.environment;
  final rulesDir = env['RULES_DIR'] != null
      ? Directory(env['RULES_DIR']!)
      : findRulesDir();
  final bundle = readBundle(rulesDir);
  final engine = Engine(Rulebook.fromBundle(bundle));
  final reviews = InMemoryReviewStore();
  final api = Api(
    engine: engine,
    bundle: bundle,
    reviews: reviews,
    adminToken: env['ADMIN_TOKEN'],
    whatsapp: _whatsapp(env, engine, reviews),
  );

  final handler = const Pipeline()
      .addMiddleware(_logRequests)
      .addHandler(api.handler);
  final port = int.parse(env['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'API on :${server.port}, rulebook ${api.rulebookVersion}'
    '${api.adminToken == null ? ', admin disabled' : ''}'
    '${api.whatsapp == null ? ', WhatsApp disabled' : ''}',
  );
}

/// Logs method, path, status and time only. Query strings (a date of birth)
/// and bodies (user text) never reach the logs.
Handler _logRequests(Handler inner) => (req) async {
  final watch = Stopwatch()..start();
  final res = await inner(req);
  stdout.writeln(
    '${DateTime.now().toUtc().toIso8601String()} ${req.method} '
    '/${req.url.path} ${res.statusCode} ${watch.elapsedMilliseconds}ms',
  );
  return res;
};

WhatsAppWebhook? _whatsapp(
  Map<String, String> env,
  Engine engine,
  ReviewStore reviews,
) {
  const keys = [
    'WHATSAPP_VERIFY_TOKEN',
    'WHATSAPP_APP_SECRET',
    'WHATSAPP_ACCESS_TOKEN',
    'WHATSAPP_PHONE_NUMBER_ID',
  ];
  final set = keys.where((k) => env[k]?.isNotEmpty ?? false).toList();
  if (set.isEmpty) return null;
  if (set.length < keys.length) {
    stderr.writeln(
      'WhatsApp needs all of ${keys.join(', ')}; '
      'missing ${keys.where((k) => !set.contains(k)).join(', ')}',
    );
    exit(78);
  }
  return WhatsAppWebhook(
    config: WhatsAppConfig(
      verifyToken: env['WHATSAPP_VERIFY_TOKEN']!,
      appSecret: env['WHATSAPP_APP_SECRET']!,
    ),
    bot: Bot(
      engine: engine,
      reviews: reviews,
      sessions: InMemorySessionStore(),
    ),
    sender: CloudApiSender(
      accessToken: env['WHATSAPP_ACCESS_TOKEN']!,
      phoneNumberId: env['WHATSAPP_PHONE_NUMBER_ID']!,
      graphVersion: env['WHATSAPP_GRAPH_VERSION'] ?? 'v23.0',
    ),
  );
}
