import 'package:core_rules/core_rules.dart';

import '../review_store.dart';
import 'messages.dart';
import 'sessions.dart';

/// The WhatsApp conversation, with no HTTP in it: one incoming message in,
/// replies out. Same engine and review queue as the API, so the bot never
/// gives an answer the app would not.
class Bot {
  final Engine engine;
  final ReviewStore reviews;
  final SessionStore sessions;
  final DateTime Function() clock;

  Bot({
    required this.engine,
    required this.reviews,
    required this.sessions,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  Rulebook get _book => engine.rulebook;

  static const _menuWords = {
    'hi', 'hii', 'hello', 'hey', 'menu', 'start', 'help', 'namaste', //
    'namaskar', 'नमस्ते', 'नमस्कार', 'मेनू',
  };

  Future<List<Outgoing>> handle(Incoming m) async {
    final now = clock();
    final session = sessions.get(m.from, now);

    if (m.buttonId case final id?) return _button(m.from, id, session, now);

    final text = m.text?.trim();
    if (text == null) {
      return const [
        TextReply(
          "I can only read typed messages for now. Please type the error "
          'exactly as it appears on the screen.',
        ),
      ];
    }
    if (text.isEmpty || _menuWords.contains(text.toLowerCase())) {
      sessions.clear(m.from);
      return [_menu];
    }
    if (session is AwaitingDob) return _dob(m.from, text, now);
    return _diagnose(m.from, text, now);
  }

  Future<List<Outgoing>> _button(
    String user,
    String id,
    Session? session,
    DateTime now,
  ) async {
    switch (id.split(':')) {
      case ['menu', 'lc']:
        sessions.put(user, AwaitingDob(now));
        return const [
          TextReply("Send the pensioner's date of birth, like *05-05-1960*."),
        ];
      case ['menu', 'explain']:
        sessions.clear(user);
        return const [
          TextReply(
            'Type the error or rejection message exactly as it appears on '
            'the screen or in the SMS.',
          ),
        ];
      case [final answer, final ruleId] when answer == 'yes' || answer == 'no':
        // Old buttons stay tappable in the chat; only the latest one counts.
        if (session is! Confirming || session.current != ruleId) {
          return const [
            TextReply(
              'That question has expired. Please send the message again.',
            ),
          ];
        }
        return answer == 'yes'
            ? _confirmed(user, session, now)
            : _rejected(user, session, now);
      default:
        return [_menu];
    }
  }

  Future<List<Outgoing>> _diagnose(
    String user,
    String text,
    DateTime now,
  ) async {
    final d = engine.diagnose(text, now: now);
    switch (d.decision) {
      case Decision.answer:
        sessions.clear(user);
        return [TextReply(answerText(d, _book))];
      case Decision.confirm:
        final s = Confirming(
          now,
          input: d.input,
          candidates: [?d.rule?.id, ...d.alternatives.map((m) => m.rule.id)],
        );
        sessions.put(user, s);
        return [_ask(s)];
      case Decision.review:
        sessions.clear(user);
        await reviews.add(
          input: d.input,
          reason: ReviewReason.noMatch,
          at: now,
          candidates: [?d.rule?.id, ...d.alternatives.map((m) => m.rule.id)],
        );
        return const [TextReply(_notRecognised)];
    }
  }

  Future<List<Outgoing>> _confirmed(
    String user,
    Confirming s,
    DateTime now,
  ) async {
    sessions.clear(user);
    final d = engine.diagnose(s.input, now: now);
    final picked = [
      ?d.match,
      ...d.alternatives,
    ].where((m) => m.rule.id == s.current).firstOrNull;
    // Only if the rulebook changed between the question and the tap.
    if (picked == null) {
      return const [
        TextReply('That question has expired. Please send the message again.'),
      ];
    }
    return [TextReply(answerText(engine.confirm(d, picked, now: now), _book))];
  }

  Future<List<Outgoing>> _rejected(
    String user,
    Confirming s,
    DateTime now,
  ) async {
    if (s.index + 1 < s.candidates.length) {
      final next = Confirming(
        now,
        input: s.input,
        candidates: s.candidates,
        index: s.index + 1,
      );
      sessions.put(user, next);
      return [_ask(next)];
    }
    sessions.clear(user);
    await reviews.add(
      input: s.input,
      reason: ReviewReason.userRejected,
      at: now,
      candidates: s.candidates,
    );
    return const [TextReply(_notRecognised)];
  }

  List<Outgoing> _dob(String user, String text, DateTime now) {
    final dob = parseDate(text);
    if (dob == null || dob.isAfter(now) || dob.year < 1900) {
      return const [
        TextReply(
          "I couldn't read that date. Send it like *05-05-1960*, or send "
          '*menu* to start over.',
        ),
      ];
    }
    sessions.clear(user);
    return [TextReply(lifeCertificateText(dob, now))];
  }

  Outgoing _ask(Confirming s) {
    final rule = _book.rule(s.current)!;
    return ButtonsReply(
      'Is this your problem?\n\n*${rule.title.of('en')}*\n'
      '${rule.explain.of('en')}',
      [
        ReplyButton('yes:${rule.id}', 'Yes'),
        ReplyButton('no:${rule.id}', 'No'),
      ],
    );
  }

  static const _menu = ButtonsReply(
    'Hello! I explain government rejections and errors, and what to fix.\n\n'
    '_${_disclaimer}_',
    [
      ReplyButton('menu:lc', 'Life certificate'),
      ReplyButton('menu:explain', 'Explain an error'),
    ],
  );

  static const _notRecognised =
      "I don't recognise this message yet, so I've noted it for our team to "
      'add. Check that it is copied exactly, or ask at the office that '
      'showed it.';
}

const _disclaimer =
    'Not affiliated with any government body. Always verify with the office '
    'before acting.';

/// A diagnosis as one WhatsApp message.
String answerText(Diagnosis d, Rulebook book) {
  final rule = d.rule!;
  final out = StringBuffer()
    ..writeln('*${rule.title.of('en')}*')
    ..writeln(rule.explain.of('en'));
  if (d.sequence.length > 1) {
    out
      ..writeln()
      ..writeln('*Order to fix in*');
    for (final (i, s) in d.sequence.indexed) {
      out.writeln(
        '${i + 1}. ${s.kind == StepKind.fix ? 'Correct' : 'Update'} '
        '${s.record.name.of('en')}',
      );
    }
  }
  out
    ..writeln()
    ..writeln('*What to do*');
  for (final (i, f) in rule.fix.indexed) {
    out.writeln('${i + 1}. *${book.label(f.actor)}*: ${f.action.of('en')}');
    if (f.form case final form?) out.writeln('   Form: ${book.label(form)}');
    if (f.bring.isNotEmpty) {
      out.writeln('   Bring: ${f.bring.map(book.label).join(', ')}');
    }
  }
  if (d.freshness != Freshness.current) {
    out
      ..writeln()
      ..writeln(
        d.freshness == Freshness.stale
            ? '⚠️ _The rules may have changed since we last checked this._'
            : '⚠️ _Not yet checked against the official source._',
      );
  }
  out
    ..writeln()
    ..writeln('Source: ${rule.sources.map((s) => s.url).join(' , ')}')
    ..write('_${_disclaimer}_');
  return out.toString();
}

String lifeCertificateText(DateTime dob, DateTime today) {
  final w = currentWindow(dob, today);
  final left = w.daysLeft(today);
  final status = w.contains(today)
      ? (left == 0 ? '*Today is the last day.*' : '*$left days left.*')
      : 'Submission opens on *${formatDay(w.opens)}*.';
  return 'Life certificate for a pensioner born ${formatDay(dob)}:\n\n'
      'Submit between *${formatDay(w.opens)}* and *${formatDay(w.closes)}*.\n'
      '$status\n\n'
      'These are the central government dates. State pensions can differ; '
      'check with the bank or treasury that pays the pension.\n\n'
      'If the certificate is rejected, send me the rejection message.';
}

/// Reads `05-05-1960`, `5/5/1960`, `05.05.1960` or `1960-05-05`.
/// Returns null for anything else, including impossible dates.
DateTime? parseDate(String text) {
  final t = text.trim();
  final dmy = RegExp(r'^(\d{1,2})[-/. ](\d{1,2})[-/. ](\d{4})$').firstMatch(t);
  final ymd = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(t);
  final (y, mo, d) = dmy != null
      ? (int.parse(dmy[3]!), int.parse(dmy[2]!), int.parse(dmy[1]!))
      : ymd != null
      ? (int.parse(ymd[1]!), int.parse(ymd[2]!), int.parse(ymd[3]!))
      : (0, 0, 0);
  if (y == 0) return null;
  final date = DateTime.utc(y, mo, d);
  // DateTime rolls 31-02 over into March; reject instead.
  return date.month == mo && date.day == d ? date : null;
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String formatDay(DateTime d) => '${d.day} ${_months[d.month - 1]} ${d.year}';
