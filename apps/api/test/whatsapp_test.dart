import 'dart:convert';

import 'package:api/api.dart';
import 'package:core_rules/core_rules.dart';
import 'package:core_rules/io.dart';
import 'package:crypto/crypto.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

const user = '919800000001';

class FakeSender implements WhatsAppSender {
  final sent = <(String, Outgoing)>[];
  bool fail = false;

  @override
  Future<void> send(String to, Outgoing message) async {
    if (fail) throw StateError('network down');
    sent.add((to, message));
  }
}

void main() {
  final bundle = readBundle(findRulesDir());
  final engine = Engine(Rulebook.fromBundle(bundle));
  late InMemoryReviewStore reviews;
  late DateTime now;
  late Bot bot;
  var nextId = 0;

  setUp(() {
    reviews = InMemoryReviewStore();
    now = DateTime.utc(2026, 11, 23, 10);
    bot = Bot(
      engine: engine,
      reviews: reviews,
      sessions: InMemorySessionStore(),
      clock: () => now,
    );
  });

  Future<List<Outgoing>> say(String text) =>
      bot.handle(Incoming(id: 'm${nextId++}', from: user, text: text));
  Future<List<Outgoing>> tap(String id) =>
      bot.handle(Incoming(id: 'm${nextId++}', from: user, buttonId: id));

  group('bot', () {
    test('greets with the menu, in Hindi too', () async {
      for (final hello in ['Hi', 'MENU', 'नमस्ते']) {
        final [reply] = await say(hello);
        expect(reply, isA<ButtonsReply>());
        expect((reply as ButtonsReply).buttons.map((b) => b.id), [
          'menu:lc',
          'menu:explain',
        ]);
      }
      expect(await reviews.list(), isEmpty, reason: 'greetings are not queued');
    });

    test('a known error gets the fix in one message', () async {
      final [reply] = await say('Error 300: Biometric data did not match');
      final body = (reply as TextReply).body;
      expect(body, startsWith('*Fingerprint or iris did not match Aadhaar*'));
      expect(body, contains('*Aadhaar centre*:'));
      expect(body, contains('Not yet checked against the official source'));
      expect(body, contains('Not affiliated with any government body'));
    });

    test('asks to confirm a fuzzy match, then answers on Yes', () async {
      final [ask] = await say('aadhar not linkd with pension acount');
      final buttons = (ask as ButtonsReply).buttons;
      expect(buttons.map((b) => b.title), ['Yes', 'No']);
      expect(buttons.first.id, 'yes:jeevan_pramaan.aadhaar_not_seeded_pension');

      final [answer] = await tap(buttons.first.id);
      expect(
        (answer as TextReply).body,
        startsWith('*Aadhaar is not linked to the pension account*'),
      );
    });

    test('No to every candidate queues the message for review', () async {
      final [ask] = await say('aadhar not linkd with pension acount');
      var reply = ask;
      while (reply is ButtonsReply) {
        [reply] = await tap(reply.buttons.last.id);
      }
      expect((reply as TextReply).body, contains("I don't recognise"));
      final [item] = await reviews.list();
      expect(item.reason, ReviewReason.userRejected);
    });

    test('an old button cannot answer a newer question', () async {
      final [first] = await say('aadhar not linkd with pension acount');
      await say('Error 300'); // a new question replaces the old one
      final [reply] = await tap((first as ButtonsReply).buttons.first.id);
      expect((reply as TextReply).body, contains('expired'));
    });

    test('a question expires after 30 minutes', () async {
      final [ask] = await say('aadhar not linkd with pension acount');
      now = now.add(const Duration(minutes: 31));
      final [reply] = await tap((ask as ButtonsReply).buttons.first.id);
      expect((reply as TextReply).body, contains('expired'));
    });

    test('an unknown message is queued, masked', () async {
      final [reply] = await say('Server error for Aadhaar 1234 5678 9012');
      expect((reply as TextReply).body, contains("I don't recognise"));
      final [item] = await reviews.list();
      expect(item.input, 'Server error for Aadhaar XXXX XXXX 9012');
      expect(item.reason, ReviewReason.noMatch);
    });

    test('life certificate asks for the DOB and gives the window', () async {
      await tap('menu:lc');
      final [bad] = await say('sometime in 1960');
      expect((bad as TextReply).body, contains("couldn't read that date"));
      final [reply] = await say('05/05/1960');
      final body = (reply as TextReply).body;
      expect(body, contains('born 5 May 1960'));
      expect(body, contains('*1 Nov 2026* and *30 Nov 2026*'));
      expect(body, contains('*7 days left.*'));
      // The DOB is not kept: the next text is a new message to diagnose.
      final [next] = await say('Invalid PPO Number');
      expect(
        (next as TextReply).body,
        startsWith('*PPO number does not match*'),
      );
    });

    test('images and voice notes get a polite refusal', () async {
      final [reply] = await bot.handle(const Incoming(id: 'img', from: user));
      expect((reply as TextReply).body, contains('only read typed messages'));
    });
  });

  test('parseDate accepts common forms and rejects impossible dates', () {
    expect(parseDate('5-5-1960'), DateTime.utc(1960, 5, 5));
    expect(parseDate('05.05.1960'), DateTime.utc(1960, 5, 5));
    expect(parseDate('1960-05-05'), DateTime.utc(1960, 5, 5));
    expect(parseDate('31-02-1960'), isNull);
    expect(parseDate('05-05-60'), isNull);
  });

  group('webhook', () {
    const secret = 'app-secret';
    late FakeSender sender;
    late WhatsAppWebhook webhook;
    late Handler handler;

    setUp(() {
      sender = FakeSender();
      webhook = WhatsAppWebhook(
        config: const WhatsAppConfig(verifyToken: 'vt', appSecret: secret),
        bot: bot,
        sender: sender,
      );
      handler = Api(
        engine: engine,
        bundle: bundle,
        reviews: reviews,
        whatsapp: webhook,
      ).handler;
    });

    Map<String, Object?> payload(String id, String text) => {
      'object': 'whatsapp_business_account',
      'entry': [
        {
          'id': 'WABA',
          'changes': [
            {
              'field': 'messages',
              'value': {
                'messaging_product': 'whatsapp',
                'metadata': {'phone_number_id': 'PNID'},
                'messages': [
                  {
                    'from': user,
                    'id': id,
                    'timestamp': '1790000000',
                    'type': 'text',
                    'text': {'body': text},
                  },
                ],
                'statuses': [
                  {'id': 'old', 'status': 'delivered'},
                ],
              },
            },
          ],
        },
      ],
    };

    Future<Response> post(Object body, {String? signature}) async {
      final raw = utf8.encode(jsonEncode(body));
      return handler(
        Request(
          'POST',
          Uri.parse('http://localhost/webhooks/whatsapp'),
          body: raw,
          headers: {
            'x-hub-signature-256':
                signature ??
                'sha256=${Hmac(sha256, utf8.encode(secret)).convert(raw)}',
          },
        ),
      );
    }

    test('answers Meta\'s verification handshake', () async {
      Future<Response> verify(String token) async => handler(
        Request(
          'GET',
          Uri.parse(
            'http://localhost/webhooks/whatsapp?hub.mode=subscribe'
            '&hub.verify_token=$token&hub.challenge=12345',
          ),
        ),
      );
      final ok = await verify('vt');
      expect(ok.statusCode, 200);
      expect(await ok.readAsString(), '12345');
      expect((await verify('wrong')).statusCode, 403);
    });

    test('replies to a signed message, once even if redelivered', () async {
      final body = payload('wamid.1', 'Invalid PPO Number');
      expect((await post(body)).statusCode, 200);
      expect((await post(body)).statusCode, 200);
      await webhook.idle();
      expect(sender.sent, hasLength(1));
      final (to, message) = sender.sent.single;
      expect(to, user);
      expect(message.toJson(to)['type'], 'text');
    });

    test('rejects unsigned or wrongly signed requests', () async {
      final body = payload('wamid.2', 'Invalid PPO Number');
      expect((await post(body, signature: 'sha256=00')).statusCode, 403);
      expect((await post(body, signature: '')).statusCode, 403);
      await webhook.idle();
      expect(sender.sent, isEmpty);
    });

    test('a failed send is logged, not retried by Meta', () async {
      sender.fail = true;
      expect((await post(payload('wamid.3', 'Hi'))).statusCode, 200);
      await webhook.idle();
    });

    test('is a 404 when not configured', () async {
      final off = Api(engine: engine, bundle: bundle, reviews: reviews);
      final res = await off.handler(
        Request('GET', Uri.parse('http://localhost/webhooks/whatsapp')),
      );
      expect(res.statusCode, 404);
    });
  });

  test('button replies serialise to the Cloud API shape', () {
    const reply = ButtonsReply('Pick one', [
      ReplyButton('a', 'A very long title over twenty'),
    ]);
    final json = reply.toJson(user);
    final interactive = json['interactive'] as Map;
    final button = (interactive['action'] as Map)['buttons'][0] as Map;
    expect(json['to'], user);
    expect(interactive['type'], 'button');
    expect((button['reply'] as Map)['title'], hasLength(20));
    expect(() => const ButtonsReply('x', []).toJson(user), throwsArgumentError);
  });
}
