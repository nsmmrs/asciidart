// Writes a corpus of documents from asciidoctor-pdf's spec suite
// (vendor/asciidoctor-pdf/test/spec): each `to_pdf <<~'EOS'` heredoc as a
// document, with the options the spec converts it with as command line
// arguments (`<doc>.opts`, one per line) and an inline theme as a theme
// file (`<doc>-theme.yml`). Specs whose options can't be read statically
// (a theme in a variable, interpolation) are left out.
//
// Usage: dart run tool/pdf_spec_corpus.dart OUT_DIR
//
// The documents use the spec's defaults: images from the spec fixtures,
// no footer (unless the spec enables it), the safe mode. Convert them with
// the gem and asciidart (reading the .opts) and compare with
// tool/pdf_parity.dart.
import 'dart:io';

const _specDir = 'vendor/asciidoctor-pdf/test/spec';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('usage: pdf_spec_corpus.dart OUT_DIR');
    exitCode = 64;
    return;
  }
  final out = Directory(args.single)..createSync(recursive: true);
  final fixtures = Directory('$_specDir/fixtures').absolute.path;
  var written = 0;
  var skipped = 0;
  final specs =
      Directory(_specDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('_spec.rb'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final spec in specs) {
    final name = spec.uri.pathSegments.last.replaceFirst('_spec.rb', '');
    final lines = spec.readAsLinesSync();
    var n = 0;
    for (var i = 0; i < lines.length; i++) {
      final match = RegExp(r"""to_pdf <<~'?(\w+)'?(.*)$""")
          .firstMatch(lines[i]);
      if (match == null) continue;
      final tag = match[1]!;
      final body = <String>[];
      var j = i + 1;
      while (j < lines.length && lines[j].trim() != tag) {
        body.add(lines[j]);
        j++;
      }
      i = j;
      n++;
      final options = _options(match[2]!.trim());
      final text = _dedent(body);
      if (options == null ||
          (!lines[i - body.length - 1].contains("<<~'") &&
              text.contains('#{'))) {
        skipped++;
        continue;
      }
      final base = '$name-${n.toString().padLeft(3, '0')}';
      File('${out.path}/$base.adoc').writeAsStringSync('$text\n');
      final cli = <String>[
        '-a',
        'imagesdir=$fixtures',
        if (!options.footer) ...['-a', 'nofooter'],
        if (options.doctype case final doctype?) ...['-d', doctype],
        for (final MapEntry(:key, :value) in options.attributes.entries) ...[
          '-a',
          if (value == null) '$key!' else '$key=$value',
        ],
      ];
      if (options.theme case final theme?) {
        File('${out.path}/$base-theme.yml').writeAsStringSync(theme);
        cli.addAll([
          '-a',
          'pdf-theme=$base-theme.yml',
          '-a',
          'pdf-themesdir=${out.absolute.path}',
        ]);
      }
      File('${out.path}/$base.opts').writeAsStringSync('${cli.join('\n')}\n');
      written++;
    }
  }
  stdout.writeln('pdf_spec_corpus: $written documents ($skipped left out)');
}

/// A spec's options: doctype, attributes, footer, theme (as YAML).
typedef _Options = ({
  String? doctype,
  Map<String, String?> attributes,
  bool footer,
  String? theme,
});

/// The options after the heredoc tag, or null when they can't be read.
_Options? _options(String text) {
  String? doctype;
  final attributes = <String, String?>{};
  var footer = false;
  String? theme;
  var rest = text;
  while (rest.isNotEmpty) {
    rest = rest.replaceFirst(RegExp(r'^,\s*'), '');
    if (rest.isEmpty) break;
    final key = RegExp(r'^(\w+):\s*').firstMatch(rest);
    if (key == null) return null;
    rest = rest.substring(key.end);
    final (value, after) = _value(rest);
    if (value == null) return null;
    rest = after.trim();
    switch (key[1]) {
      case 'analyze' || 'debug':
        break;
      case 'doctype':
        doctype = value.replaceFirst(':', '');
      case 'enable_footer':
        footer = value == 'true';
      case 'attribute_overrides' || 'attributes':
        final entries = _hash(value, rubyKeys: true);
        if (entries == null) return null;
        attributes.addAll(entries);
      case 'pdf_theme':
        final entries = _hash(value, rubyKeys: false);
        if (entries == null) return null;
        final extends_ = entries.remove('extends') ?? 'default';
        theme = [
          'extends: $extends_',
          for (final MapEntry(:key, :value) in entries.entries)
            '$key: ${value ?? '~'}',
        ].join('\n');
      default:
        return null;
    }
  }
  return (
    doctype: doctype,
    attributes: attributes,
    footer: footer,
    theme: theme,
  );
}

/// The Ruby value at the start of [text] (a literal, an array or a hash
/// on this line), and the text after it.
(String?, String) _value(String text) {
  if (text.startsWith('{') || text.startsWith('[')) {
    final open = text[0];
    final close = open == '{' ? '}' : ']';
    var depth = 0;
    for (var i = 0; i < text.length; i++) {
      if (text[i] == open) depth++;
      if (text[i] == close && --depth == 0) {
        return (text.substring(0, i + 1), text.substring(i + 1));
      }
    }
    return (null, '');
  }
  final literal = RegExp(
    r"""^('[^']*'|"[^"#]*"|:\w+|-?\d+(?:\.\d+)?|true|false|nil)""",
  ).firstMatch(text);
  if (literal == null) return (null, '');
  return (literal[0], text.substring(literal.end));
}

/// The entries of the Ruby hash [text] (`{ 'k' => 'v' }` with [rubyKeys],
/// else `{ k: v }`), as YAML scalars; null when a value isn't a literal.
Map<String, String?>? _hash(String text, {required bool rubyKeys}) {
  final inner = text.substring(1, text.length - 1).trim();
  final entries = <String, String?>{};
  var rest = inner;
  while (rest.isNotEmpty) {
    final key = rubyKeys
        ? RegExp(r"""^['"]([^'"]+)['"]\s*=>\s*""").firstMatch(rest)
        : RegExp(r'^(\w+):\s*').firstMatch(rest);
    if (key == null) return null;
    rest = rest.substring(key.end);
    final (value, after) = _value(rest);
    if (value == null || value.startsWith('{')) return null;
    entries[key[1]!] = _yaml(value);
    rest = after.trim().replaceFirst(RegExp(r'^,\s*'), '');
  }
  return entries;
}

/// A Ruby literal as a YAML scalar (or flow sequence); null for nil.
String? _yaml(String value) {
  if (value == 'nil') return null;
  if (value.startsWith(':')) return value.substring(1);
  if (value.startsWith("'")) {
    return "'${value.substring(1, value.length - 1).replaceAll("'", "''")}'";
  }
  if (value.startsWith('[')) {
    final items = value.substring(1, value.length - 1).split(',');
    return '[${items.map((v) => _yaml(v.trim()) ?? '~').join(', ')}]';
  }
  return value;
}

/// [lines] without their common indentation (a squiggly heredoc).
String _dedent(List<String> lines) {
  final indents = [
    for (final line in lines)
      if (line.trim().isNotEmpty) line.length - line.trimLeft().length,
  ];
  final indent = indents.isEmpty ? 0 : indents.reduce((a, b) => a < b ? a : b);
  return [
    for (final line in lines)
      if (line.length >= indent) line.substring(indent) else line.trimLeft(),
  ].join('\n');
}
