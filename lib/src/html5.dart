/// HTML5 converter: generates HTML 5 output from a parsed document.
///
/// Port of `lib/asciidoctor/converter/html5.rb`. Per
/// `adr/0001-dart-rewrite-goals.md` (D4) every template method produces
/// output byte-identical to Asciidoctor 2.0.26, including whitespace.
///
/// ## Framework integration
///
/// [BuiltInConverter] dispatches each node to `convertBlock` or
/// `convertInline` below, by its kind; a kind with no conversion here (list
/// items, table cells) warns and produces nothing. The
/// converter registers itself explicitly with `Converter.registerFor`.
///
/// Syntax highlighting goes through the document's [SyntaxHighlighterBase].
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/helpers.dart';
import 'package:asciidart/src/highlight/highlight.dart' show CssMode;
import 'package:asciidart/src/highlight/syntax_highlighter.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/list.dart';
import 'package:asciidart/src/ruby_semantics.dart';
import 'package:asciidart/src/rx.dart';
import 'package:asciidart/src/section.dart';
import 'package:asciidart/src/stylesheets.dart';
import 'package:asciidart/src/table.dart';
import 'package:asciidart/src/text_case.dart';

/// Renders [value] for interpolation into output: `null` renders as the
/// empty string.
String _s(String? value) => value ?? '';

/// Repeats [value] [count] times.
String _repeat(String value, int count) =>
    count <= 0 ? '' : List<String>.filled(count, value).join();

/// Splits [value] on the first [separator] into two parts.
(String, String?) _split2(String value, String separator) {
  final idx = value.indexOf(separator);
  return idx == -1
      ? (value, null)
      : (value.substring(0, idx), value.substring(idx + 1));
}

/// Strips anchor tags (port of `DropAnchorRx` in `html5.rb`).
final RegExp _dropAnchorRx = RegExp(r'<(?:a\b[^>]*|/a)>');

/// Matches leading section-title anchors (port of `LeadingAnchorsRx`).
final RegExp _leadingAnchorsRx = RegExp('^(?:<a id="[^"]+"></a>)+');

/// Matches stem line breaks (port of `StemBreakRx`).
final RegExp _stemBreakRx = RegExp(r' *\\\n(?:\\?\n)*|\n\n+');

/// Matches everything before the `<svg` start tag (port of
/// `SvgPreambleRx`; `^` without `multiLine` anchors at the start of the
/// input).
final RegExp _svgPreambleRx = RegExp(
  r'^.*?(?=<svg[ \t\n\v\f\r>])',
  dotAll: true,
);

/// Matches the `<svg` start tag (port of `SvgStartTagRx`).
final RegExp _svgStartTagRx = RegExp(r'^<svg(?:[ \t\n\v\f\r][^>]*)?>');

/// Matches `width`/`height`/`style` attributes on the `<svg` start tag
/// (port of `DimensionAttributeRx`; `CC_ANY` is `.`).
final RegExp _dimensionAttributeRx = RegExp(
  r'''[ \t\n\v\f\r](?:width|height|style)=(["']).*?\1''',
);

/// Block math delimiters by stem style (port of `BLOCK_MATH_DELIMITERS`).
const Map<String, List<String>> _blockMathDelimiters = <String, List<String>>{
  'asciimath': <String>[r'\$', r'\$'],
  'latexmath': <String>[r'\[', r'\]'],
};

/// Inline math delimiters by stem style (port of `INLINE_MATH_DELIMITERS`).
const Map<String, List<String>> _inlineMathDelimiters = <String, List<String>>{
  'asciimath': <String>[r'\$', r'\$'],
  'latexmath': <String>[r'\(', r'\)'],
};

/// Renders [delimiters] as a bracketed list of double-quoted strings with
/// backslash escapes, as embedded in the MathJax configuration script
/// (verified against Asciidoctor's output).
String _inspectDelimiters(List<String> delimiters) {
  final quoted = delimiters.map(
    (delimiter) => '"${delimiter.replaceAll(r'\', r'\\')}"',
  );
  return '[${quoted.join(', ')}]';
}

/// Prefixes [title] with the chapter/part [signifier] when it is set.
String _withSignifier(String? signifier, String title) =>
    signifier != null ? '$signifier $title' : title;

/// The inline latexmath delimiters, rendered (see above).
final String _inlineLatexmathInspect = _inspectDelimiters(
  _inlineMathDelimiters['latexmath']!,
);

/// The block latexmath delimiters, rendered (see above).
final String _blockLatexmathInspect = _inspectDelimiters(
  _blockMathDelimiters['latexmath']!,
);

/// The block asciimath delimiters, rendered (see above).
final String _blockAsciimathInspect = _inspectDelimiters(
  _blockMathDelimiters['asciimath']!,
);

/// Pinned Font Awesome version (port of `FONT_AWESOME_VERSION`).
const String _fontAwesomeVersion = '4.7.0';

/// Pinned MathJax version (port of `MATHJAX_VERSION`).
const String _mathjaxVersion = '2.7.9';

/// Stylesheet attribute values selecting the default stylesheet (port of
/// `DEFAULT_STYLESHEET_KEYS`).
const Set<String> _defaultStylesheetKeys = <String>{'', 'DEFAULT'};

/// A built-in [Converter] implementation that generates HTML 5 output.
///
/// Port of `Asciidoctor::Converter::Html5Converter`. Each `convert*`
/// method corresponds to Asciidoctor's `convert_*` method of the same name
/// and is dispatched to by `convertBlock` and `convertInline` below.
class Html5Converter extends BuiltInConverter {
  /// Creates a converter for [backend] with constructor options [opts].
  ///
  /// An `xml` [ConverterOptions.htmlsyntax] selects XML mode (void
  /// elements close with a slash and boolean attributes render as
  /// `name="name"`).
  new(super.backend, [super.opts])
    : _xmlMode = opts.htmlsyntax == 'xml',
      _voidElementSlash = opts.htmlsyntax == 'xml' ? '/' : '' {
    backendTraits = BackendTraits(
      basebackend: 'html',
      filetype: 'html',
      htmlsyntax: _xmlMode ? 'xml' : 'html',
      outfilesuffix: '.html',
      supportsTemplates: true,
    );
  }

  @override
  String? convertBlock(AbstractBlock node, ConvertOptions? opts) =>
      switch (node.context) {
        .admonition => convertAdmonition(node as Block),
        .audio => convertAudio(node as Block),
        .colist => convertColist(node as ListBlock),
        .dlist => convertDlist(node as ListBlock),
        .document => convertDocument(node as Document),
        .example => convertExample(node as Block),
        .floatingTitle => convertFloatingTitle(node as Block),
        .image => convertImage(node as Block),
        .listing => convertListing(node as Block),
        .literal => convertLiteral(node as Block),
        .olist => convertOlist(node as ListBlock),
        .open => convertOpen(node as Block),
        .pageBreak => convertPageBreak(node as Block),
        .paragraph => convertParagraph(node as Block),
        .pass => contentOnly(node),
        .preamble => convertPreamble(node as Block),
        .quote => convertQuote(node as Block),
        .section => convertSection(node as Section),
        .sidebar => convertSidebar(node as Block),
        .stem => convertStem(node as Block),
        .table => convertTable(node as Table),
        .thematicBreak => convertThematicBreak(node as Block),
        .toc => convertToc(node as Block),
        .ulist => convertUlist(node as ListBlock),
        .verse => convertVerse(node as Block),
        .video => convertVideo(node as Block),
        .listItem || .tableCell => missing(node.nodeName),
      };

  @override
  bool handlesBlock(BlockContext context) => switch (context) {
    .listItem || .tableCell => false,
    _ => true,
  };

  @override
  String? convertInline(Inline node) => switch (node.context) {
    .anchor => convertInlineAnchor(node) ?? '',
    .lineBreak => convertInlineBreak(node),
    .button => convertInlineButton(node),
    .callout => convertInlineCallout(node),
    .footnote => convertInlineFootnote(node) ?? '',
    .image => convertInlineImage(node),
    .indexterm => convertInlineIndexterm(node),
    .kbd => convertInlineKbd(node),
    .menu => convertInlineMenu(node),
    .quoted => convertInlineQuoted(node),
  };

  @override
  Set<String> get transforms => const {'embedded', 'outline'};

  @override
  String? convertTransform(
    AbstractNode node,
    String transform,
    ConvertOptions? opts,
  ) => switch (transform) {
    'embedded' => convertEmbedded(node as Document),
    'outline' => convertOutline(node as AbstractBlock, opts) ?? '',
    _ => missing(transform),
  };

  @override
  String get converterName => 'Html5Converter';

  /// Quote tags by quoted-text type (port of `QUOTE_TAGS`).
  ///
  /// Each entry holds the opening tag, the closing tag and whether the tag
  /// carries attributes. Lookups miss with empty tags.
  static const Map<String, (String, String, bool)> quoteTags =
      <String, (String, String, bool)>{
        'monospaced': ('<code>', '</code>', true),
        'emphasis': ('<em>', '</em>', true),
        'strong': ('<strong>', '</strong>', true),
        'double': ('&#8220;', '&#8221;', false),
        'single': ('&#8216;', '&#8217;', false),
        'mark': ('<mark>', '</mark>', true),
        'superscript': ('<sup>', '</sup>', true),
        'subscript': ('<sub>', '</sub>', true),
        'asciimath': (r'\$', r'\$', false),
        'latexmath': (r'\(', r'\)', false),
      };

  /// Default quote tags for unknown quoted-text types.
  static const (String, String, bool) _defaultQuoteTags = ('', '', false);

  /// Whether void elements close with a slash (the `xml` htmlsyntax).
  final bool _xmlMode;

  /// The void-element slash: `'/'` in XML mode, else `''`.
  final String _voidElementSlash;

  /// Memoized document refs catalog (port of `@refs`).
  Map<String, AbstractNode>? _refs;

  /// Whether an xref is currently being resolved (port of
  /// `@resolving_xref`; guards against recursive xrefs).
  bool _resolvingXref = false;

  /// Registers this converter for [backends]. Called by document
  /// initialization; idempotent.
  static void registerFor([List<String> backends = const ['html5']]) {
    Converter.register(Html5Converter.new, backends, provided: true);
  }

  /// Converts the [node] document to a standalone HTML page.
  String convertDocument(Document node) {
    final slash = _voidElementSlash;
    final br = '<br$slash>';
    var assetUriScheme = node.attr('asset-uri-scheme', 'https')!;
    if (assetUriScheme.isNotEmpty) {
      assetUriScheme = '$assetUriScheme:';
    }
    final cdnBaseUrl = '$assetUriScheme//cdnjs.cloudflare.com/ajax/libs';
    final linkcss = node.hasAttr('linkcss');
    final maxWidthAttr = node.hasAttr('max-width')
        ? ' style="max-width: ${_s(node.attr('max-width'))};"'
        : '';
    final result = <String>['<!DOCTYPE html>'];
    final langAttribute = node.hasAttr('nolang')
        ? ''
        : ' lang="${_s(node.attr('lang', 'en'))}"';
    final xmlnsAttribute = _xmlMode
        ? ' xmlns="http://www.w3.org/1999/xhtml"'
        : '';
    result
      ..add('<html$xmlnsAttribute$langAttribute>')
      ..add(
        '<head>\n'
        '<meta charset="${_s(node.attr('encoding', 'UTF-8'))}"$slash>\n'
        '<meta http-equiv="X-UA-Compatible" content="IE=edge"$slash>\n'
        '<meta name="viewport" content="width=device-width, '
        'initial-scale=1.0"$slash>\n'
        '<meta name="generator" content="Asciidart '
        '${_s(node.attr('asciidart-version'))}"$slash>',
      );
    if (node.hasAttr('app-name')) {
      result.add(
        '<meta name="application-name" '
        'content="${_s(node.attr('app-name'))}"$slash>',
      );
    }
    if (node.hasAttr('description')) {
      result.add(
        '<meta name="description" '
        'content="${_s(node.attr('description'))}"$slash>',
      );
    }
    if (node.hasAttr('keywords')) {
      result.add(
        '<meta name="keywords" content="${_s(node.attr('keywords'))}"$slash>',
      );
    }
    if (node.hasAttr('authors')) {
      final authors = node.subReplacements(node.attr('authors')!);
      final authorContent = authors.contains('<')
          ? authors.replaceAll(xmlSanitizeRx, '')
          : authors;
      result.add('<meta name="author" content="$authorContent"$slash>');
    }
    if (node.hasAttr('copyright')) {
      result.add(
        '<meta name="copyright" content="${_s(node.attr('copyright'))}"$slash>',
      );
    }
    if (node.hasAttr('favicon')) {
      final iconHref = node.attr('favicon')!;
      final String iconType;
      final String resolvedHref;
      if (iconHref.isEmpty) {
        resolvedHref = 'favicon.ico';
        iconType = 'image/x-icon';
      } else {
        resolvedHref = iconHref;
        final iconExt = Helpers.extname(iconHref, null);
        if (iconExt != null) {
          iconType = iconExt == '.ico'
              ? 'image/x-icon'
              : 'image/${iconExt.substring(1)}';
        } else {
          iconType = 'image/x-icon';
        }
      }
      result.add(
        '<link rel="icon" type="$iconType" href="$resolvedHref"$slash>',
      );
    }
    result.add(
      '<title>${_s(node.doctitle(sanitize: true, useFallback: true))}</title>',
    );

    late final stylesdir = node.attr('stylesdir');
    if (_defaultStylesheetKeys.contains(node.attr('stylesheet'))) {
      final webfonts = node.attr('webfonts');
      if (webfonts != null) {
        result.add(
          '<link rel="stylesheet" href="$assetUriScheme//fonts.googleapis.com/css?family=${webfonts.isEmpty ? 'Open+Sans:300,300italic,400,400italic,600,600italic%7CNoto+Serif:400,400italic,700,700italic%7CDroid+Sans+Mono:400,700' : webfonts}"$slash>',
        );
      }
      if (linkcss) {
        final href = node.normalizeWebPath(
          Stylesheets.defaultStylesheetName,
          start: stylesdir,
          preserveUriTarget: false,
        );
        result.add('<link rel="stylesheet" href="$href"$slash>');
      } else {
        result.add(
          '<style>\n${Stylesheets.instance.primaryStylesheetData}\n</style>',
        );
      }
    } else if (node.hasAttr('stylesheet')) {
      final stylesheet = node.attr('stylesheet')!;
      if (linkcss) {
        final href = node.normalizeWebPath(stylesheet, start: stylesdir);
        result.add('<link rel="stylesheet" href="$href"$slash>');
      } else {
        final contents = node.readContents(
          stylesheet,
          start: stylesdir,
          label: 'stylesheet',
        );
        result.add('<style>\n${_s(contents)}\n</style>');
      }
    }

    if (node.hasAttr('icons', 'font')) {
      if (node.hasAttr('iconfont-remote')) {
        final href = node.attr(
          'iconfont-cdn',
          '$cdnBaseUrl/font-awesome/$_fontAwesomeVersion/css/'
              'font-awesome.min.css',
        );
        result.add('<link rel="stylesheet" href="${_s(href)}"$slash>');
      } else {
        final iconfontStylesheet =
            '${_s(node.attr('iconfont-name', 'font-awesome'))}.css';
        final href = node.normalizeWebPath(
          iconfontStylesheet,
          start: stylesdir,
          preserveUriTarget: false,
        );
        result.add('<link rel="stylesheet" href="$href"$slash>');
      }
    }

    final syntaxHl = node.syntaxHighlighter;
    var syntaxHlDocinfoHeadIdx = -1;
    if (syntaxHl != null) {
      syntaxHlDocinfoHeadIdx = result.length;
      // Placeholder; replaced with (or removed for) the head docinfo below.
      result.add('');
    }

    final docinfoContent = node.docinfo();
    if (docinfoContent.isNotEmpty) {
      result.add(docinfoContent);
    }

    result.add('</head>');
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final sectioned = node.hasSections;
    final List<String> classes;
    if (sectioned &&
        node.hasAttr('toc-class') &&
        node.hasAttr('toc') &&
        node.hasAttr('toc-placement', 'auto')) {
      classes = <String>[
        _s(node.doctype),
        _s(node.attr('toc-class')),
        'toc-${_s(node.attr('toc-position', 'header'))}',
      ];
    } else {
      classes = <String>[_s(node.doctype)];
    }
    if (node.hasRole()) {
      classes.add(_s(node.role));
    }
    result.add('<body$idAttr class="${classes.join(' ')}">');

    final headerDocinfo = node.docinfo('header');
    if (headerDocinfo.isNotEmpty) {
      result.add(headerDocinfo);
    }

    if (!node.noheader) {
      result.add('<div id="header"$maxWidthAttr>');
      if (node.doctype == 'manpage') {
        result.add('<h1>${_s(node.doctitle())} Manual Page</h1>');
        if (sectioned &&
            node.hasAttr('toc') &&
            node.hasAttr('toc-placement', 'auto')) {
          result.add(
            '<div id="toc" class="${_s(node.attr('toc-class', 'toc'))}">\n'
            '<div id="toctitle">${_s(node.attr('toc-title'))}</div>\n'
            '${_s((node.converter as Converter).convert(node, 'outline'))}\n'
            '</div>',
          );
        }
        if (node.hasAttr('manpurpose')) {
          result.add(_generateMannameSection(node));
        }
      } else {
        if (node.hasHeader) {
          if (!node.notitle) {
            result.add('<h1>${_s(node.header!.title)}</h1>');
          }
          final details = <String>[];
          var idx = 1;
          for (final author in node.authors) {
            details.add(
              '<span id="author${idx > 1 ? idx : ''}" class="author">${node.subReplacements(author.name!)}</span>$br',
            );
            if (author.email != null) {
              details.add(
                '<span id="email${idx > 1 ? idx : ''}" class="email">${node.subMacros(author.email!)}</span>$br',
              );
            }
            idx += 1;
          }
          if (node.hasAttr('revnumber')) {
            details.add(
              '<span id="revnumber">${downcase(node.attr('version-label') ?? '')} ${_s(node.attr('revnumber'))}${node.hasAttr('revdate') ? ',' : ''}</span>',
            );
          }
          if (node.hasAttr('revdate')) {
            details.add(
              '<span id="revdate">${_s(node.attr('revdate'))}</span>',
            );
          }
          if (node.hasAttr('revremark')) {
            details.add(
              '$br<span id="revremark">${_s(node.attr('revremark'))}</span>',
            );
          }
          if (details.isNotEmpty) {
            result
              ..add('<div class="details">')
              ..addAll(details)
              ..add('</div>');
          }
        }

        if (sectioned &&
            node.hasAttr('toc') &&
            node.hasAttr('toc-placement', 'auto')) {
          result.add(
            '<div id="toc" class="${_s(node.attr('toc-class', 'toc'))}">\n'
            '<div id="toctitle">${_s(node.attr('toc-title'))}</div>\n'
            '${_s((node.converter as Converter).convert(node, 'outline'))}\n'
            '</div>',
          );
        }
      }
      result.add('</div>');
    }

    result.add(
      '<div id="content"$maxWidthAttr>\n${_s(node.content())}\n</div>',
    );

    if (node.hasFootnotes && !node.hasAttr('nofootnotes')) {
      result.add('<div id="footnotes"$maxWidthAttr>\n<hr$slash>');
      for (final footnote in node.footnotes) {
        result.add(
          '<div class="footnote" id="_footnotedef_${_s(footnote.index)}">\n'
          '<a href="#_footnoteref_${_s(footnote.index)}">${_s(footnote.index)}</a>. ${_s(footnote.text)}\n'
          '</div>',
        );
      }
      result.add('</div>');
    }

    if (!node.nofooter) {
      result
        ..add('<div id="footer"$maxWidthAttr>')
        ..add('<div id="footer-text">');
      if (node.hasAttr('revnumber')) {
        result.add(
          '${_s(node.attr('version-label'))} ${_s(node.attr('revnumber'))}$br',
        );
      }
      if (node.hasAttr('last-update-label') && !node.hasAttr('reproducible')) {
        result.add(
          '${_s(node.attr('last-update-label'))} '
          '${_s(node.attr('docdatetime'))}',
        );
      }
      result
        ..add('</div>')
        ..add('</div>');
    }

    // JavaScript (and auxiliary stylesheets) loaded at the end of body for
    // performance reasons.
    // See http://www.html5rocks.com/en/tutorials/speed/script-loading/
    if (syntaxHl != null) {
      if (syntaxHl.hasDocinfo('head')) {
        result[syntaxHlDocinfoHeadIdx] = syntaxHl.docinfo(
          'head',
          node,
          cdnBaseUrl: cdnBaseUrl,
          linkcss: linkcss,
          selfClosingTagSlash: slash,
        );
      } else {
        result.removeAt(syntaxHlDocinfoHeadIdx);
      }
      if (syntaxHl.hasDocinfo('footer')) {
        result.add(
          syntaxHl.docinfo(
            'footer',
            node,
            cdnBaseUrl: cdnBaseUrl,
            linkcss: linkcss,
            selfClosingTagSlash: slash,
          ),
        );
      }
    }

    if (node.hasAttr('stem')) {
      var eqnumsVal = _s(node.attr('eqnums', 'none'));
      if (eqnumsVal.isEmpty) {
        eqnumsVal = 'AMS';
      }
      final eqnumsOpt = ' equationNumbers: { autoNumber: "$eqnumsVal" } ';
      // IMPORTANT inspect calls on delimiter arrays are intentional for
      // JavaScript compat (emulates JSON.stringify); the values below were
      // verified against Asciidoctor's output.
      result.add(
        '<script type="text/x-mathjax-config">\n'
        'MathJax.Hub.Config({\n'
        '  messageStyle: "none",\n'
        '  tex2jax: {\n'
        '    inlineMath: [$_inlineLatexmathInspect],\n'
        '    displayMath: [$_blockLatexmathInspect],\n'
        '    ignoreClass: "nostem|nolatexmath"\n'
        '  },\n'
        '  asciimath2jax: {\n'
        '    delimiters: [$_blockAsciimathInspect],\n'
        '    ignoreClass: "nostem|noasciimath"\n'
        '  },\n'
        '  TeX: {$eqnumsOpt}\n'
        '})\n'
        'MathJax.Hub.Register.StartupHook("AsciiMath Jax Ready", '
        'function () {\n'
        '  MathJax.InputJax.AsciiMath.postfilterHooks.Add(function '
        '(data, node) {\n'
        '    if ((node = data.script.parentNode) && (node = node.parentNode) '
        '&& node.classList.contains("stemblock")) {\n'
        '      data.math.root.display = "block"\n'
        '    }\n'
        '    return data\n'
        '  })\n'
        '})\n'
        '</script>\n'
        '<script src="$cdnBaseUrl/mathjax/$_mathjaxVersion/MathJax.js?config=TeX-MML-AM_CHTML"></script>',
      );
    }

    final footerDocinfo = node.docinfo('footer');
    if (footerDocinfo.isNotEmpty) {
      result.add(footerDocinfo);
    }

    result
      ..add('</body>')
      ..add('</html>');
    return result.join(lf);
  }

  /// Converts the [node] document to embedded HTML (no header/footer).
  String convertEmbedded(Document node) {
    final result = <String>[];
    if (node.doctype == 'manpage') {
      // QUESTION should notitle control the manual page title?
      if (!node.notitle) {
        final idAttr = node.id != null ? ' id="${node.id}"' : '';
        result.add('<h1$idAttr>${_s(node.doctitle())} Manual Page</h1>');
      }
      if (node.hasAttr('manpurpose')) {
        result.add(_generateMannameSection(node));
      }
    } else if (node.hasHeader && !node.notitle) {
      final idAttr = node.id != null ? ' id="${node.id}"' : '';
      result.add('<h1$idAttr>${_s(node.header!.title)}</h1>');
    }

    if (node.hasSections &&
        node.hasAttr('toc') &&
        (node.attr('toc-placement')) != 'macro' &&
        (node.attr('toc-placement')) != 'preamble') {
      result.add(
        '<div id="toc" class="toc">\n'
        '<div id="toctitle">${_s(node.attr('toc-title'))}</div>\n'
        '${_s((node.converter as Converter).convert(node, 'outline'))}\n'
        '</div>',
      );
    }

    result.add(_s(node.content()));

    if (node.hasFootnotes && !node.hasAttr('nofootnotes')) {
      result.add('<div id="footnotes">\n<hr$_voidElementSlash>');
      for (final footnote in node.footnotes) {
        result.add(
          '<div class="footnote" id="_footnotedef_${_s(footnote.index)}">\n'
          '<a href="#_footnoteref_${_s(footnote.index)}">${_s(footnote.index)}</a>. ${_s(footnote.text)}\n'
          '</div>',
        );
      }
      result.add('</div>');
    }

    return result.join(lf);
  }

  /// Converts [node] (a document or section) to a table-of-contents outline.
  ///
  /// Returns `null` when [node] has no sections. [opts] carries
  /// `toclevels` and `sectnumlevels` overrides (used by the recursive call
  /// and the toc macro).
  String? convertOutline(AbstractBlock node, [ConvertOptions? opts]) {
    if (!node.hasSections) {
      return null;
    }
    final sectnumlevels =
        opts?.sectnumlevels ??
        parseLeadingInt(node.document!.attributes['sectnumlevels'] ?? '3');
    final toclevels =
        opts?.toclevels ??
        parseLeadingInt(node.document!.attributes['toclevels'] ?? '2');
    final sections = node.sections;
    // FIXME top level is incorrect if a multipart book starts with a special
    // section defined at level 0
    final result = <String>['<ul class="sectlevel${sections[0].level}">'];
    for (final child in sections) {
      final section = child as Section;
      final slevel = section.level!;
      final String stitle;
      if (section.caption != null) {
        stitle = section.captionedTitle();
      } else if (section.numbered && slevel <= sectnumlevels) {
        if (slevel < 2 && (node.document! as Document).doctype == 'book') {
          final signifierAttrs = node.document!.attributes;
          switch (section.sectname) {
            case 'chapter':
              stitle = _withSignifier(
                signifierAttrs['chapter-signifier'],
                '${section.sectnum()} ${section.title!}',
              );
            case 'part':
              // With level < 2 this renders the bare numeral plus ':'.
              stitle = _withSignifier(
                signifierAttrs['part-signifier'],
                '${section.sectnum('.', ':')} ${section.title!}',
              );
            default:
              stitle = '${section.sectnum()} ${section.title!}';
          }
        } else {
          stitle = '${section.sectnum()} ${section.title!}';
        }
      } else {
        stitle = section.title!;
      }
      final cleanTitle = stitle.contains('<a')
          ? stitle.replaceAll(_dropAnchorRx, '')
          : stitle;
      final String? childTocLevel;
      if (slevel < toclevels) {
        childTocLevel = convertOutline(
          section,
          ConvertOptions(toclevels: toclevels, sectnumlevels: sectnumlevels),
        );
      } else {
        childTocLevel = null;
      }
      if (childTocLevel != null) {
        result
          ..add('<li><a href="#${_s(section.id)}">$cleanTitle</a>')
          ..add(childTocLevel)
          ..add('</li>');
      } else {
        result.add('<li><a href="#${_s(section.id)}">$cleanTitle</a></li>');
      }
    }
    result.add('</ul>');
    return result.join(lf);
  }

  /// Converts the [node] section.
  String convertSection(Section node) {
    final docAttrs = node.document!.attributes;
    final level = node.level!;
    final String title;
    {
      var resolvedTitle = '';
      if (node.caption != null) {
        resolvedTitle = node.captionedTitle();
      } else if (node.numbered &&
          level <= parseLeadingInt(docAttrs['sectnumlevels'] ?? '3')) {
        if (level < 2 && (node.document! as Document).doctype == 'book') {
          switch (node.sectname) {
            case 'chapter':
              resolvedTitle = _withSignifier(
                docAttrs['chapter-signifier'],
                '${node.sectnum()} ${node.title!}',
              );
            case 'part':
              // See convertOutline for the part numeral format.
              resolvedTitle = _withSignifier(
                docAttrs['part-signifier'],
                '${node.sectnum('.', ':')} ${node.title!}',
              );
            default:
              resolvedTitle = '${node.sectnum()} ${node.title!}';
          }
        } else {
          resolvedTitle = '${node.sectnum()} ${node.title!}';
        }
      } else {
        resolvedTitle = node.title!;
      }
      title = resolvedTitle;
    }
    var linkedTitle = title;
    final String idAttr;
    if (node.id != null) {
      final id = node.id!;
      idAttr = ' id="$id"';
      if (docAttrs['sectlinks'] != null) {
        if (linkedTitle.startsWith('<a ')) {
          final leading = _leadingAnchorsRx.firstMatch(linkedTitle);
          if (leading != null) {
            final anchors = leading.group(0)!;
            linkedTitle =
                '$anchors<a class="link" href="#$id">${linkedTitle.substring(anchors.length)}</a>';
          } else {
            linkedTitle = '<a class="link" href="#$id">$linkedTitle</a>';
          }
        } else {
          linkedTitle = '<a class="link" href="#$id">$linkedTitle</a>';
        }
      }
      if (docAttrs['sectanchors'] != null) {
        // QUESTION should we add a font-based icon in anchor if icons=font?
        if (docAttrs['sectanchors'] == 'after') {
          linkedTitle = '$linkedTitle<a class="anchor" href="#$id"></a>';
        } else {
          linkedTitle = '<a class="anchor" href="#$id"></a>$linkedTitle';
        }
      }
    } else {
      idAttr = '';
    }
    final role = node.role;
    final roleClass = role != null ? ' ${_s(role)}' : '';
    if (level == 0) {
      return '<h1$idAttr class="sect0$roleClass">$linkedTitle</h1>\n'
          '${_s(node.content())}';
    }
    final content = _s(node.content());
    final body = level == 1
        ? '<div class="sectionbody">\n$content\n</div>'
        : content;
    return '<div class="sect$level$roleClass">\n'
        '<h${level + 1}$idAttr>$linkedTitle</h${level + 1}>\n'
        '$body\n'
        '</div>';
  }

  /// Converts the [node] admonition block.
  String convertAdmonition(Block node) {
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final name = _s(node.attr('name'));
    final titleElement = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final String label;
    if (node.document!.hasAttr('icons')) {
      if (node.document!.hasAttr('icons', 'font') && !node.hasAttr('icon')) {
        label =
            '<i class="fa icon-$name" title="${_s(node.attr('textlabel'))}"></i>';
      } else {
        label =
            '<img src="${node.iconUri(name)}" '
            'alt="${_s(node.attr('textlabel'))}"$_voidElementSlash>';
      }
    } else {
      label = '<div class="title">${_s(node.attr('textlabel'))}</div>';
    }
    final role = node.role;
    return '<div$idAttr class="admonitionblock '
        '$name${role != null ? ' ${_s(role)}' : ''}">\n'
        '<table>\n'
        '<tr>\n'
        '<td class="icon">\n'
        '$label\n'
        '</td>\n'
        '<td class="content">\n'
        '$titleElement${_s(node.content())}\n'
        '</td>\n'
        '</tr>\n'
        '</table>\n'
        '</div>';
  }

  /// Converts the [node] audio block.
  String convertAudio(Block node) {
    final xml = _xmlMode;
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>['audioblock'];
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';
    final titleElement = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final startT = node.attr('start');
    final endT = node.attr('end');
    final timeAnchor = startT != null || endT != null
        ? '#t=${_s(startT)}${endT != null ? ',${_s(endT)}' : ''}'
        : '';
    final src = node.mediaUri(node.attr('target')!);
    final controlsAttribute = node.hasOption('nocontrols')
        ? ''
        : _appendBooleanAttribute('controls', xml);
    return '<div$idAttribute$classAttribute>\n'
        '$titleElement<div class="content">\n'
        '<audio src="$src$timeAnchor"${_optionAttribute(node, 'autoplay')}'
        '$controlsAttribute${_optionAttribute(node, 'loop')}>\n'
        'Your browser does not support the audio tag.\n'
        '</audio>\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] callout list.
  String convertColist(ListBlock node) {
    final result = <String>[];
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>['colist'];
    if (node.style != null) {
      classes.add(node.style!);
    }
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';

    result.add('<div$idAttribute$classAttribute>');
    if (node.hasTitle) {
      result.add('<div class="title">${_s(node.title)}</div>');
    }

    if (node.document!.hasAttr('icons')) {
      result.add('<table>');
      final fontIcons = node.document!.hasAttr('icons', 'font');
      var num = 0;
      for (final item in node.items) {
        final listItem = item;
        num += 1;
        final String numLabel;
        if (fontIcons) {
          numLabel = '<i class="conum" data-value="$num"></i><b>$num</b>';
        } else {
          numLabel =
              '<img src="${node.iconUri('callouts/$num')}" '
              'alt="$num"$_voidElementSlash>';
        }
        result.add(
          '<tr>\n'
          '<td>$numLabel</td>\n'
          '<td>${_s(listItem.text)}${listItem.hasBlocks ? '$lf${_s(listItem.content())}' : ''}</td>\n'
          '</tr>',
        );
      }
      result.add('</table>');
    } else {
      result.add('<ol>');
      for (final item in node.items) {
        final listItem = item;
        result.add(
          '<li>\n'
          '<p>${_s(listItem.text)}</p>${listItem.hasBlocks ? '$lf${_s(listItem.content())}' : ''}\n'
          '</li>',
        );
      }
      result.add('</ol>');
    }

    result.add('</div>');
    return result.join(lf);
  }

  /// Converts the [node] description list.
  String convertDlist(ListBlock node) {
    final result = <String>[];
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';

    final List<String> classes;
    switch (node.style) {
      case 'qanda':
        classes = <String>['qlist', 'qanda'];
      case 'horizontal':
        classes = <String>['hdlist'];
      default:
        classes = <String>['dlist'];
        if (node.style != null) {
          classes.add(node.style!);
        }
    }
    if (node.role != null) {
      classes.add(_s(node.role));
    }

    final classAttribute = ' class="${classes.join(' ')}"';

    result.add('<div$idAttribute$classAttribute>');
    if (node.hasTitle) {
      result.add('<div class="title">${_s(node.title)}</div>');
    }
    switch (node.style) {
      case 'qanda':
        result.add('<ol>');
        for (final DlistEntry(:terms, description: dd) in node.entries) {
          result.add('<li>');
          for (final term in terms) {
            result.add('<p><em>${_s(term.text)}</em></p>');
          }
          if (dd != null) {
            if (dd.hasText) {
              result.add('<p>${_s(dd.text)}</p>');
            }
            if (dd.hasBlocks) {
              result.add(_s(dd.content()));
            }
          }
          result.add('</li>');
        }
        result.add('</ol>');
      case 'horizontal':
        final slash = _voidElementSlash;
        result.add('<table>');
        if (node.hasAttr('labelwidth') || node.hasAttr('itemwidth')) {
          result.add('<colgroup>');
          final labelWidth = node.hasAttr('labelwidth')
              ? ' style="width: '
                    '${_chompPercent(node.attr('labelwidth')!)}%;"'
              : '';
          result.add('<col$labelWidth$slash>');
          final itemWidth = node.hasAttr('itemwidth')
              ? ' style="width: '
                    '${_chompPercent(node.attr('itemwidth')!)}%;"'
              : '';
          result
            ..add('<col$itemWidth$slash>')
            ..add('</colgroup>');
        }
        for (final DlistEntry(:terms, description: dd) in node.entries) {
          result
            ..add('<tr>')
            ..add(
              '<td '
              'class="hdlist1${node.hasOption('strong') ? ' strong' : ''}">',
            );
          var firstTerm = true;
          for (final term in terms) {
            if (!firstTerm) {
              result.add('<br$slash>');
            }
            result.add(_s(term.text));
            firstTerm = false;
          }
          result
            ..add('</td>')
            ..add('<td class="hdlist2">');
          if (dd != null) {
            if (dd.hasText) {
              result.add('<p>${_s(dd.text)}</p>');
            }
            if (dd.hasBlocks) {
              result.add(_s(dd.content()));
            }
          }
          result
            ..add('</td>')
            ..add('</tr>');
        }
        result.add('</table>');
      default:
        result.add('<dl>');
        final dtStyleAttribute = node.style != null ? '' : ' class="hdlist1"';
        for (final DlistEntry(:terms, description: dd) in node.entries) {
          for (final term in terms) {
            result.add('<dt$dtStyleAttribute>${_s(term.text)}</dt>');
          }
          if (dd == null) {
            continue;
          }
          result.add('<dd>');
          if (dd.hasText) {
            result.add('<p>${_s(dd.text)}</p>');
          }
          if (dd.hasBlocks) {
            result.add(_s(dd.content()));
          }
          result.add('</dd>');
        }
        result.add('</dl>');
    }

    result.add('</div>');
    return result.join(lf);
  }

  /// Converts the [node] example block.
  String convertExample(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    if (node.hasOption('collapsible')) {
      final classAttribute = node.role != null
          ? ' class="${_s(node.role)}"'
          : '';
      final summaryElement = node.hasTitle
          ? '<summary class="title">${_s(node.title)}</summary>'
          : '<summary class="title">Details</summary>';
      final openAttribute = node.hasOption('open') ? ' open' : '';
      return '<details$idAttribute$classAttribute$openAttribute>\n'
          '$summaryElement\n'
          '<div class="content">\n'
          '${_s(node.content())}\n'
          '</div>\n'
          '</details>';
    }
    final titleElement = node.hasTitle
        ? '<div class="title">${node.captionedTitle()}</div>\n'
        : '';
    final role = node.role;
    return '<div$idAttribute '
        'class="exampleblock${role != null ? ' ${_s(role)}' : ''}">\n'
        '$titleElement<div class="content">\n'
        '${_s(node.content())}\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] floating title.
  String convertFloatingTitle(Block node) {
    final tagName = 'h${node.level! + 1}';
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>[];
    if (node.style != null) {
      classes.add(node.style!);
    }
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    return '<$tagName$idAttribute class="${classes.join(' ')}">${_s(node.title)}</$tagName>';
  }

  /// Converts the [node] image block.
  String convertImage(Block node) {
    final target = node.attr('target')!;
    final widthAttr = node.hasAttr('width')
        ? ' width="${_s(node.attr('width'))}"'
        : '';
    final heightAttr = node.hasAttr('height')
        ? ' height="${_s(node.attr('height'))}"'
        : '';
    String imgTag(String src) =>
        '<img src="$src" alt="${_encodeAttributeValue(node.alt)}"'
        '$widthAttr$heightAttr$_voidElementSlash>';
    final String img;
    if ((node.hasAttr('format', 'svg') || target.contains('.svg')) &&
        node.document!.safe < SafeMode.secure) {
      if (node.hasOption('inline')) {
        img =
            readSvgContents(node, target) ??
            '<span class="alt">${_s(node.alt)}</span>';
      } else if (node.hasOption('interactive')) {
        final fallback = node.hasAttr('fallback')
            ? imgTag(node.imageUri(node.attr('fallback')!))
            : '<span class="alt">${_s(node.alt)}</span>';
        img =
            '<object type="image/svg+xml" data="${node.imageUri(target)}"'
            '$widthAttr$heightAttr>'
            '$fallback</object>';
      } else {
        img = imgTag(node.imageUri(target));
      }
    } else {
      img = imgTag(node.imageUri(target));
    }
    var wrappedImg = img;
    if (node.hasAttr('link')) {
      final linkConstraintAttrs = _appendLinkConstraintAttrs(node).join();
      wrappedImg =
          '<a class="image" href="${_s(node.attr('link'))}"'
          '$linkConstraintAttrs>$img</a>';
    }
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>['imageblock'];
    if (node.hasAttr('float')) {
      classes.add(_s(node.attr('float')));
    }
    if (node.hasAttr('align')) {
      classes.add('text-${_s(node.attr('align'))}');
    }
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    final classAttr = ' class="${classes.join(' ')}"';
    final titleEl = node.hasTitle
        ? '\n<div class="title">${node.captionedTitle()}</div>'
        : '';
    return '<div$idAttr$classAttr>\n'
        '<div class="content">\n'
        '$wrappedImg\n'
        '</div>$titleEl\n'
        '</div>';
  }

  /// Converts the [node] listing block.
  String convertListing(Block node) {
    final nowrap =
        node.hasOption('nowrap') || !node.document!.hasAttr('prewrap');
    final String? lang;
    final SyntaxHighlighterBase? syntaxHl;
    var hlOpts = const FormatOptions();
    var preOpen = '';
    var preClose = '';
    if (node.style == 'source') {
      lang = node.attr('language');
      syntaxHl = (node.document! as Document).syntaxHighlighter;
      if (syntaxHl != null) {
        final docAttrs = node.document!.attributes;
        hlOpts = syntaxHl.canHighlight
            ? FormatOptions(
                nowrap: nowrap,
                cssMode: CssMode.fromAttribute(
                  docAttrs['${syntaxHl.name}-css'],
                ),
                style: docAttrs['${syntaxHl.name}-style'],
              )
            : FormatOptions(nowrap: nowrap);
      } else {
        final nowrapClass = nowrap ? ' nowrap' : '';
        final langAttributes = lang != null
            ? ' class="language-$lang" data-lang="$lang"'
            : '';
        preOpen = '<pre class="highlight$nowrapClass"><code$langAttributes>';
        preClose = '</code></pre>';
      }
    } else {
      lang = null;
      syntaxHl = null;
      preOpen = '<pre${nowrap ? ' class="nowrap"' : ''}>';
      preClose = '</pre>';
    }
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '<div class="title">${node.captionedTitle()}</div>\n'
        : '';
    final role = node.role;
    final body = syntaxHl != null
        ? syntaxHl.format(node, lang, hlOpts)
        : '$preOpen${_s(node.content())}$preClose';
    return '<div$idAttribute '
        'class="listingblock${role != null ? ' ${_s(role)}' : ''}">\n'
        '$titleElement<div class="content">\n'
        '$body\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] literal block.
  String convertLiteral(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final nowrap =
        !node.document!.hasAttr('prewrap') || node.hasOption('nowrap');
    final role = node.role;
    return '<div$idAttribute '
        'class="literalblock${role != null ? ' ${_s(role)}' : ''}">\n'
        '$titleElement<div class="content">\n'
        '<pre${nowrap ? ' class="nowrap"' : ''}>${_s(node.content())}</pre>\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] stem block.
  String convertStem(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final style = node.style!;
    final delimiters = _blockMathDelimiters[style]!;
    final open = delimiters[0];
    final close = delimiters[1];
    final String equation;
    {
      final content = node.content();
      if (content != null) {
        var resolved = content;
        if (style == 'asciimath' && resolved.contains(lf)) {
          final br = '$lf<br$_voidElementSlash>';
          resolved = resolved.replaceAllMapped(_stemBreakRx, (match) {
            final breaks = match.group(0)!.split('\n').length - 1;
            return '$close${_repeat(br, breaks - 1)}$lf$open';
          });
        }
        if (!(resolved.startsWith(open) && resolved.endsWith(close))) {
          resolved = '$open$resolved$close';
        }
        equation = resolved;
      } else {
        equation = '';
      }
    }
    final role = node.role;
    return '<div$idAttribute '
        'class="stemblock${role != null ? ' ${_s(role)}' : ''}">\n'
        '$titleElement<div class="content">\n'
        '$equation\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] ordered list.
  String convertOlist(ListBlock node) {
    final result = <String>[];
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>['olist'];
    if (node.style != null) {
      classes.add(node.style!);
    }
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';

    result.add('<div$idAttribute$classAttribute>');
    if (node.hasTitle) {
      result.add('<div class="title">${_s(node.title)}</div>');
    }

    final keyword = node.listMarkerKeyword();
    final typeAttribute = keyword != null ? ' type="$keyword"' : '';
    final startAttribute = node.hasAttr('start')
        ? ' start="${_s(node.attr('start'))}"'
        : '';
    final reversedAttribute = _optionAttribute(node, 'reversed');
    result.add(
      '<ol class="${_s(node.style)}"'
      '$typeAttribute$startAttribute$reversedAttribute>',
    );

    for (final item in node.items) {
      final listItem = item;
      result
        ..add(_listItemOpenTag(listItem))
        ..add('<p>${_s(listItem.text)}</p>');
      if (listItem.hasBlocks) {
        result.add(_s(listItem.content()));
      }
      result.add('</li>');
    }

    result
      ..add('</ol>')
      ..add('</div>');
    return result.join(lf);
  }

  /// Converts the [node] open block.
  String convertOpen(Block node) {
    final style = node.style;
    if (style == 'abstract') {
      if (identical(node.parent, node.document) &&
          (node.document! as Document).doctype == 'book') {
        logger.warn(
          'abstract block cannot be used in a document without a '
          'doctitle when doctype is book. Excluding block content.',
        );
        return '';
      }
      final idAttr = node.id != null ? ' id="${node.id}"' : '';
      final titleEl = node.hasTitle
          ? '<div class="title">${_s(node.title)}</div>\n'
          : '';
      final role = node.role;
      return '<div$idAttr class="quoteblock '
          'abstract${role != null ? ' ${_s(role)}' : ''}">\n'
          '$titleEl<blockquote>\n'
          '${_s(node.content())}\n'
          '</blockquote>\n'
          '</div>';
    }
    if (style == 'partintro' &&
        (node.level! > 0 ||
            node.parent!.context != BlockContext.section ||
            (node.document! as Document).doctype != 'book')) {
      logger.error(
        'partintro block can only be used when doctype is book and '
        'must be a child of a book part. Excluding block content.',
      );
      return '';
    }
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final titleEl = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final role = node.role;
    final styleClass = style != null && style != 'open' ? ' $style' : '';
    final roleClass = role != null ? ' ${_s(role)}' : '';
    return '<div$idAttr class="openblock$styleClass$roleClass">\n'
        '$titleEl<div class="content">\n'
        '${_s(node.content())}\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] page break.
  String convertPageBreak(Block node) =>
      '<div style="page-break-after: always;"></div>';

  /// Converts the [node] paragraph.
  String convertParagraph(Block node) {
    final String attributes;
    if (node.role != null) {
      attributes =
          '${node.id != null ? ' id="${node.id}"' : ''} '
          'class="paragraph ${_s(node.role)}"';
    } else if (node.id != null) {
      attributes = ' id="${node.id}" class="paragraph"';
    } else {
      attributes = ' class="paragraph"';
    }
    if (node.hasTitle) {
      return '<div$attributes>\n'
          '<div class="title">${_s(node.title)}</div>\n'
          '<p>${_s(node.content())}</p>\n'
          '</div>';
    }
    return '<div$attributes>\n<p>${_s(node.content())}</p>\n</div>';
  }

  /// Converts the [node] preamble.
  String convertPreamble(Block node) {
    final doc = node.document! as Document;
    final String toc;
    if (doc.hasAttr('toc-placement', 'preamble') &&
        doc.hasSections &&
        doc.hasAttr('toc')) {
      toc =
          '\n<div id="toc" class="${_s(doc.attr('toc-class', 'toc'))}">\n'
          '<div id="toctitle">${_s(doc.attr('toc-title'))}</div>\n'
          '${_s((doc.converter as Converter).convert(doc, 'outline'))}\n'
          '</div>';
    } else {
      toc = '';
    }

    return '<div id="preamble">\n'
        '<div class="sectionbody">\n'
        '${_s(node.content())}\n'
        '</div>$toc\n'
        '</div>';
  }

  /// Converts the [node] quote block.
  String convertQuote(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>['quoteblock'];
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';
    final titleElement = node.hasTitle
        ? '\n<div class="title">${_s(node.title)}</div>'
        : '';
    final attributionElement = _attributionElement(node);

    return '<div$idAttribute$classAttribute>$titleElement\n'
        '<blockquote>\n'
        '${_s(node.content())}\n'
        '</blockquote>$attributionElement\n'
        '</div>';
  }

  /// Converts the [node] thematic break.
  String convertThematicBreak(Block node) => '<hr$_voidElementSlash>';

  /// Converts the [node] sidebar block.
  String convertSidebar(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final role = node.role;
    return '<div$idAttribute '
        'class="sidebarblock${role != null ? ' ${_s(role)}' : ''}">\n'
        '<div class="content">\n'
        '$titleElement${_s(node.content())}\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] table.
  String convertTable(Table node) {
    final result = <String>[];
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    var frame = _s(node.attr('frame', 'all', 'table-frame'));
    if (frame == 'topbot') {
      frame = 'ends';
    }
    final classes = <String>[
      'tableblock',
      'frame-$frame',
      'grid-${_s(node.attr('grid', 'all', 'table-grid'))}',
    ];
    final stripes = node.attr('stripes', null, 'table-stripes');
    if (stripes != null) {
      classes.add('stripes-${_s(stripes)}');
    }
    var styleAttribute = '';
    // An explicit width keeps the table width but not the column widths.
    final autowidth = node.hasOption('autowidth');
    final tablewidth = node.attr('tablepcwidth');
    if (autowidth && !node.hasAttr('width')) {
      classes.add('fit-content');
    } else if (tablewidth == '100') {
      classes.add('stretch');
    } else {
      styleAttribute = ' style="width: ${_s(tablewidth)}%;"';
    }
    if (node.hasAttr('float')) {
      classes.add(_s(node.attr('float')));
    }
    final role = node.role;
    if (role != null) {
      classes.add(_s(role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';

    result.add('<table$idAttribute$classAttribute$styleAttribute>');
    if (node.hasTitle) {
      result.add('<caption class="title">${node.captionedTitle()}</caption>');
    }
    if (node.rowcount > 0) {
      final slash = _voidElementSlash;
      result.add('<colgroup>');
      if (autowidth) {
        for (var i = 0; i < node.columns.length; i++) {
          result.add('<col$slash>');
        }
      } else {
        for (final col in node.columns) {
          result.add(
            col.hasOption('autowidth')
                ? '<col$slash>'
                : '<col style="width: ${_s(col.attr('colpcwidth'))}%;"$slash>',
          );
        }
      }
      result.add('</colgroup>');
      for (final section in node.rows.toMap().entries) {
        final tsec = section.key;
        final rows = section.value;
        if (rows.isEmpty) {
          continue;
        }
        result.add('<t$tsec>');
        for (final row in rows) {
          result.add('<tr>');
          for (final cell in row) {
            final String cellContent;
            if (tsec == 'head') {
              cellContent = _s(cell.text);
            } else {
              switch (cell.style) {
                case 'asciidoc':
                  cellContent =
                      '<div class="content">${_s(cell.content())}</div>';
                case 'literal':
                  cellContent =
                      '<div class="literal"><pre>${_s(cell.text)}</pre></div>';
                default:
                  final paragraphs = cell.paragraphs;
                  cellContent = paragraphs.isEmpty
                      ? ''
                      : '<p class="tableblock">${paragraphs.join('</p>\n<p class="tableblock">')}</p>';
              }
            }

            final cellTagName = (tsec == 'head' || cell.style == 'header')
                ? 'th'
                : 'td';
            final cellClassAttribute =
                ' class="tableblock halign-${_s(cell.attr('halign'))} '
                'valign-${_s(cell.attr('valign'))}"';
            final cellColspanAttribute = cell.colspan != null
                ? ' colspan="${cell.colspan}"'
                : '';
            final cellRowspanAttribute = cell.rowspan != null
                ? ' rowspan="${cell.rowspan}"'
                : '';
            final document = node.document! as Document;
            final cellStyleAttribute = document.hasAttr('cellbgcolor')
                ? ' style="background-color: '
                      '${_s(document.attr('cellbgcolor'))};"'
                : '';
            result.add(
              '<$cellTagName$cellClassAttribute$cellColspanAttribute'
              '$cellRowspanAttribute$cellStyleAttribute>'
              '$cellContent</$cellTagName>',
            );
          }
          result.add('</tr>');
        }
        result.add('</t$tsec>');
      }
    }
    result.add('</table>');
    return result.join(lf);
  }

  /// Converts the [node] toc macro block.
  String convertToc(Block node) {
    final doc = node.document! as Document;
    if (!(doc.hasAttr('toc-placement', 'macro') &&
        doc.hasSections &&
        doc.hasAttr('toc'))) {
      return '<!-- toc disabled -->';
    }

    final String idAttr;
    final String titleIdAttr;
    if (node.id != null) {
      idAttr = ' id="${node.id}"';
      titleIdAttr = ' id="${node.id}title"';
    } else {
      idAttr = ' id="toc"';
      titleIdAttr = ' id="toctitle"';
    }
    final title = node.hasTitle ? _s(node.title) : _s(doc.attr('toc-title'));
    final levels = node.hasAttr('levels')
        ? parseLeadingInt(node.attr('levels'))
        : null;
    final role = node.hasRole()
        ? _s(node.role)
        : _s(doc.attr('toc-class', 'toc'));

    final outline = (doc.converter as Converter).convert(
      doc,
      'outline',
      ConvertOptions(toclevels: levels),
    );
    return '<div$idAttr class="$role">\n'
        '<div$titleIdAttr class="title">$title</div>\n'
        '${_s(outline)}\n'
        '</div>';
  }

  /// Converts the [node] unordered list.
  String convertUlist(ListBlock node) {
    final result = <String>[];
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final divClasses = <String>['ulist'];
    if (node.style != null) {
      divClasses.add(node.style!);
    }
    if (node.role != null) {
      divClasses.add(_s(node.role));
    }
    var markerChecked = '';
    var markerUnchecked = '';
    final String ulClassAttribute;
    final checklist = node.hasOption('checklist');
    if (checklist) {
      divClasses.insert(1, 'checklist');
      ulClassAttribute = ' class="checklist"';
      if (node.hasOption('interactive')) {
        if (_xmlMode) {
          markerChecked = '<input type="checkbox" data-item-complete="1" checked="checked"/> ';
          markerUnchecked = '<input type="checkbox" data-item-complete="0"/> ';
        } else {
          markerChecked =
              '<input type="checkbox" data-item-complete="1" checked> ';
          markerUnchecked = '<input type="checkbox" data-item-complete="0"> ';
        }
      } else if (node.document!.hasAttr('icons', 'font')) {
        markerChecked = '<i class="fa fa-check-square-o"></i> ';
        markerUnchecked = '<i class="fa fa-square-o"></i> ';
      } else {
        markerChecked = '&#10003; ';
        markerUnchecked = '&#10063; ';
      }
    } else {
      ulClassAttribute = node.style != null ? ' class="${node.style}"' : '';
    }
    result.add('<div$idAttribute class="${divClasses.join(' ')}">');
    if (node.hasTitle) {
      result.add('<div class="title">${_s(node.title)}</div>');
    }
    result.add('<ul$ulClassAttribute>');

    for (final item in node.items) {
      final listItem = item;
      result.add(_listItemOpenTag(listItem));
      if (checklist && listItem.hasAttr('checkbox')) {
        result.add(
          '<p>${listItem.hasAttr('checked') ? markerChecked : markerUnchecked}${_s(listItem.text)}</p>',
        );
      } else {
        result.add('<p>${_s(listItem.text)}</p>');
      }
      if (listItem.hasBlocks) {
        result.add(_s(listItem.content()));
      }
      result.add('</li>');
    }

    result
      ..add('</ul>')
      ..add('</div>');
    return result.join(lf);
  }

  /// Converts the [node] verse block.
  String convertVerse(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>['verseblock'];
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';
    final titleElement = node.hasTitle
        ? '\n<div class="title">${_s(node.title)}</div>'
        : '';
    final attributionElement = _attributionElement(node);

    return '<div$idAttribute$classAttribute>$titleElement\n'
        '<pre class="content">${_s(node.content())}</pre>$attributionElement\n'
        '</div>';
  }

  /// Converts the [node] video block.
  String convertVideo(Block node) {
    final xml = _xmlMode;
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final classes = <String>['videoblock'];
    if (node.hasAttr('float')) {
      classes.add(_s(node.attr('float')));
    }
    if (node.hasAttr('align')) {
      classes.add('text-${_s(node.attr('align'))}');
    }
    if (node.role != null) {
      classes.add(_s(node.role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';
    final titleElement = node.hasTitle
        ? '\n<div class="title">${_s(node.title)}</div>'
        : '';
    final widthAttribute = node.hasAttr('width')
        ? ' width="${_s(node.attr('width'))}"'
        : '';
    final heightAttribute = node.hasAttr('height')
        ? ' height="${_s(node.attr('height'))}"'
        : '';
    switch (node.attr('poster')) {
      case 'vimeo':
        var assetUriScheme = (node.document! as Document).attr(
          'asset-uri-scheme',
          'https',
        )!;
        if (assetUriScheme.isNotEmpty) {
          assetUriScheme = '$assetUriScheme:';
        }
        final startAnchor = node.hasAttr('start')
            ? '#at=${_s(node.attr('start'))}'
            : '';
        final delimiter = <String>['?'];
        String popDelimiter() =>
            delimiter.isNotEmpty ? delimiter.removeLast() : '&amp;';
        final targetAndHash = _split2(node.attr('target')!, '/');
        final target = targetAndHash.$1;
        var hash = targetAndHash.$2;
        hash ??= node.attr('hash');
        final hashParam = hash != null ? '${popDelimiter()}h=$hash' : '';
        final autoplayParam = node.hasOption('autoplay')
            ? '${popDelimiter()}autoplay=1'
            : '';
        final loopParam = node.hasOption('loop')
            ? '${popDelimiter()}loop=1'
            : '';
        final mutedParam = node.hasOption('muted')
            ? '${popDelimiter()}muted=1'
            : '';
        return '<div$idAttribute$classAttribute>$titleElement\n'
            '<div class="content">\n'
            '<iframe$widthAttribute$heightAttribute src="$assetUriScheme//player.vimeo.com/video/$target$hashParam$autoplayParam$loopParam$mutedParam$startAnchor" frameborder="0"${node.hasOption('nofullscreen') ? '' : _appendBooleanAttribute('allowfullscreen', xml)}></iframe>\n'
            '</div>\n'
            '</div>';
      case 'youtube':
        var assetUriScheme = (node.document! as Document).attr(
          'asset-uri-scheme',
          'https',
        )!;
        if (assetUriScheme.isNotEmpty) {
          assetUriScheme = '$assetUriScheme:';
        }
        final relParamVal = node.hasOption('related') ? 1 : 0;
        // NOTE start and end must be seconds (t parameter allows XmYs where
        // X is minutes and Y is seconds)
        final startParam = node.hasAttr('start')
            ? '&amp;start=${_s(node.attr('start'))}'
            : '';
        final endParam = node.hasAttr('end')
            ? '&amp;end=${_s(node.attr('end'))}'
            : '';
        final autoplayParam = node.hasOption('autoplay')
            ? '&amp;autoplay=1'
            : '';
        final hasLoopParam = node.hasOption('loop');
        final loopParam = hasLoopParam ? '&amp;loop=1' : '';
        final muteParam = node.hasOption('muted') ? '&amp;mute=1' : '';
        final controlsParam = node.hasOption('nocontrols')
            ? '&amp;controls=0'
            : '';
        // cover both ways of controlling fullscreen option
        final String fsParam;
        final String fsAttribute;
        if (node.hasOption('nofullscreen')) {
          fsParam = '&amp;fs=0';
          fsAttribute = '';
        } else {
          fsParam = '';
          fsAttribute = _appendBooleanAttribute('allowfullscreen', xml);
        }
        final modestParam = node.hasOption('modest')
            ? '&amp;modestbranding=1'
            : '';
        final themeParam = node.hasAttr('theme')
            ? '&amp;theme=${_s(node.attr('theme'))}'
            : '';
        final hlParam = node.hasAttr('lang')
            ? '&amp;hl=${_s(node.attr('lang'))}'
            : '';

        // parse video_id/list_id syntax where list_id (i.e., playlist) is
        // optional
        final targetAndList = _split2(node.attr('target')!, '/');
        var target = targetAndList.$1;
        final list = targetAndList.$2 ?? node.attr('list');
        final String listParam;
        if (list != null) {
          listParam = '&amp;list=$list';
        } else {
          // parse dynamic playlist syntax: video_id1,video_id2,...
          final targetAndPlaylist = _split2(target, ',');
          target = targetAndPlaylist.$1;
          final playlist = targetAndPlaylist.$2 ?? node.attr('playlist');
          if (playlist != null) {
            // INFO playlist bar doesn't appear in Firefox unless showinfo=1
            // and modestbranding=1
            listParam = '&amp;playlist=$target,$playlist';
          } else {
            // NOTE for loop to work, playlist must be specified; use
            // VIDEO_ID if there's no explicit playlist
            listParam = hasLoopParam ? '&amp;playlist=$target' : '';
          }
        }

        return '<div$idAttribute$classAttribute>$titleElement\n'
            '<div class="content">\n'
            '<iframe$widthAttribute$heightAttribute src="$assetUriScheme//www.youtube.com/embed/$target?rel=$relParamVal$startParam$endParam$autoplayParam$loopParam$muteParam$controlsParam$listParam$fsParam$modestParam$themeParam$hlParam" frameborder="0"$fsAttribute></iframe>\n'
            '</div>\n'
            '</div>';
      default:
        final posterVal = node.attr('poster');
        final posterAttribute = posterVal == null || posterVal.isEmpty
            ? ''
            : ' poster="${node.mediaUri(posterVal)}"';
        final preloadVal = node.attr('preload');
        final preloadAttribute = preloadVal == null || preloadVal.isEmpty
            ? ''
            : ' preload="$preloadVal"';
        final startT = node.attr('start');
        final endT = node.attr('end');
        final timeAnchor = startT != null || endT != null
            ? '#t=${_s(startT)}${endT != null ? ',${_s(endT)}' : ''}'
            : '';
        final src = node.mediaUri(node.attr('target')!);
        final controlsAttribute = node.hasOption('nocontrols')
            ? ''
            : _appendBooleanAttribute('controls', xml);
        return '<div$idAttribute$classAttribute>$titleElement\n'
            '<div class="content">\n'
            '<video src="$src$timeAnchor"'
            '$widthAttribute$heightAttribute$posterAttribute'
            '${_optionAttribute(node, 'autoplay')}'
            '${_optionAttribute(node, 'muted')}$controlsAttribute'
            '${_optionAttribute(node, 'loop')}$preloadAttribute>\n'
            'Your browser does not support the video tag.\n'
            '</video>\n'
            '</div>\n'
            '</div>';
    }
  }

  /// Converts the [node] inline anchor.
  String? convertInlineAnchor(Inline node) {
    switch (node.type) {
      case 'xref':
        final path = node.attributes['path'];
        if (path != null) {
          final initial = node.role != null
              ? <String>[' class="${_s(node.role)}"']
              : <String>[];
          final attrs = _appendLinkConstraintAttrs(node, initial).join();
          final text = node.text ?? _s(path);
          return '<a href="${_s(node.target)}"$attrs>$text</a>';
        }
        final attrs = node.role != null ? ' class="${_s(node.role)}"' : '';
        var text = node.text;
        if (text == null) {
          final refs = _refs ??= node.document!.catalog.refs;
          final refid = node.attributes['refid'];
          Document? top;
          final ref =
              refs[refid] ??
              ((refid == null || refid.isEmpty)
                  ? top = _getRootDocument(node)
                  : null);
          if (ref is AbstractNode) {
            // Guards against recursive xrefs (port of the
            // `@resolving_xref ||= (outer = true)` idiom).
            final outer = !_resolvingXref;
            if (outer) {
              _resolvingXref = true;
            }
            try {
              if (outer) {
                final resolved = _xreftextOf(
                  ref,
                  node.attr('xrefstyle', null, 'xrefstyle'),
                );
                if (resolved != null) {
                  text = resolved.contains('<a')
                      ? resolved.replaceAll(_dropAnchorRx, '')
                      : resolved;
                } else {
                  text = top != null ? '[^top]' : '[$refid]';
                }
              } else {
                text = top != null ? '[^top]' : '[$refid]';
              }
            } finally {
              if (outer) {
                _resolvingXref = false;
              }
            }
          } else {
            text = '[$refid]';
          }
        }
        return '<a href="${_s(node.target)}"$attrs>${_s(text)}</a>';
      case 'ref':
        return '<a id="${_s(node.id)}"></a>';
      case 'link':
        final attrs = <String>[];
        if (node.id != null) {
          attrs.add(' id="${node.id}"');
        }
        if (node.role != null) {
          attrs.add(' class="${_s(node.role)}"');
        }
        if (node.hasAttr('title')) {
          attrs.add(' title="${_s(node.attr('title'))}"');
        }
        return '<a href="${_s(node.target)}"${_appendLinkConstraintAttrs(node, attrs).join()}>${_s(node.text)}</a>';
      case 'bibref':
        return '<a id="${_s(node.id)}"></a>[${_s(node.reftext ?? node.id)}]';
      default:
        logger.warn('unknown anchor type: :${node.type}');
        return null;
    }
  }

  /// Converts the [node] inline line break.
  String convertInlineBreak(Inline node) =>
      '${_s(node.text)}<br$_voidElementSlash>';

  /// Converts the [node] inline button.
  String convertInlineButton(Inline node) =>
      '<b class="button">${_s(node.text)}</b>';

  /// Converts the [node] inline callout.
  String convertInlineCallout(Inline node) {
    if (node.document!.hasAttr('icons', 'font')) {
      return '<i class="conum" data-value="${_s(node.text)}"></i><b>(${_s(node.text)})</b>';
    }
    if (node.document!.hasAttr('icons')) {
      final src = node.iconUri('callouts/${_s(node.text)}');
      return '<img src="$src" alt="${_s(node.text)}"$_voidElementSlash>';
    }
    if (node.xmlCommentGuard) {
      return '&lt;!--<b class="conum">(${_s(node.text)})</b>--&gt;';
    }
    return '${_s(node.attributes['guard'])}<b class="conum">(${_s(node.text)})</b>';
  }

  /// Converts the [node] inline footnote.
  String? convertInlineFootnote(Inline node) {
    final index = node.attr('index');
    if (index != null) {
      if (node.type == 'xref') {
        return '<sup class="footnoteref">[<a class="footnote" href="#_footnotedef_${_s(index)}" title="View footnote.">${_s(index)}</a>]</sup>';
      }
      final idAttr = node.id != null ? ' id="_footnote_${node.id}"' : '';
      return '<sup class="footnote"$idAttr>[<a id="_footnoteref_${_s(index)}" class="footnote" href="#_footnotedef_${_s(index)}" title="View footnote.">${_s(index)}</a>]</sup>';
    }
    if (node.type == 'xref') {
      return '<sup class="footnoteref red" title="Unresolved footnote reference.">[${_s(node.text)}]</sup>';
    }
    return null;
  }

  /// Converts the [node] inline image.
  String convertInlineImage(Inline node) {
    final target = node.target!;
    final type = node.type ?? 'image';
    String imgAttrs() {
      var attrs = node.hasAttr('width')
          ? ' width="${_s(node.attr('width'))}"'
          : '';
      if (node.hasAttr('height')) {
        attrs = '$attrs height="${_s(node.attr('height'))}"';
      }
      if (node.hasAttr('title')) {
        attrs = '$attrs title="${_s(node.attr('title'))}"';
      }
      return attrs;
    }

    String imgTag(String src, String attrs) =>
        '<img src="$src" alt="${_encodeAttributeValue(_s(node.alt))}"'
        '$attrs$_voidElementSlash>';

    final String img;
    if (type == 'icon') {
      final icons = (node.document! as Document).attr('icons');
      if (icons == 'font') {
        var iClassAttrVal = 'fa fa-$target';
        if (node.hasAttr('size')) {
          iClassAttrVal = '$iClassAttrVal fa-${_s(node.attr('size'))}';
        }
        if (node.hasAttr('flip')) {
          iClassAttrVal = '$iClassAttrVal fa-flip-${_s(node.attr('flip'))}';
        } else if (node.hasAttr('rotate')) {
          iClassAttrVal = '$iClassAttrVal fa-rotate-${_s(node.attr('rotate'))}';
        }
        final attrs = node.hasAttr('title')
            ? ' title="${_s(node.attr('title'))}"'
            : '';
        img = '<i class="$iClassAttrVal"$attrs></i>';
      } else if (icons != null) {
        final attrs = imgAttrs();
        img = imgTag(node.iconUri(target), attrs);
      } else {
        img = '[${_s(node.alt)}&#93;';
      }
    } else {
      final attrs = imgAttrs();
      if ((node.hasAttr('format', 'svg') || target.contains('.svg')) &&
          node.document!.safe < SafeMode.secure) {
        if (node.hasOption('inline')) {
          img =
              readSvgContents(node, target) ??
              '<span class="alt">${_s(node.alt)}</span>';
        } else if (node.hasOption('interactive')) {
          final fallback = node.hasAttr('fallback')
              ? imgTag(node.imageUri(node.attr('fallback')!), attrs)
              : '<span class="alt">${_s(node.alt)}</span>';
          img =
              '<object type="image/svg+xml" '
              'data="${node.imageUri(target)}"$attrs>'
              '$fallback</object>';
        } else {
          img = imgTag(node.imageUri(target), attrs);
        }
      } else {
        img = imgTag(node.imageUri(target), attrs);
      }
    }
    var wrappedImg = img;
    if (node.hasAttr('link')) {
      final linkConstraintAttrs = _appendLinkConstraintAttrs(node).join();
      wrappedImg =
          '<a class="image" href="${_s(node.attr('link'))}"'
          '$linkConstraintAttrs>$img</a>';
    }
    final role = node.role;
    final String classAttrVal;
    if (role != null) {
      classAttrVal = node.hasAttr('float')
          ? '$type ${_s(node.attr('float'))} ${_s(role)}'
          : '$type ${_s(role)}';
    } else if (node.hasAttr('float')) {
      classAttrVal = '$type ${_s(node.attr('float'))}';
    } else {
      classAttrVal = type;
    }
    return '<span class="$classAttrVal">$wrappedImg</span>';
  }

  /// Converts the [node] inline index term.
  String convertInlineIndexterm(Inline node) =>
      node.type == 'visible' ? _s(node.text) : '';

  /// Converts the [node] inline keyboard shortcut.
  String convertInlineKbd(Inline node) {
    final keys = node.keys!;
    if (keys.length == 1) return '<kbd>${keys[0]}</kbd>';
    return '<span class="keyseq"><kbd>${keys.join('</kbd>+<kbd>')}</kbd></span>';
  }

  /// Converts the [node] inline menu reference.
  String convertInlineMenu(Inline node) {
    final caret = node.document!.hasAttr('icons', 'font')
        ? '&#160;<i class="fa fa-angle-right caret"></i> '
        : '&#160;<b class="caret">&#8250;</b> ';
    final submenuJoiner = '</b>$caret<b class="submenu">';
    final menu = _s(node.attr('menu'));
    final submenus = node.submenus!;
    if (submenus.isEmpty) {
      final menuitem = node.attr('menuitem');
      if (menuitem != null) {
        return '<span class="menuseq"><b class="menu">$menu</b>$caret<b class="menuitem">${_s(menuitem)}</b></span>';
      }
      return '<b class="menuref">$menu</b>';
    }
    return '<span class="menuseq"><b class="menu">$menu</b>$caret<b class="submenu">${submenus.join(submenuJoiner)}</b>$caret<b class="menuitem">${_s(node.attr('menuitem'))}</b></span>';
  }

  /// Converts the [node] inline quoted text.
  String convertInlineQuoted(Inline node) {
    final (open, close, tag) = quoteTags[node.type] ?? _defaultQuoteTags;
    if (node.id != null) {
      final classAttr = node.role != null ? ' class="${_s(node.role)}"' : '';
      if (tag) {
        return '${open.substring(0, open.length - 1)} '
            'id="${node.id}"$classAttr>${_s(node.text)}$close';
      }
      return '<span id="${node.id}"$classAttr>$open${_s(node.text)}$close</span>';
    }
    if (node.role != null) {
      if (tag) {
        return '${open.substring(0, open.length - 1)} '
            'class="${_s(node.role)}">${_s(node.text)}$close';
      }
      return '<span class="${_s(node.role)}">$open${_s(node.text)}$close</span>';
    }
    return '$open${_s(node.text)}$close';
  }

  /// Reads the SVG at [target] for inlining into the output.
  ///
  /// Returns `null` when the target cannot be read or is empty. The XML
  /// preamble is stripped and, when the [node] specifies a width or
  /// height, those dimensions replace any `width`/`height`/`style`
  /// attributes on the `<svg>` start tag.
  ///
  /// NOTE exposed for Bespoke converters.
  String? readSvgContents(AbstractNode node, String target) {
    var svg = node.readContents(
      target,
      start: node.document!.attr('imagesdir'),
      normalize: true,
      label: 'SVG',
      warnIfEmpty: true,
    );
    if (svg == null) {
      return null;
    }
    if (svg.isEmpty) {
      return null;
    }
    if (!svg.startsWith('<svg')) {
      svg = svg.replaceFirst(_svgPreambleRx, '');
    }
    String? oldStartTag;
    String? newStartTag;
    // NOTE width, height and style attributes are removed if either width
    // or height is specified
    for (final dim in const <String>['width', 'height']) {
      if (!node.hasAttr(dim)) {
        continue;
      }
      if (newStartTag == null) {
        final startTagMatch = _svgStartTagRx.firstMatch(svg);
        if (startTagMatch == null) {
          continue;
        }
        newStartTag = (oldStartTag = startTagMatch.group(
          0,
        )!).replaceAll(_dimensionAttributeRx, '');
      }
      // NOTE a unitless value in HTML is assumed to be px, so we can pass
      // the value straight through
      newStartTag =
          '${newStartTag.substring(0, newStartTag.length - 1)} '
          '$dim="${_s(node.attr(dim))}">';
    }
    if (newStartTag != null) {
      svg = '$newStartTag${svg.substring(oldStartTag!.length)}';
    }
    return svg;
  }

  /// Renders the boolean HTML attribute [name] for [xml] mode.
  String _appendBooleanAttribute(String name, bool xml) =>
      xml ? ' $name="$name"' : ' $name';

  /// The attribution `<div>` (attribution and cite title) of a quote or
  /// verse [node], or an empty string when it has neither.
  String _attributionElement(Block node) {
    final attribution = node.hasAttr('attribution')
        ? node.attr('attribution')
        : null;
    final citetitle = node.hasAttr('citetitle') ? node.attr('citetitle') : null;
    if (attribution == null && citetitle == null) return '';
    final citeElement = citetitle != null
        ? '<cite>${_s(citetitle)}</cite>'
        : '';
    final lineBreak = citetitle != null ? '<br$_voidElementSlash>\n' : '';
    final attributionText = attribution != null
        ? '&#8212; ${_s(attribution)}$lineBreak'
        : '';
    return '\n<div class="attribution">\n$attributionText$citeElement\n</div>';
  }

  /// The `<li>` start tag for [item], carrying its id and role.
  String _listItemOpenTag(ListItem item) {
    final idAttribute = item.id != null ? ' id="${item.id}"' : '';
    final role = item.role;
    final classAttribute = role != null ? ' class="${_s(role)}"' : '';
    return '<li$idAttribute$classAttribute>';
  }

  /// The boolean [option] attribute when [node] has that option set.
  String _optionAttribute(AbstractNode node, String option) =>
      node.hasOption(option) ? _appendBooleanAttribute(option, _xmlMode) : '';

  /// Appends link-constraint attributes (`target`, `rel`) for [node] to
  /// [attrs] (a fresh list when omitted) and returns it.
  List<String> _appendLinkConstraintAttrs(
    AbstractNode node, [
    List<String>? attrs,
  ]) {
    final result = attrs ?? <String>[];
    final rel = node.hasOption('nofollow') ? 'nofollow' : null;
    final window = node.attributes['window'];
    if (window != null) {
      result.add(' target="${_s(window)}"');
      if (_s(window) == '_blank' || node.hasOption('noopener')) {
        result.add(rel != null ? ' rel="$rel noopener"' : ' rel="noopener"');
      }
    } else if (rel != null) {
      result.add(' rel="$rel"');
    }
    return result;
  }

  /// Escapes double quotes in the attribute [value].
  String _encodeAttributeValue(String value) =>
      value.contains('"') ? value.replaceAll('"', '&quot;') : value;

  /// Removes one trailing `%` from [value] (port of `chomp '%'`).
  String _chompPercent(String value) =>
      value.endsWith('%') ? value.substring(0, value.length - 1) : value;

  /// Generates the `manname` section for the manpage [node].
  String _generateMannameSection(Document node) {
    var mannameTitle = _s(node.attr('manname-title', 'Name'));
    final firstSection = node.sections.isNotEmpty ? node.sections[0] : null;
    final nextSectionTitle = firstSection is Section
        ? firstSection.title
        : null;
    if (nextSectionTitle != null &&
        nextSectionTitle == upcase(nextSectionTitle)) {
      mannameTitle = upcase(mannameTitle);
    }
    final mannameId = node.attr('manname-id');
    final mannameIdAttr = mannameId != null ? ' id="$mannameId"' : '';
    return '<h2$mannameIdAttr>$mannameTitle</h2>\n'
        '<div class="sectionbody">\n'
        '<p>${(node.mannames ?? const <String>[]).join(', ')} - ${_s(node.attr('manpurpose'))}</p>\n'
        '</div>';
  }

  /// Returns the root document of [node]'s document tree.
  Document _getRootDocument(AbstractNode node) {
    var doc = node.document! as Document;
    while (doc.nested()) {
      doc = doc.parentDocument!;
    }
    return doc;
  }

  /// Returns the cross-reference text for [ref], which is either a block
  /// or an inline node (`xreftext` lives on both classes).
  String? _xreftextOf(AbstractNode ref, String? xrefstyle) => switch (ref) {
    AbstractBlock() => ref.xreftext(xrefstyle),
    Inline() => ref.xreftext(xrefstyle),
    _ => null,
  };
}
