/// Mustache-style templates for generated text (IDs, reftexts, labels,
/// headings, note origins): `{{name}}`, `{{name.part}}`,
/// `{{name|filter|filter}}`, sections `{{#name}}…{{/name}}` (shown when
/// the value is present and not false, repeated for a list) and inverted
/// sections `{{^name}}…{{/name}}`.
library;

/// A value a template reads.
sealed class TValue {
  const new();
}

/// A text value.
final class TText extends TValue {
  /// A text value of [value].
  const new(this.value);

  /// The text.
  final String value;
}

/// A flag: a section renders for `true`, an inverted section for `false`.
final class TFlag extends TValue {
  /// A flag of [value].
  const new({required this.value});

  /// Whether the flag is set.
  final bool value;
}

/// A record of named fields, rendered by itself as [text] (a book: its
/// code; `{{book.name}}` reads a field).
final class TRecord extends TValue {
  /// A record of [fields], rendered as [text].
  const new(this.fields, {this.text = ''});

  /// What `{{name}}` prints for the record itself.
  final String text;

  /// The record's fields by name.
  final Map<String, TValue> fields;
}

/// A list a section repeats for each of its items.
final class TItems extends TValue {
  /// A list of [items].
  const new(this.items);

  /// The items, each a map of names to values.
  final List<Map<String, TValue>> items;
}

final _tag = RegExp(r'\{\{([#^/]?)\s*([^}]*?)\s*\}\}');

/// [template] with the values of [context].
String render(String template, Map<String, TValue> context) {
  final out = StringBuffer();
  _render(template, [context], out);
  return out.toString();
}

void _render(String t, List<Map<String, TValue>> scopes, StringBuffer out) {
  var pos = 0;
  while (true) {
    final m = _tag.firstMatch(t.substring(pos));
    if (m == null) {
      out.write(t.substring(pos));
      return;
    }
    out.write(t.substring(pos, pos + m.start));
    final kind = m[1]!;
    final expr = m[2]!;
    final after = pos + m.end;
    if (kind == '#' || kind == '^') {
      final close = _findClose(t, after, expr);
      final body = t.substring(after, close.$1);
      // A section on a filtered value (`{{#line|every:5}}`) shows when the
      // filtered text is not empty.
      final filtered = expr.contains('|');
      var value = filtered ? null : _lookup(expr, scopes);
      if (filtered) {
        final parts = expr.split('|');
        var text = _text(_lookup(parts.first.trim(), scopes));
        for (final f in parts.skip(1)) {
          text = applyFilter(f.trim(), text);
        }
        value = TText(text);
      }
      final truthy = switch (value) {
        null => false,
        TFlag(:final value) => value,
        TText(:final value) => value.isNotEmpty,
        TItems(:final items) => items.isNotEmpty,
        TRecord() => true,
      };
      if (kind == '^') {
        if (!truthy) _render(body, scopes, out);
      } else if (filtered) {
        if (truthy) _render(body, scopes, out);
      } else if (value case TItems(:final items)) {
        for (final item in items) {
          _render(body, [...scopes, item], out);
        }
      } else if (value case TRecord(:final fields) when truthy) {
        _render(body, [...scopes, fields], out);
      } else if (truthy) {
        _render(body, scopes, out);
      }
      pos = close.$2;
      continue;
    }
    final parts = expr.split('|');
    var text = _text(_lookup(parts.first.trim(), scopes));
    for (final f in parts.skip(1)) {
      text = applyFilter(f.trim(), text);
    }
    out.write(text);
    pos = after;
  }
}

/// Where the section [name] opened before [from] closes: (start of the
/// closing tag, end of it), counting nested sections of the same name.
(int, int) _findClose(String t, int from, String name) {
  var depth = 1;
  var pos = from;
  while (true) {
    final m = _tag.firstMatch(t.substring(pos));
    if (m == null) throw FormatException('unclosed {{#$name}} in "$t"');
    if (m[2] == name && (m[1] == '#' || m[1] == '^')) depth++;
    if (m[2] == name && m[1] == '/') {
      depth--;
      if (depth == 0) return (pos + m.start, pos + m.end);
    }
    pos += m.end;
  }
}

TValue? _lookup(String expr, List<Map<String, TValue>> scopes) {
  if (expr == '.') {
    return scopes.length > 1 ? TRecord(scopes.last) : null;
  }
  final path = expr.split('.');
  for (final scope in scopes.reversed) {
    var v = scope[path.first];
    if (v == null) continue;
    for (final key in path.skip(1)) {
      v = v is TRecord ? v.fields[key] : null;
      if (v == null) break;
    }
    return v;
  }
  return null;
}

String _text(TValue? v) => switch (v) {
  null => '',
  TText(:final value) => value,
  TFlag(:final value) => value ? 'true' : '',
  TRecord(:final text) => text,
  TItems() => '',
};

const _arabicIndic = '٠١٢٣٤٥٦٧٨٩';

/// A filter by name: `lower`, `upper`, `titlecase`, `arabic-indic`,
/// `roman`, `ROMAN`, `hebrew`, `every:N` (the text when it is a multiple of
/// N, else nothing).
String applyFilter(String filter, String text) {
  final (name, arg) = switch (filter.indexOf(':')) {
    -1 => (filter, ''),
    final i => (filter.substring(0, i), filter.substring(i + 1)),
  };
  switch (name) {
    case 'lower':
      return text.toLowerCase();
    case 'upper':
      return text.toUpperCase();
    case 'titlecase':
      return text.replaceAllMapped(
        RegExp("[A-Za-z']+"),
        (m) => m[0]!.length < 2
            ? m[0]!
            : '${m[0]![0].toUpperCase()}${m[0]!.substring(1).toLowerCase()}',
      );
    case 'arabic-indic':
      return text.replaceAllMapped(
        RegExp('[0-9]'),
        (m) => _arabicIndic[int.parse(m[0]!)],
      );
    case 'roman':
      return toRoman(int.tryParse(text) ?? 0).toLowerCase();
    case 'ROMAN':
      return toRoman(int.tryParse(text) ?? 0);
    case 'hebrew':
      return toHebrew(int.tryParse(text) ?? 0);
    case 'every':
      final n = int.tryParse(text);
      final k = int.tryParse(arg) ?? 1;
      return n != null && n % k == 0 ? text : '';
    case 'pad':
      return text.padLeft(int.tryParse(arg) ?? 0, '0');
    case 'slug':
      return text
          .toLowerCase()
          .replaceAll(RegExp('[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-|-$'), '');
    default:
      throw FormatException('unknown template filter "$filter"');
  }
}

/// [n] as a Roman numeral in capitals (`XIV`).
String toRoman(int n) {
  if (n <= 0) return '';
  const values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1];
  const symbols = [
    'M',
    'CM',
    'D',
    'CD',
    'C',
    'XC',
    'L',
    'XL',
    'X',
    'IX',
    'V',
    'IV',
    'I',
  ];
  final out = StringBuffer();
  var rest = n;
  for (var i = 0; i < values.length; i++) {
    while (rest >= values[i]) {
      out.write(symbols[i]);
      rest -= values[i];
    }
  }
  return out.toString();
}

/// The number the Roman numeral [s] writes (either case); 0 when [s] is
/// not one.
int fromRoman(String s) {
  const v = {'I': 1, 'V': 5, 'X': 10, 'L': 50, 'C': 100, 'D': 500, 'M': 1000};
  final u = s.toUpperCase();
  var total = 0;
  for (var i = 0; i < u.length; i++) {
    final a = v[u[i]];
    if (a == null) return 0;
    final b = i + 1 < u.length ? v[u[i + 1]] ?? 0 : 0;
    total += a < b ? -a : a;
  }
  return toRoman(total) == u ? total : 0;
}

/// Hebrew numerals (gematria), as Hebrew editions number dapim and
/// chapters: 15 and 16 are written ט״ו and ט״ז.
String toHebrew(int n) {
  if (n <= 0) return '';
  const ones = ['', 'א', 'ב', 'ג', 'ד', 'ה', 'ו', 'ז', 'ח', 'ט'];
  const tens = ['', 'י', 'כ', 'ל', 'מ', 'נ', 'ס', 'ע', 'פ', 'צ'];
  const hundreds = ['', 'ק', 'ר', 'ש', 'ת'];
  final out = StringBuffer();
  var rest = n;
  while (rest >= 400) {
    out.write('ת');
    rest -= 400;
  }
  out.write(hundreds[rest ~/ 100]);
  rest %= 100;
  if (rest == 15) {
    out.write('טו');
  } else if (rest == 16) {
    out.write('טז');
  } else {
    out
      ..write(tens[rest ~/ 10])
      ..write(ones[rest % 10]);
  }
  final s = out.toString();
  return s.length == 1
      ? '$s׳'
      : '${s.substring(0, s.length - 1)}״${s[s.length - 1]}';
}
