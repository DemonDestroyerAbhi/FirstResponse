// Runs the API.
//
//   PORT          Port to listen on (default 8080)
//   RULES_DIR     Path to the repo's rules/ folder (default: found upwards)
//   ADMIN_TOKEN   Bearer token for /v1/admin; admin routes are off without it
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
  final api = Api(
    engine: Engine(Rulebook.fromBundle(bundle)),
    bundle: bundle,
    reviews: InMemoryReviewStore(),
    adminToken: env['ADMIN_TOKEN'],
  );

  final handler = const Pipeline()
      .addMiddleware(_logRequests)
      .addHandler(api.handler);
  final port = int.parse(env['PORT'] ?? '8080');
  final server = await shelf_io.serve(handler, InternetAddress.anyIPv4, port);
  stdout.writeln(
    'API on :${server.port}, rulebook ${api.rulebookVersion}'
    '${api.adminToken == null ? ', admin disabled' : ''}',
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
