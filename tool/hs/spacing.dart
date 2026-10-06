// Compares the spacing of two PDFs of the Hypermedia Systems book (lane
// TASK-pbj7ln): for each probe, a line that contains one text followed
// (on the same page, within a few lines) by a line that contains
// another, the distance from the first line's top to the second's, in
// each PDF. The book's two editions share most of their text, so the
// probes find the same passages in both; the difference shows which
// element's spacing differs.
//
// Usage: dart run tool/hs/spacing.dart TYPST.pdf ASCIIDOC.pdf
//
// Needs pdftotext (poppler).
import 'dart:io';

/// A line of text: its page (0-based), top and bottom, and words.
typedef _Line = ({int page, double top, double bottom, String text});

/// What each probe measures, and its two texts (the start of a line is
/// enough; case and spaces don't count).
const _probes = <(String, String, String)>[
  (
    'paragraph to paragraph (line pitch)',
    'Hypermedia is a universal technology today',
    'Billions of people use hypermedia-based systems',
  ),
  (
    'paragraph to section heading',
    '(And, as the section on Hyperview will show',
    'What Is Hypermedia?',
  ),
  ('section heading to quote', 'What Is Hypermedia?', 'Hypertexts: new forms'),
  ('quote to its attribution', 'or perform at the reader', 'Ted Nelson'),
  (
    'quote attribution to paragraph',
    'Ted Nelson',
    'Let us begin at the beginning',
  ),
  (
    'paragraph to definition term',
    'Hyperlinks are a canonical example of what',
    'Hypermedia Control',
  ),
  (
    'definition to paragraph',
    'within itself.',
    'Hypermedia controls are what differentiate',
  ),
  (
    'paragraph to listing caption',
    'Here is what the code looks like for this handler',
    'A handler for server-side search',
  ),
  (
    'paragraph to code (no caption)',
    'Here is the new handler code',
    '@app.route("/contacts/<contact_id>/edit"',
  ),
  (
    'listing caption to code',
    'The "new contact" controller code',
    '@app.route("/contacts/new"',
  ),
  ('code line pitch', 'def contacts_new():', 'c = Contact('),
  (
    'code to callout list',
    'return render_template("new.html"',
    'We construct a new contact object',
  ),
  (
    'callout list item to item',
    'We construct a new contact object',
    'We try to save it',
  ),
  (
    'callout list to paragraph',
    'On failure, re-render the form',
    'The logic in this handler is a bit more complex',
  ),
  (
    'bullet item to item',
    'Then, when a user clicks on the text',
    'The browser will issue an HTTP GET',
  ),
  (
    'sidebar title to text',
    'Factoring Your Applications',
    'One thing that often trips people up',
  ),
  (
    'paragraph to sidebar',
    'For our purposes, however, since our application is small',
    'Factoring Your Applications',
  ),
  (
    'subsection heading to paragraph',
    'Why Only Anchors',
    'Consider: what makes anchor tags',
  ),
];

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'usage: dart run tool/hs/spacing.dart TYPST.pdf ASCIIDOC.pdf',
    );
    exit(64);
  }
  final a = _lines(args[0]);
  final b = _lines(args[1]);
  stdout
    ..writeln('| Probe | Typst | AsciiDoc | Difference |')
    ..writeln('| --- | --- | --- | --- |');
  for (final (name, first, second) in _probes) {
    final x = _distance(a, first, second);
    final y = _distance(b, first, second);
    String show(double? d) => d == null ? 'not found' : d.toStringAsFixed(1);
    final diff = x != null && y != null
        ? (y - x >= 0 ? '+' : '') + (y - x).toStringAsFixed(1)
        : '';
    stdout.writeln('| $name | ${show(x)} | ${show(y)} | $diff |');
  }
}

String _key(String text) => text.toLowerCase().replaceAll(
  RegExp(
    r'[\s“”"‘’'
    ']+',
  ),
  '',
);

/// The distance from the top of the first line that starts (or ends)
/// with [first] to the top of the next line, within six, that contains
/// [second] on the same page.
double? _distance(List<_Line> lines, String first, String second) {
  final a = _key(first);
  final b = _key(second);
  for (var i = 0; i < lines.length; i++) {
    if (!_key(lines[i].text).contains(a)) continue;
    for (var j = i + 1; j < lines.length && j <= i + 6; j++) {
      if (lines[j].page != lines[i].page) break;
      if (_key(lines[j].text).contains(b)) return lines[j].top - lines[i].top;
    }
  }
  return null;
}

/// The lines of [pdf], in reading order.
List<_Line> _lines(String pdf) {
  final xml =
      Process.runSync('pdftotext', ['-bbox-layout', pdf, '-']).stdout as String;
  final lines = <_Line>[];
  var page = -1;
  for (final m in RegExp(
    r'<page |<line xMin="[\d.]+" yMin="([\d.]+)" xMax="[\d.]+" yMax="([\d.]+)">([\s\S]*?)</line>',
  ).allMatches(xml)) {
    if (m[0] == '<page ') {
      page++;
      continue;
    }
    final words = [
      for (final w in RegExp('<word[^>]*>([^<]*)</word>').allMatches(m[3]!))
        w[1]!
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'"),
    ];
    lines.add((
      page: page,
      top: double.parse(m[1]!),
      bottom: double.parse(m[2]!),
      text: words.join(' '),
    ));
  }
  return lines;
}
