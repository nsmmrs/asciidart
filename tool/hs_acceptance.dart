// The Hypermedia Systems acceptance run (lane TASK-stcstl): builds the
// book's AsciiDoc sources as PDF, HTML, EPUB 3 and DocBook 5 with the
// asciidart executable, each in one command, and checks what the book's
// authors had to fix by hand.
//
// Usage: dart run tool/hs_acceptance.dart [--exe PATH] [--out DIR]
//            [--report FILE]
//
// With --report, the results table replaces the one in FILE (such as
// benchmark/HS.md), the rest kept; a new FILE has the table alone.
//
// The sources (bigskysoftware/hypermedia-systems-old, whose book/ isn't
// under its repository's license) are cloned at a pinned commit into
// ~/.cache/asciidart-work/hs-old and never vendored; EPUBCheck and the
// DocBook 5.0 RELAX NG schema are fetched into ~/.cache/asciidart-work/tools.
// Needs git, curl, unzip, java, xmllint, pdftotext and qpdf. Heavy: run it
// in a capped unit.
import 'dart:convert';
import 'dart:io';

import 'package:asciidart/src/internal.dart';

const _repository =
    'https://github.com/bigskysoftware/hypermedia-systems-old.git';
const _commit = '2e8c4be47f64de281d0e325599bcbe69e7ed05ce';
const _epubcheck =
    'https://github.com/w3c/epubcheck/releases/download/v5.4.0/epubcheck-5.4.0.zip';
const _docbookSchema = 'https://cdn.docbook.org/schema/5.0/rng/docbook.rng';

final String _cache = '${Platform.environment['HOME']}/.cache/asciidart-work';

Future<void> main(List<String> args) async {
  var exe = 'dist/asciidart-linux-x64';
  var out = '$_cache/hs-out';
  String? report;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--exe':
        exe = args[++i];
      case '--out':
        out = args[++i];
      case '--report':
        report = args[++i];
    }
  }
  exe = File(exe).absolute.path;
  final sources = _sources();
  final tools = _tools();
  final outDir = Directory(out)..createSync(recursive: true);
  final theme = File('tool/hs/hs-theme.yml').absolute.path;
  final rows = <(String, String, String)>[];
  // A table row; the result is pass, fail or n/a (null).
  // ignore: avoid_positional_boolean_parameters
  void row(String check, bool? ok, String detail) =>
      rows.add((check, ok == null ? 'n/a' : (ok ? 'pass' : 'FAIL'), detail));

  // The builds.
  final pdfArgs = [
    '-b',
    'pdf',
    '-a',
    'hypermedia-systems-pdf',
    '-a',
    'pdf-theme=$theme',
    '-a',
    'pdf-fontsdir=${sources.path}/fonts;GEM_FONTS_DIR',
  ];
  final builds = {
    'PDF': (pdfArgs, '${outDir.path}/HypermediaSystems.pdf'),
    'HTML': (
      ['-b', 'html5', '-a', 'callout-links'],
      '${outDir.path}/HypermediaSystems.html',
    ),
    'EPUB 3': (
      ['-b', 'epub3', '-a', 'callout-links'],
      '${outDir.path}/HypermediaSystems.epub',
    ),
    'DocBook 5': (['-b', 'docbook5'], '${outDir.path}/HypermediaSystems.xml'),
  };
  final timings = <String, Duration>{};
  for (final MapEntry(key: name, value: (options, file)) in builds.entries) {
    final (result, time) = _convert(exe, sources, options, file);
    timings[name] = time;
    final messages = _messages(result.stderr as String);
    final errors = messages.where((m) => m.contains('ERROR')).length;
    row(
      '$name build',
      result.exitCode == 0 && File(file).existsSync(),
      '${time.inMilliseconds} ms, ${_size(file)}, $errors errors, '
          '${messages.length - errors} warnings',
    );
  }
  final pdf = builds['PDF']!.$2;

  // The same bytes twice.
  final again = '${outDir.path}/again.pdf';
  _convert(exe, sources, pdfArgs, again);
  row('PDF byte-stable across runs', _same(pdf, again), 'SOURCE_DATE_EPOCH=0');

  // Every listing line as often as in the HTML (which has no pages to
  // split listings across), none cropped.
  final listings = _listingLines(sources);
  // Layout mode: the default joins a word hyphenated across lines. Each
  // page's last line (the theme's footer) is left out: a listing line
  // wrapped across a page break goes on after it.
  final text = _normalize(
    [
      for (final page
          in (_run('pdftotext', ['-layout', pdf, '-']).stdout as String).split(
            '\f',
          ))
        _withoutLastLine(page),
    ].join('\n'),
  );
  // The HTML's callout markers left out, as the PDF's are, and its index
  // (whose links are labeled with section titles; the PDF's, with page
  // numbers).
  final htmlText = _normalize(
    _htmlText(
      File(builds['HTML']!.$2)
          .readAsStringSync()
          .replaceAll(RegExp(r'<b class="conum">\(\d+\)</b>'), '')
          .replaceAll(
            RegExp(r'<div class="index">[\s\S]*?</ul>\n</div>\n</div>'),
            '',
          ),
    ),
  );
  var dropped = 0;
  var repeated = 0;
  final examples = <String>[];
  // Without spaces: a line wrapped across two lines still counts.
  final compactPdf = text.replaceAll(' ', '');
  final compactHtml = htmlText.replaceAll(' ', '');
  for (final line in listings.keys) {
    final compact = line.replaceAll(' ', '');
    final count = _count(compactHtml, compact);
    final found = _count(compactPdf, compact);
    if (found < count) {
      dropped++;
      if (examples.length < 3) examples.add('missing: "$line"');
    } else if (found > count) {
      repeated++;
      if (examples.length < 3) examples.add('repeated: "$line"');
    }
  }
  row(
    'PDF has each listing line once (#122)',
    dropped == 0 && repeated == 0,
    '${listings.length} distinct lines of 24+ characters: $dropped missing, '
        '$repeated repeated'
        '${examples.isEmpty ? '' : '; ${examples.join('; ')}'}',
  );
  final cropped = _beyondEdges(pdf);
  row(
    'PDF crops no text (#106)',
    cropped.$1 == 0,
    '${cropped.$1} words past the page edge, ${cropped.$2} past the margin',
  );

  // The index and the page numbers.
  final layout = _run('pdftotext', ['-layout', pdf, '-']).stdout as String;
  final indexAt = layout.lastIndexOf(RegExp(r'\n\s*Index\s*\n'));
  final entries = indexAt < 0
      ? 0
      : RegExp(r'[^\s,], \d+').allMatches(layout.substring(indexAt)).length;
  row(
    'PDF index with page numbers',
    indexAt >= 0 && entries > 20,
    '$entries entries with page numbers',
  );
  final labels = _labels(pdf);
  final roman =
      labels.isNotEmpty && RegExp(r'^[ivxlc]+$').hasMatch(labels.first);
  final body = labels.indexOf('1');
  row(
    'PDF front matter roman, body arabic from 1',
    roman && body > 0,
    labels.isEmpty
        ? 'no page labels'
        : 'first labels ${labels.take(6).join(' ')}; "1" on page ${body + 1}',
  );
  row(
    'PDF time for the whole book',
    timings['PDF']!.inSeconds < 60,
    '${timings['PDF']!.inMilliseconds} ms for ${labels.length} pages',
  );

  // HTML index.
  final html = File(builds['HTML']!.$2).readAsStringSync();
  final indexLinks = RegExp('href="#_indexterm_').allMatches(html).length;
  row('HTML index with links', indexLinks > 0, '$indexLinks links to uses');
  final calloutLinks = RegExp('class="conum-link"').allMatches(html).length;
  final calloutBacks = RegExp('class="conum-back"').allMatches(html).length;
  row(
    'HTML callouts linked both ways (callout-links)',
    calloutLinks > 0 && calloutBacks > 0,
    '$calloutLinks markers, $calloutBacks items',
  );

  // Validity.
  final docbook = _run('xmllint', [
    '--noout',
    '--relaxng',
    tools.schema,
    builds['DocBook 5']!.$2,
  ]);
  final docbookErrors = (docbook.stderr as String)
      .split('\n')
      .where((l) => l.contains('error') || l.contains('fails to validate'))
      .toList();
  row(
    'DocBook 5 validates (RELAX NG 5.0)',
    docbook.exitCode == 0,
    docbookErrors.isEmpty
        ? 'valid'
        : '${docbookErrors.length} errors; ${docbookErrors.first.trim()}',
  );
  final epub = _run('java', [
    '-jar',
    tools.epubcheck,
    '--quiet',
    builds['EPUB 3']!.$2,
  ]);
  final epubErrors = '${epub.stdout}${epub.stderr}'
      .split('\n')
      .where((l) => l.startsWith('ERROR') || l.startsWith('FATAL'))
      .toList();
  row(
    'EPUBCheck passes',
    epub.exitCode == 0,
    epubErrors.isEmpty
        ? 'no errors'
        : '${epubErrors.length} errors; ${epubErrors.first}',
  );

  final table = StringBuffer()
    ..writeln('| Check | Result | Detail |')
    ..writeln('| --- | --- | --- |');
  for (final (check, result, detail) in rows) {
    table.writeln('| $check | $result | ${detail.replaceAll('|', r'\|')} |');
  }
  stdout.write(table);
  if (report != null) _writeReport(File(report), table.toString());
}

/// The sources at the pinned commit, with the master file at the root of
/// the repository, where its includes and images are relative to.
Directory _sources() {
  final dir = Directory('$_cache/hs-old');
  if (!dir.existsSync()) {
    _check(_run('git', ['clone', '-q', _repository, dir.path]));
  }
  final head =
      (_run('git', ['-C', dir.path, 'rev-parse', 'HEAD']).stdout as String)
          .trim();
  if (head != _commit) {
    _check(_run('git', ['-C', dir.path, 'fetch', '-q', 'origin', _commit]));
    _check(_run('git', ['-C', dir.path, 'checkout', '-q', _commit]));
  }
  // The master file at the root, where its includes and images are
  // relative to, with an index: the book's index (book/INDEX.adoc) was
  // made by hand, for want of one in the HTML; this one is generated.
  final master = File('${dir.path}/book/HypermediaSystems.adoc')
      .readAsStringSync();
  File('${dir.path}/HypermediaSystems.adoc')
      .writeAsStringSync('${master.trimRight()}\n\n[index]\n= Index\n');
  return dir;
}

/// EPUBCheck and the DocBook schema, fetched once.
({String epubcheck, String schema}) _tools() {
  final dir = Directory('$_cache/tools')..createSync(recursive: true);
  final jar = '${dir.path}/epubcheck-5.4.0/epubcheck.jar';
  if (!File(jar).existsSync()) {
    _check(_run('curl', ['-sSLo', '${dir.path}/epubcheck.zip', _epubcheck]));
    _check(_run('unzip', ['-qo', '${dir.path}/epubcheck.zip', '-d', dir.path]));
  }
  final schema = '${dir.path}/docbook.rng';
  if (!File(schema).existsSync()) {
    _check(_run('curl', ['-sSLo', schema, _docbookSchema]));
  }
  return (epubcheck: jar, schema: schema);
}

(ProcessResult, Duration) _convert(
  String exe,
  Directory sources,
  List<String> options,
  String file,
) {
  final watch = Stopwatch()..start();
  final result = Process.runSync(
    exe,
    ['-S', 'unsafe', ...options, '-o', file, 'HypermediaSystems.adoc'],
    workingDirectory: sources.path,
    environment: {'SOURCE_DATE_EPOCH': '0', 'TZ': 'UTC'},
  );
  return (result, watch.elapsed);
}

/// The distinct lines of 24 characters or more in the book's listings
/// (callout markers dropped, spaces collapsed), with how often each
/// occurs.
Map<String, int> _listingLines(Directory sources) {
  final document = loadFile(
    '${sources.path}/HypermediaSystems.adoc',
    options: AsciidoctorOptions(
      safe: SafeMode.unsafe,
      attributes: const {'hypermedia-systems-pdf': ''},
      logger: MemoryLogger(),
    ),
  );
  final counts = <String, int>{};
  for (final block in document.findBy(context: BlockContext.listing)) {
    if (block is! Block) continue;
    for (final line in block.lines) {
      final text = _normalize(
        line.replaceAll(
          RegExp(r'\s*(?://|#|<!--)?\s*<\d+>\s*(?:-->)?\s*$'),
          '',
        ),
      );
      if (text.length >= 24) counts[text] = (counts[text] ?? 0) + 1;
    }
  }
  return counts;
}

/// Writes [table] into [file] in place of the table there (and the date
/// of the `## Latest run` heading), or alone into a new file.
void _writeReport(File file, String table) {
  if (!file.existsSync()) {
    file.writeAsStringSync(table);
    return;
  }
  final lines = file.readAsLinesSync();
  final start = lines.indexWhere((line) => line.startsWith('| Check |'));
  if (start < 0) {
    file.writeAsStringSync('${lines.join('\n')}\n\n$table');
    return;
  }
  var end = start;
  while (end < lines.length && lines[end].startsWith('|')) {
    end++;
  }
  final today = DateTime.now().toIso8601String().substring(0, 10);
  final kept = [
    for (final line in lines.sublist(0, start))
      if (line.startsWith('## Latest run ('))
        '## Latest run ($today)'
      else
        line,
    table.trimRight(),
    ...lines.sublist(end),
  ];
  file.writeAsStringSync('${kept.join('\n')}\n');
}

/// [page] without its last line that has text.
String _withoutLastLine(String page) {
  final lines = page.trimRight().split('\n');
  if (lines.isNotEmpty) lines.removeLast();
  return lines.join('\n');
}

/// The text of the HTML [html]: tags dropped, character references
/// resolved.
String _htmlText(String html) => html
    .replaceAll(RegExp('<[^>]*>'), ' ')
    .replaceAllMapped(RegExp('&(#x?[0-9a-fA-F]+|[a-z]+);'), (m) {
      final ref = m[1]!;
      if (ref.startsWith('#x')) {
        return String.fromCharCode(int.parse(ref.substring(2), radix: 16));
      }
      if (ref.startsWith('#')) {
        return String.fromCharCode(int.parse(ref.substring(1)));
      }
      return switch (ref) {
        'lt' => '<',
        'gt' => '>',
        'amp' => '&',
        'quot' => '"',
        'apos' => "'",
        'nbsp' => ' ',
        _ => m[0]!,
      };
    });

String _normalize(String text) =>
    text.replaceAll(' ', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

int _count(String text, String needle) {
  var count = 0;
  var at = text.indexOf(needle);
  while (at >= 0) {
    count++;
    at = text.indexOf(needle, at + needle.length);
  }
  return count;
}

/// The words past a page's edge, and past its widest margin.
(int, int) _beyondEdges(String pdf) {
  final bbox = _run('pdftotext', ['-bbox', pdf, '-']).stdout as String;
  var pastEdge = 0;
  var pastMargin = 0;
  var width = 0.0;
  for (final line in bbox.split('\n')) {
    if (RegExp(r'<page width="([\d.]+)"').firstMatch(line) case final m?) {
      width = double.parse(m[1]!);
    } else if (RegExp(r'xMax="([\d.]+)"').firstMatch(line) case final m?) {
      final xMax = double.parse(m[1]!);
      if (xMax > width + 0.5) pastEdge++;
      if (xMax > width - 72 + 1) pastMargin++;
    }
  }
  return (pastEdge, pastMargin);
}

List<String> _labels(String pdf) {
  final json = _run('qpdf', ['--json', '--json-key=pagelabels', pdf]).stdout;
  final data = jsonDecode(json as String) as Map<String, Object?>;
  final labels = data['pagelabels'];
  if (labels is! List) return const [];
  // Expand the ranges to one label per page.
  final pages =
      int.tryParse(
        RegExp(r'Pages:\s+(\d+)')
                .firstMatch(_run('pdfinfo', [pdf]).stdout as String)?[1] ??
            '',
      ) ??
      0;
  final starts = <(int, String, int, String)>[];
  for (final entry in labels) {
    if (entry is! Map<String, Object?>) continue;
    final index = entry['index'];
    final label = entry['label'];
    if (index is! int || label is! Map<String, Object?>) continue;
    final prefix = (label['/P'] as String? ?? '').replaceFirst('u:', '');
    final style = label['/S'] as String? ?? '';
    final start = label['/St'] as int? ?? 1;
    starts.add((index, prefix, start, style));
  }
  final result = <String>[];
  for (var page = 0; page < pages; page++) {
    final (index, prefix, start, style) = starts.lastWhere(
      (s) => s.$1 <= page,
      orElse: () => (0, '', 1, ''),
    );
    final n = start + page - index;
    result.add(switch (style) {
      '/D' => '$prefix$n',
      '/r' => '$prefix${_roman(n)}',
      _ => prefix,
    });
  }
  return result;
}

String _roman(int n) {
  const values = [100, 90, 50, 40, 10, 9, 5, 4, 1];
  const letters = ['c', 'xc', 'l', 'xl', 'x', 'ix', 'v', 'iv', 'i'];
  final out = StringBuffer();
  var rest = n;
  for (var i = 0; i < values.length; i++) {
    while (rest >= values[i]) {
      out.write(letters[i]);
      rest -= values[i];
    }
  }
  return out.toString();
}

List<String> _messages(String stderr) => [
  for (final line in stderr.split('\n'))
    if (line.startsWith('asciidart:')) line,
];

bool _same(String a, String b) {
  final x = File(a).readAsBytesSync();
  final y = File(b).readAsBytesSync();
  if (x.length != y.length) return false;
  for (var i = 0; i < x.length; i++) {
    if (x[i] != y[i]) return false;
  }
  return true;
}

String _size(String file) {
  final f = File(file);
  if (!f.existsSync()) return 'no file';
  return '${(f.lengthSync() / 1024).round()} KB';
}

ProcessResult _run(String executable, List<String> args) =>
    Process.runSync(executable, args, stdoutEncoding: utf8);

void _check(ProcessResult result) {
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
    exit(1);
  }
}
