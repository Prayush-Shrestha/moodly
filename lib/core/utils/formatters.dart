import 'package:intl/intl.dart';

/// Shared date/time display formats.
abstract final class Formatters {
  /// `Tuesday, October 28` — home header.
  static String longDate(DateTime date) =>
      DateFormat('EEEE, MMMM d').format(date);

  /// `Oct 28, 2026` — lists and detail views.
  static String mediumDate(DateTime date) =>
      DateFormat('MMM d, y').format(date);

  /// `Tuesday, October 28, 2026` — check-in screen header.
  static String fullDate(DateTime date) =>
      DateFormat('EEEE, MMMM d, y').format(date);

  /// `4:32 PM` — last-updated stamps.
  static String time(DateTime date) => DateFormat('h:mm a').format(date);

  /// `Oct 28, 4:32 PM` — export metadata / audit lines.
  static String dateTime(DateTime date) =>
      DateFormat('MMM d, y, h:mm a').format(date);
}
