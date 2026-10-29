/// Helpers for handling **local** calendar dates consistently.
///
/// Mood entries are keyed by the device's local calendar day so that "today"
/// always matches what the user sees. The key format is `yyyy-MM-dd`, which
/// sorts and compares correctly as a plain string, avoiding any timezone
/// surprises between storage and display.
abstract final class AppDates {
  /// Trims any time-of-day component so two timestamps on the same local day
  /// compare equal.
  static DateTime dateOnly(DateTime date) =>
      DateTime(date.year, date.month, date.day);

  /// Canonical `yyyy-MM-dd` key for a local calendar day.
  static String dateKey(DateTime date) {
    final d = dateOnly(date);
    final month = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$month-$day';
  }

  /// Parses a `yyyy-MM-dd` key back into a local date-only [DateTime].
  static DateTime parseDateKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) {
      throw FormatException('Invalid date key: $key');
    }
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }

  static bool isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return dateKey(a) == dateKey(b);
  }

  /// True when [date] is a local calendar day in the future.
  static bool isFuture(DateTime date, {DateTime? now}) {
    final reference = dateOnly(now ?? DateTime.now());
    return dateOnly(date).isAfter(reference);
  }

  /// The start (inclusive) and end-exclusive of the current local day.
  static DateTime startOfToday({DateTime? now}) =>
      dateOnly(now ?? DateTime.now());

  /// Start of the week (Monday) containing [date].
  static DateTime startOfWeek(DateTime date) {
    final d = dateOnly(date);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// Start of the calendar month containing [date].
  static DateTime startOfMonth(DateTime date) =>
      DateTime(date.year, date.month);

  /// Inclusive list of every day from [from] to [to].
  static List<DateTime> daysInRange(DateTime from, DateTime to) {
    final days = <DateTime>[];
    var cursor = dateOnly(from);
    final end = dateOnly(to);
    while (!cursor.isAfter(end)) {
      days.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  /// Friendly greeting based on the time of day.
  static String greeting(DateTime now) {
    final hour = now.hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
