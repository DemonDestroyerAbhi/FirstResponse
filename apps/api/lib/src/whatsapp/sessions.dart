/// Short-lived conversation state per WhatsApp user.
///
/// Holds only what the next reply needs, and expires quickly: a date of
/// birth or a masked message is kept for minutes, not stored.
library;

sealed class Session {
  final DateTime updatedAt;
  const Session(this.updatedAt);
}

/// Asked for the pensioner's date of birth.
class AwaitingDob extends Session {
  const AwaitingDob(super.updatedAt);
}

/// Asking "is this your problem?" about [candidates], one at a time.
class Confirming extends Session {
  /// The user's message, already masked by the engine.
  final String input;

  /// Rule ids, best first.
  final List<String> candidates;
  final int index;

  const Confirming(
    super.updatedAt, {
    required this.input,
    required this.candidates,
    this.index = 0,
  });

  String get current => candidates[index];
}

abstract interface class SessionStore {
  Session? get(String user, DateTime now);
  void put(String user, Session session);
  void clear(String user);
}

class InMemorySessionStore implements SessionStore {
  final Duration ttl;
  final _sessions = <String, Session>{};

  InMemorySessionStore({this.ttl = const Duration(minutes: 30)});

  @override
  Session? get(String user, DateTime now) {
    final s = _sessions[user];
    if (s != null && now.difference(s.updatedAt) > ttl) {
      _sessions.remove(user);
      return null;
    }
    return s;
  }

  @override
  void put(String user, Session session) {
    // Drop expired sessions now and then so the map does not grow forever.
    if (_sessions.length > 1000) {
      _sessions.removeWhere(
        (_, s) => session.updatedAt.difference(s.updatedAt) > ttl,
      );
    }
    _sessions[user] = session;
  }

  @override
  void clear(String user) => _sessions.remove(user);
}
