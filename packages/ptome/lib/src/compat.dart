/// The `asciidoctor-compat` setting (ADR-0015): the formats whose output
/// keeps Asciidoctor's look, for projects migrating from Asciidoctor.
library;

import 'package:ptome/src/constants.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/stylesheets.dart';

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

/// The formats `document`'s `asciidoctor-compat` names, by the value they
/// were read from (behaviors ask while the header is still read, before an
/// attribute entry may set it).
final Expando<(String?, Set<CompatFormat>)> _documentCompat = Expando();

/// Whether [document]'s `asciidoctor-compat` setting names [format].
/// `pdf-compat` names the PDF too.
bool asciidoctorCompat(Document document, CompatFormat format) {
  if (format == CompatFormat.pdf && document.hasAttr('pdf-compat')) {
    return true;
  }
  final value = document.attr('asciidoctor-compat');
  final cached = _documentCompat[document];
  if (cached != null && cached.$1 == value) return cached.$2.contains(format);
  final formats = switch (value) {
    null => const <CompatFormat>{},
    final value => parseCompat(
      value,
      onUnknown: (name) => LoggerManager.logger.warn(
        'asciidoctor-compat: unknown format: $name (expected html, epub, '
        'docbook, manpage or pdf)',
      ),
    ),
  };
  _documentCompat[document] = (value, formats);
  return formats.contains(format);
}

/// [document]'s `stylesheet` attribute as the HTML converters read it: the
/// stylesheet of Asciidoctor's latest stable release
/// ([Stylesheets.stableStylesheetKey]) in place of the default one when
/// `asciidoctor-compat` names HTML.
String? htmlStylesheetKey(Document document) {
  final key = document.attr('stylesheet');
  return defaultStylesheetKeys.contains(key) &&
          asciidoctorCompat(document, CompatFormat.html)
      ? Stylesheets.stableStylesheetKey
      : key;
}

/// A behavior of Ptome's engine that Asciidoctor's latest stable release
/// (2.0.26) has otherwise: Ptome follows Asciidoctor's main line, and
/// `asciidoctor-compat` takes the stable release's value, for the format
/// the behavior is part of. Each is an attribute of its own, so a document
/// can choose either way whatever `asciidoctor-compat` says.
enum Behavior {
  /// How HTML gives a table's width, its columns' and a horizontal
  /// description list's: `attribute` (`width="50%"`, as Asciidoctor's main
  /// line writes them) or `style` (`style="width: 50%;"`).
  htmlWidths('html-widths', CompatFormat.html, 'attribute', 'style'),

  /// Where highlight.js highlights source blocks in HTML: `server` (at
  /// conversion, with the theme's stylesheet linked) or `client` (in the
  /// browser, highlight.js 9.18.3 loaded from its CDN, as Asciidoctor does).
  highlightjsMode('highlightjs-mode', CompatFormat.html, 'server', 'client'),

  /// When HTML says which program wrote it (`<meta name="generator">`):
  /// `unless-reproducible` (not with the `reproducible` attribute) or
  /// `always`.
  htmlGenerator(
    'html-generator',
    CompatFormat.html,
    'unless-reproducible',
    'always',
  ),

  /// How HTML lists the sections (the table of contents): `ptome` (a
  /// multipart book's parts at level 0, each entry below the top level
  /// classed with its level, a section's own `toclevels`, at least one
  /// level) or `2.0.26` (as Asciidoctor 2.0.26 lists them).
  htmlToc('html-toc', CompatFormat.html, 'ptome', '2.0.26'),

  /// How HTML marks a page break: `class` (`<div class="page-break">`) or
  /// `style` (`style="page-break-after: always;"`).
  htmlPageBreak('html-page-break', CompatFormat.html, 'class', 'style'),

  /// Whether an HTML thematic break keeps its role (`[.fancy]`): `kept` or
  /// `dropped`.
  htmlBreakRoles('html-break-roles', CompatFormat.html, 'kept', 'dropped'),

  /// How HTML shows a Wistia video (`video::id[wistia]`): `embed` (Wistia's
  /// player) or `video` (a video element, as for a file).
  htmlWistia('html-wistia', CompatFormat.html, 'embed', 'video'),

  /// Whether a source block's `nohighlight` option leaves it unhighlighted
  /// in HTML: `honored` or `ignored`.
  htmlNohighlight('html-nohighlight', CompatFormat.html, 'honored', 'ignored'),

  /// Whether DocBook says which quotes quoted text has (`<quote
  /// role="double">`): `written` or `none`.
  docbookQuoteRoles(
    'docbook-quote-roles',
    CompatFormat.docbook,
    'written',
    'none',
  ),

  // The language, in every format (the format converted to decides).

  /// What an empty ID (`[[]]`, `[#]`) gives a section: `none` (no ID) or
  /// `empty` (an empty one).
  emptyIds('empty-ids', null, 'none', 'empty'),

  /// Whether four tildes (`~~~~`) delimit an open block: `open` or `text`.
  tildeBlocks('tilde-blocks', null, 'open', 'text'),

  /// Whether `{cxx}` is an intrinsic attribute (C++): `defined` or
  /// `undefined`.
  cxxAttribute('cxx-attribute', null, 'defined', 'undefined'),

  /// Whether an ordered list's first marker (`3.`) sets where it starts:
  /// `marker` or `one`.
  listStart('list-start', null, 'marker', 'one'),

  /// The attributes of the link an include falls back to (a target it
  /// can't read as a file): `all` (`role=include` and the directive's own)
  /// or `role` (`role=include` alone).
  includeLink('include-link', null, 'all', 'role'),

  /// What `link=self` on an image links to: `image` (the image itself) or
  /// `self` (the URL `self`).
  linkSelf('link-self', null, 'image', 'self'),

  /// Whether an inline image keeps its ID (`image:a.png[id=x]`): `kept` or
  /// `dropped`.
  inlineImageIds('inline-image-ids', null, 'kept', 'dropped'),

  /// Whether an include's `skip-front-matter` option drops the included
  /// file's front matter: `honored` or `ignored`.
  includeFrontMatter('include-front-matter', null, 'honored', 'ignored'),

  /// What a block style above the document title (`[preface]`) makes of
  /// it: `section` (a section of that style; the document has no header)
  /// or `title` (the document title; the style is dropped).
  doctitleStyle('doctitle-style', null, 'section', 'title'),

  /// Whether an inline image's own `imagesdir` (`image:a.png[imagesdir=x]`)
  /// wins over the document's: `kept` or `replaced`.
  inlineImagesdir('inline-imagesdir', null, 'kept', 'replaced');

  new(this.attribute, this.format, this.ptome, this.stable);

  /// The attribute that sets it.
  final String attribute;

  /// The format whose `asciidoctor-compat` takes the stable value (null:
  /// the language, which the format converted to decides).
  final CompatFormat? format;

  /// Ptome's value.
  final String ptome;

  /// The value of Asciidoctor's latest stable release.
  final String stable;

  /// The value for [document]: its attribute, else the stable release's
  /// when it is converted to [format] with `asciidoctor-compat` naming it,
  /// else Ptome's.
  String of(Document document) {
    if (document.attr(attribute) case final value?) return value;
    final converted = CompatFormat.named(document.attr('backend') ?? 'html5');
    final applies = format == null || converted == format;
    return applies &&
            converted != null &&
            asciidoctorCompat(document, converted)
        ? stable
        : ptome;
  }
}
