/// WhatsApp Cloud API message shapes, reduced to what the bot uses.
library;

/// A message from a user, parsed from a webhook.
class Incoming {
  /// WhatsApp message id, used to drop Meta's retries.
  final String id;

  /// The user's WhatsApp number. Personal data: never logged.
  final String from;

  /// Typed text, when the user typed something.
  final String? text;

  /// Reply button id, when the user tapped a button.
  final String? buttonId;

  const Incoming({
    required this.id,
    required this.from,
    this.text,
    this.buttonId,
  });

  /// Every user message in a webhook body. Delivery statuses and other
  /// events are skipped. Types the bot cannot read yet (images, voice)
  /// come through with neither [text] nor [buttonId].
  static List<Incoming> parseWebhook(Map<String, dynamic> body) => [
    for (final entry in body['entry'] as List? ?? const [])
      for (final change in (entry as Map)['changes'] as List? ?? const [])
        if ((change as Map)['field'] == 'messages')
          for (final m
              in (change['value'] as Map)['messages'] as List? ?? const [])
            _parse(m as Map<String, dynamic>),
  ];

  static Incoming _parse(Map<String, dynamic> m) {
    final interactive = m['interactive'] as Map<String, dynamic>?;
    final reply =
        (interactive?['button_reply'] ?? interactive?['list_reply'])
            as Map<String, dynamic>?;
    return Incoming(
      id: m['id'] as String,
      from: m['from'] as String,
      text: m['type'] == 'text' ? (m['text'] as Map)['body'] as String? : null,
      buttonId: reply?['id'] as String?,
    );
  }
}

/// A reply from the bot.
sealed class Outgoing {
  const Outgoing();

  /// The Cloud API `/messages` request body.
  Map<String, Object?> toJson(String to);
}

class TextReply extends Outgoing {
  /// WhatsApp formatting: `*bold*`, `_italic_`. At most 4096 characters.
  final String body;

  const TextReply(this.body);

  @override
  Map<String, Object?> toJson(String to) => {
    'messaging_product': 'whatsapp',
    'recipient_type': 'individual',
    'to': to,
    'type': 'text',
    'text': {'preview_url': false, 'body': _clip(body, 4096)},
  };

  @override
  String toString() => 'TextReply($body)';
}

class ReplyButton {
  /// Comes back as [Incoming.buttonId]; at most 256 characters.
  final String id;

  /// At most 20 characters, or WhatsApp rejects the message.
  final String title;

  const ReplyButton(this.id, this.title);
}

/// A message with up to three reply buttons.
class ButtonsReply extends Outgoing {
  final String body;
  final List<ReplyButton> buttons;

  /// One to three [buttons]; WhatsApp rejects more.
  const ButtonsReply(this.body, this.buttons);

  @override
  Map<String, Object?> toJson(String to) {
    if (buttons.isEmpty || buttons.length > 3) {
      throw ArgumentError(
        'WhatsApp allows 1 to 3 buttons, got ${buttons.length}',
      );
    }
    return _json(to);
  }

  Map<String, Object?> _json(String to) => {
    'messaging_product': 'whatsapp',
    'recipient_type': 'individual',
    'to': to,
    'type': 'interactive',
    'interactive': {
      'type': 'button',
      'body': {'text': _clip(body, 1024)},
      'action': {
        'buttons': [
          for (final b in buttons)
            {
              'type': 'reply',
              'reply': {'id': b.id, 'title': _clip(b.title, 20)},
            },
        ],
      },
    },
  };

  @override
  String toString() =>
      'ButtonsReply($body, ${buttons.map((b) => b.title).join(' | ')})';
}

String _clip(String s, int max) =>
    s.length <= max ? s : '${s.substring(0, max - 1)}…';
