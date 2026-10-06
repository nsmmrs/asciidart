// A page of two PDFs side by side, word by word (lane EPIC-n7s6v0): for
// each word in reading order, its box in the first PDF (G) and in the
// second (A), and the differences, to see what a raster difference is
// made of (text, wrapping, spacing).
//
// Usage: dart run tool/hs/page_lines.dart FIRST.pdf SECOND.pdf PAGE [PAGE2]
//
// PAGE2 is the second PDF's page (PAGE by default). Needs pdftotext.
import 'dart:io';

typedef _Word = ({
  String text,
  double left,
  double top,
  double right,
  double bottom,
});

void main(List<String> args) {
  if (args.length < 3) {
    stderr.writeln(
      'usage: dart run tool/hs/page_lines.dart FIRST.pdf SECOND.pdf PAGE [PAGE2]',
    );
    exit(64);
  }
  final page = int.parse(args[2]);
  final a = _words(args[0], page);
  final b = _words(args[1], args.length > 3 ? int.parse(args[3]) : page);
  String f(double d) => d.toStringAsFixed(2).padLeft(7);
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : null;
    final y = i < b.length ? b[i] : null;
    if (x != null && y != null && x.text == y.text) {
      final dl = y.left - x.left;
      final dt = y.top - x.top;
      final dw = (y.right - y.left) - (x.right - x.left);
      final dh = (y.bottom - y.top) - (x.bottom - x.top);
      final same = [dl, dt, dw, dh].every((d) => d.abs() < 0.01);
      stdout.writeln(
        '${same ? ' ' : '*'} ${x.text.padRight(24)} G ${f(x.left)} ${f(x.top)}'
        '  Δx ${f(dl)} Δy ${f(dt)} Δw ${f(dw)} Δh ${f(dh)}',
      );
    } else {
      stdout
        ..writeln(
          '! G ${x == null ? '-' : '${x.text} ${f(x.left)} ${f(x.top)}'}',
        )
        ..writeln(
          '! A ${y == null ? '-' : '${y.text} ${f(y.left)} ${f(y.top)}'}',
        );
    }
  }
}

List<_Word> _words(String pdf, int page) {
  final xml =
      Process.runSync('pdftotext', [
            '-f',
            '$page',
            '-l',
            '$page',
            '-bbox',
            pdf,
            '-',
          ]).stdout
          as String;
  // Callout markers left out: asciidart marks them as artifacts (not in
  // the text), Typst doesn't.
  return [
    for (final m in RegExp(
      r'<word xMin="([\d.]+)" yMin="([\d.]+)" xMax="([\d.]+)" yMax="([\d.]+)">([^<]*)</word>',
    ).allMatches(xml))
      (
        text: m[5]!
            .replaceAll('&amp;', '&')
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&quot;', '"')
            .replaceAll('&#39;', "'"),
        left: double.parse(m[1]!),
        top: double.parse(m[2]!),
        right: double.parse(m[3]!),
        bottom: double.parse(m[4]!),
      ),
  ].where((w) => !RegExp(r'^\[\d+\]$').hasMatch(w.text)).toList();
}
