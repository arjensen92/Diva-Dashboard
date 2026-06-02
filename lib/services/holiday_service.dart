import 'package:flutter/widgets.dart';

/// Holiday catalog + date lookup. Pure data + pure functions — no Flutter
/// widgets. Consumed by the calendar card to decide which day cells get a
/// holiday label, icon, or background.
///
/// Three tables feed [holidaysFor]:
///  - [_fixedHolidays]   — same MM-DD every year (Christmas, Halloween, …).
///  - [perYearHolidays]  — dates that shift year-to-year and don't fit a
///                         simple rule (Mardi Gras, Chinese New Year, …).
///                         Add one entry per year you care about.
///  - [_floatingHolidaysFor] — rule-based: nth-weekday-of-month,
///                             last-weekday-of-month, Easter.
///
/// Per-holiday presentation overrides (icon filename, cell color,
/// stretched-bg opacity, bobbing) live in the other top-level constants
/// below — all of them are keyed by holiday name.

// ===== Presentation overrides (keyed by holiday name) =====

/// Icon filename in `assets/icons/holidays/` for each named holiday.
/// Holidays without an entry render as a text label only.
const holidayIcons = <String, String>{
  "April Fools'": 'april-fools.apng',
  'Easter': 'easter.apng',
  'Easter Sunday': 'easter.apng',
  'Earth Day': 'earth-day.apng',
  'Tax Day': 'tax-day.apng',
  'National Burrito Day': 'burrito-day.gif',
  'Tartan Day': 'tartan-day.png',
  'National Unicorn Day': 'unicorn-day.gif',
  'National Grilled Cheese Day': 'grilled-cheese-day.gif',
  '420': '420.gif',
  'Arbor Day': 'arbor-day.gif',
  'National Pretzel Day': 'pretzel-day.gif',
  'International Dance Day': 'dance-day.gif',
  'International Jazz Day': 'jazz-day.gif',
  "Valentine's Day": 'valentines-day.gif',
  'World Health Day': 'health-day.png',
  'National Pet Day': 'pet-day.gif',
};

/// How many copies of a holiday's icon to render side-by-side in its day
/// cell. Default (missing key) is 1.
const holidayIconRepeat = <String, int>{};

/// Holidays whose icon bobs up and down by 1px (no smoothing).
const bobbingHolidays = <String>{'World Health Day'};

/// Semi-transparent fill color for a holiday's day cell (behind
/// everything). Alpha is intentionally ≤ 0x80 so the month background
/// still shows through.
const holidayCellColors = <String, Color>{
  'International Day of Pink': Color(0x80EC3D8D),
};

/// Holidays whose icon fills the entire day cell as a stretched
/// background, instead of rendering as a small bottom-center icon.
const stretchedHolidayBgs = <String>{'Tartan Day'};

/// Per-holiday opacity for the stretched background image. Default 1.0.
const stretchedHolidayOpacity = <String, double>{
  'Tartan Day': 0.5,
};

/// Holidays whose *name* is suppressed from the day cell's text column —
/// icon only.
const iconOnlyHolidays = <String>{'420'};

/// Month-theme accent color (January icy blue → December Christmas red).
const monthColors = <int, Color>{
  1: Color(0xFF88CCEE), // January — icy blue
  2: Color(0xFFFF69B4), // February — pink (Valentine's)
  3: Color(0xFF77DD77), // March — spring green
  4: Color(0xFFFFD700), // April — golden yellow
  5: Color(0xFFFF6B6B), // May — coral
  6: Color(0xFFFFA500), // June — orange sunshine
  7: Color(0xFFFF4444), // July — red (fireworks)
  8: Color(0xFF87CEEB), // August — sky blue
  9: Color(0xFFDEB887), // September — autumn tan
  10: Color(0xFFFF8C00), // October — pumpkin orange
  11: Color(0xFF8B4513), // November — brown (harvest)
  12: Color(0xFFCC0000), // December — christmas red
};

// ===== Date tables =====

/// Fixed-date holidays — keyed by `MM-DD`.
const _fixedHolidays = <String, String>{
  '01-01': "New Year's Day",
  '02-02': 'Groundhog Day',
  '02-14': "Valentine's Day",
  '03-17': "St. Patrick's Day",
  '04-01': "April Fools'",
  '04-06': 'Tartan Day',
  '04-07': 'World Health Day',
  '04-09': 'National Unicorn Day',
  '04-11': 'National Pet Day',
  '04-12': 'National Grilled Cheese Day',
  '04-15': 'Tax Day',
  '04-20': '420',
  '04-22': 'Earth Day',
  '04-26': 'National Pretzel Day',
  '04-29': 'International Dance Day',
  '04-30': 'International Jazz Day',
  '05-05': 'Cinco de Mayo',
  '06-19': 'Juneteenth',
  '07-04': 'Independence Day',
  '10-31': 'Halloween',
  '11-11': 'Veterans Day',
  '12-24': 'Christmas Eve',
  '12-25': 'Christmas Day',
  '12-31': "New Year's Eve",
};

/// Holidays whose date shifts every year and doesn't fit a simple rule
/// (e.g. Mardi Gras, Chinese New Year, Rosh Hashanah, Diwali, Ramadan
/// start). Keyed by `YYYY-MM-DD` → holiday name. Add one entry per year
/// you care about; entries for past years are harmless.
const perYearHolidays = <String, String>{
  '2026-04-08': 'International Day of Pink',
  '2026-04-24': 'Arbor Day',
};

// ===== Public lookup =====

/// Returns every holiday that lands on [date] — merging fixed-date,
/// floating (rule-based), and per-year entries.
List<String> holidaysFor(DateTime date) {
  final result = <String>[];
  final mmdd = _mmdd(date);
  final fixed = _fixedHolidays[mmdd];
  if (fixed != null) result.add(fixed);
  final perYear = perYearHolidays[_yyyymmdd(date)];
  if (perYear != null) result.add(perYear);
  result.addAll(_floatingHolidaysFor(date.year, date.month, date.day));
  return result;
}

String _mmdd(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _yyyymmdd(DateTime d) => '${d.year}-${_mmdd(d)}';

// ===== Floating-date calculators =====

/// Day-of-month for the nth [weekday] of [month] in [year]. Weekdays use
/// [DateTime] constants (Mon=1..Sun=7); [n] is 1-indexed.
int _nthWeekday(int year, int month, int weekday, int n) {
  final first = DateTime(year, month, 1);
  final firstMatch = 1 + ((weekday - first.weekday) + 7) % 7;
  return firstMatch + (n - 1) * 7;
}

/// Day-of-month for the last [weekday] of [month] in [year].
int _lastWeekday(int year, int month, int weekday) {
  final last = DateTime(year, month + 1, 0);
  return last.day - ((last.weekday - weekday + 7) % 7);
}

/// Gregorian Easter Sunday via the Gauss/Butcher algorithm.
DateTime _easterSunday(int year) {
  final a = year % 19;
  final b = year ~/ 100;
  final c = year % 100;
  final d = b ~/ 4;
  final e = b % 4;
  final f = (b + 8) ~/ 25;
  final g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4;
  final k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final month = (h + l - 7 * m + 114) ~/ 31;
  final day = ((h + l - 7 * m + 114) % 31) + 1;
  return DateTime(year, month, day);
}

/// Rule-based holidays (nth-weekday-of-month, last-weekday-of-month,
/// Easter) that land on the given day.
List<String> _floatingHolidaysFor(int year, int month, int day) {
  final result = <String>[];

  // MLK Day — 3rd Monday of January
  if (month == 1 && day == _nthWeekday(year, 1, DateTime.monday, 3)) {
    result.add('Martin Luther King Jr. Day');
  }
  // Presidents' Day — 3rd Monday of February
  if (month == 2 && day == _nthWeekday(year, 2, DateTime.monday, 3)) {
    result.add("Presidents' Day");
  }
  // National Burrito Day — 1st Thursday of April
  if (month == 4 && day == _nthWeekday(year, 4, DateTime.thursday, 1)) {
    result.add('National Burrito Day');
  }
  // Mother's Day — 2nd Sunday of May
  if (month == 5 && day == _nthWeekday(year, 5, DateTime.sunday, 2)) {
    result.add("Mother's Day");
  }
  // Memorial Day — last Monday of May
  if (month == 5 && day == _lastWeekday(year, 5, DateTime.monday)) {
    result.add('Memorial Day');
  }
  // Father's Day — 3rd Sunday of June
  if (month == 6 && day == _nthWeekday(year, 6, DateTime.sunday, 3)) {
    result.add("Father's Day");
  }
  // Labor Day — 1st Monday of September
  if (month == 9 && day == _nthWeekday(year, 9, DateTime.monday, 1)) {
    result.add('Labor Day');
  }
  // Columbus Day — 2nd Monday of October
  if (month == 10 && day == _nthWeekday(year, 10, DateTime.monday, 2)) {
    result.add('Columbus Day');
  }
  // Thanksgiving — 4th Thursday of November
  if (month == 11 && day == _nthWeekday(year, 11, DateTime.thursday, 4)) {
    result.add('Thanksgiving');
  }

  // Easter Sunday
  final easter = _easterSunday(year);
  if (easter.month == month && easter.day == day) result.add('Easter Sunday');

  return result;
}
