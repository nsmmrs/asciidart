// Lists the theme keys documented in asciidoctor-pdf's theming guide that
// the PDF converter never reads, over a corpus of documents: the keys it
// doesn't honor (or that the corpus doesn't exercise).
//
// Usage: dart run tool/pdf_theme_keys.dart THEME_DOCS_DIR CORPUS_DIR
//
// THEME_DOCS_DIR is docs/modules/theme/pages of asciidoctor-pdf 2.3.27;
// the documented keys are the ones its YAML examples set. CORPUS_DIR holds
// documents with their options (`<doc>.opts`, as tool/pdf_spec_corpus.dart
// writes them), converted in process with the theme's lookups recorded.
// Keys named after something the document chooses (a role, an icon, a
// font) count as read when the converter reads the same key for any name.
import 'dart:io';

import 'package:ptome/src/internal.dart';
import 'package:ptome/src/pdf/pdf.dart';
import 'package:ptome/src/pdf/theme.dart';

import 'vendored_fonts.dart';

void main(List<String> args) {
  useVendoredFonts();
  if (args.length != 2) {
    stderr.writeln('usage: pdf_theme_keys.dart THEME_DOCS_DIR CORPUS_DIR');
    exitCode = 64;
    return;
  }
  registerPdf();
  final documented = _documentedKeys(Directory(args[0]));
  final read = <String>{};
  Theme.lookups = read;
  final out = Directory.systemTemp.createTempSync('pdf-theme-keys.');
  final documents =
      Directory(args[1])
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.adoc'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final document in documents) {
    final opts = File(document.path.replaceFirst(RegExp(r'\.adoc$'), '.opts'));
    // asciidoctor-pdf's look, its keys read as the gem reads them.
    final attributes = <String, String?>{'asciidoctor-compat': 'pdf'};
    String? doctype;
    if (opts.existsSync()) {
      final lines = opts.readAsLinesSync();
      for (var i = 0; i + 1 < lines.length; i += 2) {
        final value = lines[i + 1];
        if (lines[i] == '-d') {
          doctype = value;
        } else if (value.endsWith('!')) {
          attributes[value.substring(0, value.length - 1)] = null;
        } else {
          final (name, _, text) = value.partition('=');
          attributes[name] = text;
        }
      }
    }
    try {
      convertFile(
        document.path,
        AsciidoctorOptions(
          safe: SafeMode.unsafe,
          backend: 'pdf',
          doctype: doctype,
          attributes: attributes,
          toFile: '${out.path}/out.pdf',
          logger: MemoryLogger(),
        ),
      );
    } on Object catch (error) {
      stderr.writeln('${document.path}: $error');
    }
  }
  out.deleteSync(recursive: true);
  Theme.lookups = null;
  final unread = [
    for (final key in documented)
      if (!read.contains(key) && !read.any((r) => _sameFamily(key, r))) key,
  ];
  stdout
    ..writeln(
      'pdf_theme_keys: ${documented.length} documented keys, '
      '${documented.length - unread.length} read over '
      '${documents.length} documents, ${unread.length} never read:',
    )
    ..writeAll(unread.map((key) => '  $key\n'));
}

/// The prefixes of keys named after something a document or theme
/// chooses, with the number of name segments after them.
const _families = {
  'role_': 1,
  'admonition_icon_': 1,
  'admonition_label_': 0,
  'font_catalog_': 2,
  'ulist_marker_': 1,
  'heading_h': 0,
  'toc_h': 0,
};

/// Whether [key] and [other] are the same key for different names.
bool _sameFamily(String key, String other) {
  for (final MapEntry(key: prefix, value: names) in _families.entries) {
    if (!key.startsWith(prefix) || !other.startsWith(prefix)) continue;
    if (names == 0) return false;
    final a = key.substring(prefix.length).split('_');
    final b = other.substring(prefix.length).split('_');
    if (a.length > names &&
        b.length > names &&
        a.skip(names).join('_') == b.skip(names).join('_')) {
      return true;
    }
  }
  return false;
}

/// The keys the YAML examples of the theming guide in [dir] set.
List<String> _documentedKeys(Directory dir) {
  final keys = <String>{};
  final pages =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.adoc'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final page in pages) {
    final lines = page.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (!RegExp(r'^a?\|\[source(,yaml)?\]$').hasMatch(lines[i].trim())) {
        continue;
      }
      final stack = <(int, String)>[];
      for (i++; i < lines.length; i++) {
        final line = lines[i];
        if (line.startsWith('|') || line.trim().isEmpty) break;
        final trimmed = line.trim();
        if (trimmed.startsWith('#') ||
            trimmed.startsWith('-') ||
            !trimmed.contains(':')) {
          continue;
        }
        final indent = line.length - line.trimLeft().length;
        final (name, _, value) = trimmed.partition(':');
        while (stack.isNotEmpty && stack.last.$1 >= indent) {
          stack.removeLast();
        }
        stack.add((indent, name.trim().replaceAll(RegExp('''['"]'''), '')));
        if (value.trim().isNotEmpty && !value.trim().startsWith('&')) {
          keys.add(
            [for (final (_, segment) in stack) segment]
                .join('_')
                .replaceAll('-', '_'),
          );
        }
      }
    }
  }
  return keys.toList()..sort();
}

extension on String {
  (String, String, String) partition(String separator) {
    final at = indexOf(separator);
    return at < 0
        ? (this, '', '')
        : (substring(0, at), separator, substring(at + separator.length));
  }
}
