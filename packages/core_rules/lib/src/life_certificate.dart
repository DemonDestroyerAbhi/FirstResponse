/// Life-certificate deadlines and reminders (module #9).
///
/// Defaults follow the DoPPW rule for central government pensioners:
/// pensioners aged 80 or more may submit from 1 October, everyone else from
/// 1 November, and the window closes on 30 November. State governments and
/// some disbursing agencies use other dates, so the policy is configurable.
///
/// The defaults must be checked against the current DoPPW circular before
/// launch, like any rule.
library;

class LifeCertificatePolicy {
  final int superSeniorAge;
  final ({int month, int day}) superSeniorOpens;
  final ({int month, int day}) opens;
  final ({int month, int day}) closes;

  /// Days before the deadline to remind, in addition to when the window opens.
  final List<int> remindDaysBefore;

  const LifeCertificatePolicy({
    this.superSeniorAge = 80,
    this.superSeniorOpens = (month: 10, day: 1),
    this.opens = (month: 11, day: 1),
    this.closes = (month: 11, day: 30),
    this.remindDaysBefore = const [21, 7, 2],
  });

  static const centralGovernment = LifeCertificatePolicy();
}

enum ReminderKind { windowOpens, beforeDeadline, deadlineDay }

class Reminder {
  final DateTime date;
  final ReminderKind kind;

  /// Days left until the deadline, counting the deadline day itself as 0.
  final int daysLeft;

  const Reminder(this.date, this.kind, this.daysLeft);

  @override
  String toString() =>
      '${date.toIso8601String().substring(0, 10)} ${kind.name} ($daysLeft)';
}

class LifeCertificateWindow {
  final DateTime opens;
  final DateTime closes;

  const LifeCertificateWindow(this.opens, this.closes);

  bool contains(DateTime day) {
    final d = _day(day);
    return !d.isBefore(opens) && !d.isAfter(closes);
  }

  /// Days until [closes], 0 on the deadline day, negative once missed.
  int daysLeft(DateTime day) => closes.difference(_day(day)).inDays;
}

/// Window for the submission season in [year], for a pensioner born on
/// [dateOfBirth]. Age is taken on the day the super-senior window opens.
LifeCertificateWindow windowFor(
  int year,
  DateTime dateOfBirth, {
  LifeCertificatePolicy policy = LifeCertificatePolicy.centralGovernment,
}) {
  final early = DateTime.utc(
    year,
    policy.superSeniorOpens.month,
    policy.superSeniorOpens.day,
  );
  final opens = ageOn(dateOfBirth, early) >= policy.superSeniorAge
      ? early
      : DateTime.utc(year, policy.opens.month, policy.opens.day);
  return LifeCertificateWindow(
    opens,
    DateTime.utc(year, policy.closes.month, policy.closes.day),
  );
}

/// The season a pensioner should act on: this year's, or next year's once
/// this year's deadline has passed.
LifeCertificateWindow currentWindow(
  DateTime dateOfBirth,
  DateTime today, {
  LifeCertificatePolicy policy = LifeCertificatePolicy.centralGovernment,
}) {
  final window = windowFor(today.year, dateOfBirth, policy: policy);
  return window.daysLeft(today) >= 0
      ? window
      : windowFor(today.year + 1, dateOfBirth, policy: policy);
}

/// Reminders still ahead of [today] for this season, in date order.
List<Reminder> remindersFor(
  LifeCertificateWindow window,
  DateTime today, {
  LifeCertificatePolicy policy = LifeCertificatePolicy.centralGovernment,
}) {
  final now = _day(today);
  final all = <Reminder>[
    Reminder(
      window.opens,
      ReminderKind.windowOpens,
      window.daysLeft(window.opens),
    ),
    for (final d in policy.remindDaysBefore)
      if (d > 0)
        Reminder(
          window.closes.subtract(Duration(days: d)),
          ReminderKind.beforeDeadline,
          d,
        ),
    Reminder(window.closes, ReminderKind.deadlineDay, 0),
  ];
  return [
    for (final r in all)
      if (!r.date.isBefore(now) && !r.date.isBefore(window.opens)) r,
  ]..sort((a, b) => a.date.compareTo(b.date));
}

int ageOn(DateTime dateOfBirth, DateTime day) {
  var age = day.year - dateOfBirth.year;
  if (day.month < dateOfBirth.month ||
      (day.month == dateOfBirth.month && day.day < dateOfBirth.day)) {
    age--;
  }
  return age;
}

DateTime _day(DateTime d) => DateTime.utc(d.year, d.month, d.day);
