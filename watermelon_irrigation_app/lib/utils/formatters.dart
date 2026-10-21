import 'package:intl/intl.dart';

import '../models/growth_stage.dart';

class Fmt {
  static final _updated = DateFormat('MMMM d, y, h:mm a');
  static final _longDate = DateFormat('MMMM d, y');
  static final _shortDate = DateFormat('MMM d');
  static final _shortDateYear = DateFormat('MMM d, y');
  static final _shortDateTime = DateFormat('MMM d, h:mm a');

  static String updated(DateTime t) => _updated.format(t);
  static String longDate(DateTime t) => _longDate.format(t);
  static String shortDate(DateTime t) => _shortDate.format(t);
  static String shortDateYear(DateTime t) => _shortDateYear.format(t);
  static String shortDateTime(DateTime t) => _shortDateTime.format(t);

  /// 29.0 -> "29", 28.46 -> "28.5"
  static String number(double v) {
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }

  static String percent(double v) => '${number(v)}%';
  static String celsius(double v) => '${number(v)}°C';
  static String mm(double v) => '${number(v)} mm';
  static String minutes(double v) => '${number(v)} min';
  static String hours(double v) => '${number(v)} h';

  /// Used for "Next irrigation ___".
  static String nextIrrigation(double h) {
    if (h <= 0) return 'now';
    if (h < 1) return 'in ${(h * 60).round()} minutes';
    if (h == 1) return 'in 1 hour';
    return 'in ${number(h)} hours';
  }

  /// The farmer-facing name for the stages in [growthStages]; any other
  /// value is shown as its own name, e.g. "early_fruiting" -> "Early Fruiting".
  static String growthStage(String raw) {
    for (final s in growthStages) {
      if (s.value == raw) return s.label;
    }
    return _titleCase(raw);
  }

  static String _titleCase(String raw) => raw
      .replaceAll(RegExp(r'[_\-]+'), ' ')
      .trim()
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
      .join(' ');

  static String period(DateTime from, DateTime to) {
    if (from.year == to.year && from.month == to.month && from.day == to.day) {
      return longDate(to);
    }
    return '${shortDate(from)} to ${shortDateYear(to)}';
  }
}
