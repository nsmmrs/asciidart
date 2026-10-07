/// The `asciidoctor-compat` setting (ADR-0015): the formats whose output
/// keeps Asciidoctor's look, for projects migrating from Asciidoctor.
library;

import 'package:asciidart/src/constants.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/logging.dart';
import 'package:asciidart/src/stylesheets.dart';

/// The output formats `asciidoctor-compat` can name.
enum CompatFormat {
  /// HTML pages and the website (html5, xhtml5, multipage_html5).
  html({'html', 'html5', 'xhtml', 'xhtml5', 'multipage_html5', 'website'}),

  /// EPUB (epub3).
  epub({'epub', 'epub3'}),

  /// DocBook (docbook5).
  docbook({'docbook', 'docbook5'}),

  /// Man pages.
  manpage({'manpage'}),

  /// PDF.
  pdf({'pdf'});

  new(this.names);

  /// The names that select this format in a list.
  final Set<String> names;

  /// The format [name] selects, or null when it names none.
  static CompatFormat? named(String name) {
    final key = name.trim().toLowerCase();
    for (final format in values) {
      if (format.names.contains(key)) return format;
    }
    return null;
  }
}

/// The formats a value of `asciidoctor-compat` names: every format for
/// `true` or an empty value, none for `false`, else those of the
/// comma-separated list. Names that select no format are passed to
/// [onUnknown].
Set<CompatFormat> parseCompat(
  String value, {
  void Function(String name)? onUnknown,
}) {
  switch (value.trim().toLowerCase()) {
    case '' || 'true' || 'all':
      return CompatFormat.values.toSet();
    case 'false' || 'none':
      return const {};
  }
  final formats = <CompatFormat>{};
  for (final name in value.split(',').map((name) => name.trim())) {
    if (name.isEmpty) continue;
    if (CompatFormat.named(name) case final format?) {
      formats.add(format);
    } else {
      onUnknown?.call(name);
    }
  }
  return formats;
}

final Expando<Set<CompatFormat>> _documentCompat = Expando();

/// Whether [document]'s `asciidoctor-compat` setting names [format].
/// `pdf-compat` names the PDF too.
bool asciidoctorCompat(Document document, CompatFormat format) {
  if (format == CompatFormat.pdf && document.hasAttr('pdf-compat')) {
    return true;
  }
  final formats = _documentCompat[document] ??= switch (document.attr(
    'asciidoctor-compat',
  )) {
    null => const {},
    final value => parseCompat(
      value,
      onUnknown: (name) => LoggerManager.logger.warn(
        'asciidoctor-compat: unknown format: $name (expected html, epub, '
        'docbook, manpage or pdf)',
      ),
    ),
  };
  return formats.contains(format);
}

/// [document]'s `stylesheet` attribute as the HTML converters read it:
/// Asciidoctor's stylesheet alone ([Stylesheets.classicStylesheetKey]) in
/// place of the default one when `asciidoctor-compat` names HTML.
String? htmlStylesheetKey(Document document) {
  final key = document.attr('stylesheet');
  return defaultStylesheetKeys.contains(key) &&
          asciidoctorCompat(document, CompatFormat.html)
      ? Stylesheets.classicStylesheetKey
      : key;
}
