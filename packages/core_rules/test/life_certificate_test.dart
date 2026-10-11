import 'package:core_rules/core_rules.dart';
import 'package:test/test.dart';

void main() {
  test('pensioners aged 80 or more get the October window', () {
    final w = windowFor(2026, DateTime.utc(1946, 10, 1));
    expect(w.opens, DateTime.utc(2026, 10, 1));
    expect(w.closes, DateTime.utc(2026, 11, 30));
  });

  test('turning 80 a day after the window opens means November', () {
    expect(
      windowFor(2026, DateTime.utc(1946, 10, 2)).opens,
      DateTime.utc(2026, 11, 1),
    );
  });

  test('days left counts the deadline day as 0', () {
    final w = windowFor(2026, DateTime.utc(1960, 5, 5));
    expect(w.daysLeft(DateTime.utc(2026, 11, 30, 18)), 0);
    expect(w.daysLeft(DateTime.utc(2026, 12, 1)), -1);
    expect(w.contains(DateTime.utc(2026, 10, 31)), isFalse);
    expect(w.contains(DateTime.utc(2026, 11, 1)), isTrue);
  });

  test('reminders skip the past and anything before the window opens', () {
    final w = windowFor(2026, DateTime.utc(1960, 5, 5));
    expect(remindersFor(w, DateTime.utc(2026, 10, 11)).map((r) => '$r'), [
      '2026-11-01 windowOpens (29)',
      '2026-11-09 beforeDeadline (21)',
      '2026-11-23 beforeDeadline (7)',
      '2026-11-28 beforeDeadline (2)',
      '2026-11-30 deadlineDay (0)',
    ]);
    expect(remindersFor(w, DateTime.utc(2026, 11, 25)).map((r) => '$r'), [
      '2026-11-28 beforeDeadline (2)',
      '2026-11-30 deadlineDay (0)',
    ]);
  });

  test('a state policy can change the dates', () {
    const policy = LifeCertificatePolicy(
      opens: (month: 4, day: 1),
      closes: (month: 6, day: 30),
    );
    final w = windowFor(2027, DateTime.utc(1960, 1, 1), policy: policy);
    expect(w.opens, DateTime.utc(2027, 4, 1));
    expect(w.closes, DateTime.utc(2027, 6, 30));
  });
}
