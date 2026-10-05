/// Dates for the EPUB package metadata, read as the gem reads them (Ruby's
/// `Time.parse`) and written in UTC (`2026-01-31T12:00:00Z`).
library;

/// [value] parsed as a time and written in UTC ISO 8601, or `null` when it
/// holds no date this reads.
///
/// Reads the forms documents and Asciidoctor give: `2026-01-31`,
/// `2026-01-31 12:00:00 +0100` (`docdatetime`), ISO 8601 with a `T`, an
/// offset or `Z`, `2026/01/31`, and `31 January 2026` or `January 31,
/// 2026`. A time without an offset is local time, as in Ruby.
String? rubyTimeParseUtc(String value) {
  final text = value.trim();
  final parsed = _parseNumeric(text) ?? _parseMonthName(text);
  if (parsed == null) return null;
  final utc = parsed.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${utc.year.toString().padLeft(4, '0')}-${two(utc.month)}-'
      '${two(utc.day)}T${two(utc.hour)}:${two(utc.minute)}:${two(utc.second)}Z';
}

final RegExp _numericRx = RegExp(
  r'^(\d{4})[-/](\d{1,2})[-/](\d{1,2})'
  r'(?:[ T](\d{1,2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?)?'
  r'\s*(Z|UTC|[+-]\d{2}:?\d{2})?$',
  caseSensitive: false,
);

DateTime? _parseNumeric(String text) {
  final match = _numericRx.firstMatch(text);
  if (match == null) return null;
  return _build(
    int.parse(match[1]!),
    int.parse(match[2]!),
    int.parse(match[3]!),
    int.parse(match[4] ?? '0'),
    int.parse(match[5] ?? '0'),
    int.parse(match[6] ?? '0'),
    match[7],
  );
}

const List<String> _months = [
  'jan',
  'feb',
  'mar',
  'apr',
  'may',
  'jun',
  'jul',
  'aug',
  'sep',
  'oct',
  'nov',
  'dec',
];

final RegExp _dayMonthYearRx = RegExp(
  r'^(\d{1,2})(?:st|nd|rd|th)?\s+([A-Za-z]+)\.?,?\s+(\d{4})$',
);
final RegExp _monthDayYearRx = RegExp(
  r'^([A-Za-z]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})$',
);

DateTime? _parseMonthName(String text) {
  int? month(String name) {
    final index = _months.indexOf(
      name.length < 3 ? '' : name.substring(0, 3).toLowerCase(),
    );
    return index < 0 ? null : index + 1;
  }

  if (_dayMonthYearRx.firstMatch(text) case final match?) {
    final m = month(match[2]!);
    if (m == null) return null;
    return _build(int.parse(match[3]!), m, int.parse(match[1]!), 0, 0, 0, null);
  }
  if (_monthDayYearRx.firstMatch(text) case final match?) {
    final m = month(match[1]!);
    if (m == null) return null;
    return _build(int.parse(match[3]!), m, int.parse(match[2]!), 0, 0, 0, null);
  }
  return null;
}

DateTime? _build(
  int year,
  int month,
  int day,
  int hour,
  int minute,
  int second,
  String? zone,
) {
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  if (hour > 23 || minute > 59 || second > 60) return null;
  if (zone == null) {
    return DateTime(year, month, day, hour, minute, second);
  }
  final utc = DateTime.utc(year, month, day, hour, minute, second);
  final upper = zone.toUpperCase();
  if (upper == 'Z' || upper == 'UTC') return utc;
  final sign = zone.startsWith('-') ? -1 : 1;
  final digits = zone.substring(1).replaceAll(':', '');
  final offset = Duration(
    hours: int.parse(digits.substring(0, 2)),
    minutes: int.parse(digits.substring(2)),
  );
  return sign > 0 ? utc.subtract(offset) : utc.add(offset);
}
