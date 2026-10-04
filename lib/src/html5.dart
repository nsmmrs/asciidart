/// HTML5 converter: generates HTML 5 output from a parsed document.
///
/// Port of `lib/asciidoctor/converter/html5.rb` (complete). Per
/// `adr/0001-dart-rewrite-goals.md` (D4) every template method produces
/// byte-identical output to the Ruby converter, including whitespace.
///
/// ## Framework integration
///
/// Ruby's `convert_<transform>` methods become handler registrations via
/// [ConverterBase.handle] (see `converter.dart`); [convert] itself is
/// inherited from [ConverterBase], which warns and returns `null` for
/// unregistered transforms, mirroring Ruby's `NoMethodError` rescue. The
/// converter registers itself with [Converter.registerFor] (explicit
/// registration replaces Ruby's lazy `require`).
///
/// ## Cross-wave contracts
///
/// * Substitutions: [AbstractNode] already declares the substitutor stubs
///   (`subReplacements`, ...). The one missing signature, `subMacros`
///   (`Substitutors#sub_macros`, used for author emails), resolves through
///   the TEMP-SHIM `substitutors.dart`, which the `port/substitutors`
///   merge deletes.
/// * Syntax highlighting: [NodeSyntaxHighlighter] mirrors the
///   `SyntaxHighlighter::Base` surface `html5.rb` consumes (`name`,
///   `highlight?`, `format`, `docinfo?`, `docinfo`). The full framework
///   (registry, factory, adapter wiring) arrives with the converter wave;
///   until then `Document.syntaxHighlighter` is cast to this interface.
/// * `method_missing` / `respond_to_missing?` (Ruby adapters for
///   unprefixed template names) have no Dart equivalent and are not
///   ported; [handles] reports the registered transforms instead.
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/converter.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/rx.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/stylesheets.dart';
import 'package:asciidoctor/src/table.dart';

/// Renders [value] the way Ruby string interpolation does: `toString`,
/// except `null` (and, via callers, Ruby `nil`) renders as the empty
/// string instead of `'null'`.
String _s(Object? value) => value?.toString() ?? '';

/// Repeats [value] [count] times (port of Ruby's `String#*`).
String _repeat(String value, int count) =>
    count <= 0 ? '' : List<String>.filled(count, value).join();

/// Splits [value] on the first [separator] (port of Ruby's
/// `String#split(sep, 2)` destructured into two variables).
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
final RegExp _stemBreakRx = RegExp(r' *\\\n(?:\\\?\n)*|\n\n+');

/// Matches everything before the `<svg` start tag (port of
/// `SvgPreambleRx`; the non-Opal branch; Ruby `\A` is `^` without
/// `multiLine` in Dart).
final RegExp _svgPreambleRx = RegExp(r'^.*?(?=<svg[\s>])', dotAll: true);

/// Matches the `<svg` start tag (port of `SvgStartTagRx`).
final RegExp _svgStartTagRx = RegExp(r'^<svg(?:\s[^>]*)?>');

/// Matches `width`/`height`/`style` attributes on the `<svg` start tag
/// (port of `DimensionAttributeRx`; `CC_ANY` is `.`).
final RegExp _dimensionAttributeRx = RegExp(
  r'''\s(?:width|height|style)=(["']).*?\1''',
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

/// Renders [delimiters] the way Ruby's `Array#inspect` does (backslash
/// escaping plus double quotes), as embedded in the MathJax configuration
/// script (results verified against the Ruby runtime).
String _inspectDelimiters(List<String> delimiters) =>
    '[${delimiters.map((delimiter) => '"${delimiter.replaceAll(r'\', r'\\')}"').join(', ')}]';

/// Ruby `Array#inspect` of the inline latexmath delimiters (see above).
final String _inlineLatexmathInspect = _inspectDelimiters(
  _inlineMathDelimiters['latexmath']!,
);

/// Ruby `Array#inspect` of the block latexmath delimiters (see above).
final String _blockLatexmathInspect = _inspectDelimiters(
  _blockMathDelimiters['latexmath']!,
);

/// Ruby `Array#inspect` of the block asciimath delimiters (see above).
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

/// The syntax-highlighter surface consumed by the HTML5 converter.
///
/// Mirrors the `SyntaxHighlighter::Base` API used by `html5.rb`: [name]
/// (e.g. `'rouge'`), [canHighlight] (`highlight?`), [format], [hasDocinfo]
/// (`docinfo?`) and [docinfo]. The full framework (registry, factory and
/// the wiring to the adapters in `highlight/`) arrives with the converter
/// wave; until then `Document.syntaxHighlighter` is cast to this interface
/// when set. [location] is `'head'` or `'footer'`.
abstract interface class NodeSyntaxHighlighter {
  /// The highlighter name (selects the `{name}-css` document attribute).
  String get name;

  /// Whether this highlighter performs highlighting (`highlight?`).
  bool get canHighlight;

  /// Formats the source [node] written in [language] as highlighted HTML.
  ///
  /// [opts] carries `css_mode`, `style` (both only when [canHighlight])
  /// and `nowrap`, exactly as `html5.rb` builds them.
  String format(
    AbstractBlock node,
    String? language,
    Map<String, Object?> opts,
  );

  /// Whether this highlighter injects markup at [location] (`docinfo?`).
  bool hasDocinfo(String location);

  /// Returns the markup injected at [location] for [node] (`docinfo`).
  String docinfo(
    String location,
    Document node, {
    required String cdnBaseUrl,
    required bool linkcss,
    required String selfClosingTagSlash,
  });
}

/// A built-in [Converter] implementation that generates HTML 5 output.
///
/// Port of `Asciidoctor::Converter::Html5Converter`. Each `convert*`
/// method mirrors its Ruby `convert_*` namesake; template selection that
/// Ruby performs by method dispatch is expressed as [handle] registrations
/// below (see the library docs).
class Html5Converter extends ConverterBase {
  /// Creates a converter for [backend] with constructor options [opts].
  ///
  /// `opts['htmlsyntax'] == 'xml'` selects XML mode (void elements close
  /// with a slash and boolean attributes render as `name="name"`).
  Html5Converter(super.backend, [super.opts])
    : _xmlMode = opts['htmlsyntax'] == 'xml',
      _voidElementSlash = opts['htmlsyntax'] == 'xml' ? '/' : '' {
    initBackendTraits(<String, Object?>{
      'basebackend': 'html',
      'filetype': 'html',
      'htmlsyntax': _xmlMode ? 'xml' : 'html',
      'outfilesuffix': '.html',
      'supports_templates': true,
    });
    handle(
      'inline_quoted',
      (node, [opts]) => convertInlineQuoted(node as Inline),
    );
    handle('paragraph', (node, [opts]) => convertParagraph(node as Block));
    handle(
      'inline_anchor',
      (node, [opts]) => convertInlineAnchor(node as Inline),
    );
    handle('section', (node, [opts]) => convertSection(node as Section));
    handle('listing', (node, [opts]) => convertListing(node as Block));
    handle('literal', (node, [opts]) => convertLiteral(node as Block));
    handle('ulist', (node, [opts]) => convertUlist(node as ListBlock));
    handle('olist', (node, [opts]) => convertOlist(node as ListBlock));
    handle('dlist', (node, [opts]) => convertDlist(node as ListBlock));
    handle('admonition', (node, [opts]) => convertAdmonition(node as Block));
    handle('colist', (node, [opts]) => convertColist(node as ListBlock));
    handle('embedded', (node, [opts]) => convertEmbedded(node as Document));
    handle('example', (node, [opts]) => convertExample(node as Block));
    handle(
      'floating_title',
      (node, [opts]) => convertFloatingTitle(node as Block),
    );
    handle('image', (node, [opts]) => convertImage(node as Block));
    handle(
      'inline_break',
      (node, [opts]) => convertInlineBreak(node as Inline),
    );
    handle(
      'inline_button',
      (node, [opts]) => convertInlineButton(node as Inline),
    );
    handle(
      'inline_callout',
      (node, [opts]) => convertInlineCallout(node as Inline),
    );
    handle(
      'inline_footnote',
      (node, [opts]) => convertInlineFootnote(node as Inline),
    );
    handle(
      'inline_image',
      (node, [opts]) => convertInlineImage(node as Inline),
    );
    handle(
      'inline_indexterm',
      (node, [opts]) => convertInlineIndexterm(node as Inline),
    );
    handle('inline_kbd', (node, [opts]) => convertInlineKbd(node as Inline));
    handle('inline_menu', (node, [opts]) => convertInlineMenu(node as Inline));
    handle('open', (node, [opts]) => convertOpen(node as Block));
    handle('page_break', (node, [opts]) => convertPageBreak(node as Block));
    handle('preamble', (node, [opts]) => convertPreamble(node as Block));
    handle('quote', (node, [opts]) => convertQuote(node as Block));
    handle('sidebar', (node, [opts]) => convertSidebar(node as Block));
    handle('stem', (node, [opts]) => convertStem(node as Block));
    handle('table', (node, [opts]) => convertTable(node as Table));
    handle(
      'thematic_break',
      (node, [opts]) => convertThematicBreak(node as Block),
    );
    handle('verse', (node, [opts]) => convertVerse(node as Block));
    handle('video', (node, [opts]) => convertVideo(node as Block));
    handle('document', (node, [opts]) => convertDocument(node as Document));
    handle('toc', (node, [opts]) => convertToc(node as Block));
    handle('pass', (node, [opts]) => contentOnly(node));
    handle('audio', (node, [opts]) => convertAudio(node as Block));
    handle(
      'outline',
      (node, [opts]) => convertOutline(node as AbstractBlock, opts),
    );
  }

  /// Quote tags by quoted-text type (port of `QUOTE_TAGS`).
  ///
  /// Each entry holds the opening tag, the closing tag and, for tags that
  /// carry attributes, a trailing `true`. Lookups miss with `['', '']`
  /// (the Ruby `Hash` default).
  static const Map<String, List<Object>> quoteTags = <String, List<Object>>{
    'monospaced': <Object>['<code>', '</code>', true],
    'emphasis': <Object>['<em>', '</em>', true],
    'strong': <Object>['<strong>', '</strong>', true],
    'double': <Object>['&#8220;', '&#8221;'],
    'single': <Object>['&#8216;', '&#8217;'],
    'mark': <Object>['<mark>', '</mark>', true],
    'superscript': <Object>['<sup>', '</sup>', true],
    'subscript': <Object>['<sub>', '</sub>', true],
    'asciimath': <Object>[r'\$', r'\$'],
    'latexmath': <Object>[r'\(', r'\)'],
  };

  /// Default quote tags for unknown quoted-text types.
  static const List<Object> _defaultQuoteTags = <Object>['', ''];

  /// Whether void elements close with a slash (the `xml` htmlsyntax).
  final bool _xmlMode;

  /// The void-element slash: `'/'` in XML mode, else `''`.
  final String _voidElementSlash;

  /// Memoized document refs catalog (port of `@refs`).
  Map<String, Object?>? _refs;

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
    var assetUriScheme = node.attr('asset-uri-scheme', 'https') as String;
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
    result.add(
      '<html${_xmlMode ? ' xmlns="http://www.w3.org/1999/xhtml"' : ''}$langAttribute>',
    );
    result.add(
      '<head>\n'
      '<meta charset="${_s(node.attr('encoding', 'UTF-8'))}"$slash>\n'
      '<meta http-equiv="X-UA-Compatible" content="IE=edge"$slash>\n'
      '<meta name="viewport" content="width=device-width, initial-scale=1.0"$slash>',
    );
    final reproducible = node.hasAttr('reproducible');
    if (!reproducible) {
      result.add(
        '<meta name="generator" content="Asciidoctor ${_s(node.attr('asciidoctor-version'))}"$slash>',
      );
    }
    if (node.hasAttr('app-name')) {
      result.add(
        '<meta name="application-name" content="${_s(node.attr('app-name'))}"$slash>',
      );
    }
    if (node.hasAttr('description')) {
      result.add(
        '<meta name="description" content="${_s(node.attr('description'))}"$slash>',
      );
    }
    if (node.hasAttr('keywords')) {
      result.add(
        '<meta name="keywords" content="${_s(node.attr('keywords'))}"$slash>',
      );
    }
    if (node.hasAttr('authors')) {
      final authors = node.subReplacements(node.attr('authors') as String);
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
      final iconHref = node.attr('favicon') as String;
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

    if (_defaultStylesheetKeys.contains(node.attr('stylesheet'))) {
      final webfonts = node.attr('webfonts');
      if (webfonts != null && webfonts != false) {
        result.add(
          '<link rel="stylesheet" href="$assetUriScheme//fonts.googleapis.com/css?family=${(webfonts as String).isEmpty ? 'Open+Sans:300,300italic,400,400italic,600,600italic%7CNoto+Serif:400,400italic,700,700italic%7CNoto+Sans+Mono:400,700' : webfonts}"$slash>',
        );
      }
      if (linkcss) {
        result.add(
          '<link rel="stylesheet" href="${node.normalizeWebPath(Stylesheets.defaultStylesheetName, node.attr('stylesdir') as String?, false)}"$slash>',
        );
      } else {
        result.add(
          '<style>\n${Stylesheets.instance.primaryStylesheetData}\n</style>',
        );
      }
    } else if (node.hasAttr('stylesheet')) {
      if (linkcss) {
        result.add(
          '<link rel="stylesheet" href="${node.normalizeWebPath(node.attr('stylesheet') as String, node.attr('stylesdir') as String?)}"$slash>',
        );
      } else {
        result.add(
          '<style>\n${_s(node.readContents(node.attr('stylesheet') as String, start: node.attr('stylesdir') as String?, warnOnFailure: true, label: 'stylesheet'))}\n</style>',
        );
      }
    }

    if (node.hasAttr('icons', 'font')) {
      if (node.hasAttr('iconfont-remote')) {
        result.add(
          '<link rel="stylesheet" href="${_s(node.attr('iconfont-cdn', '$cdnBaseUrl/font-awesome/$_fontAwesomeVersion/css/font-awesome.min.css'))}"$slash>',
        );
      } else {
        final iconfontStylesheet =
            '${_s(node.attr('iconfont-name', 'font-awesome'))}.css';
        result.add(
          '<link rel="stylesheet" href="${node.normalizeWebPath(iconfontStylesheet, node.attr('stylesdir') as String?, false)}"$slash>',
        );
      }
    }

    final syntaxHlValue = node.syntaxHighlighter;
    final syntaxHl = isTruthy(syntaxHlValue)
        ? syntaxHlValue as NodeSyntaxHighlighter
        : null;
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
              '<span id="author${idx > 1 ? idx : ''}" class="author">${node.subReplacements(author.name as String)}</span>$br',
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
              '<span id="revnumber">${(node.attr('version-label') ?? '').toString().toLowerCase()} ${_s(node.attr('revnumber'))}${node.hasAttr('revdate') ? ',' : ''}</span>',
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
            result.add('<div class="details">');
            result.addAll(details);
            result.add('</div>');
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
      result.add('<div id="footer"$maxWidthAttr>');
      result.add('<div id="footer-text">');
      if (node.hasAttr('revnumber')) {
        result.add(
          '${_s(node.attr('version-label'))} ${_s(node.attr('revnumber'))}$br',
        );
      }
      if (node.hasAttr('last-update-label') && !reproducible) {
        result.add(
          '${_s(node.attr('last-update-label'))} ${_s(node.attr('docdatetime'))}',
        );
      }
      result.add('</div>');
      result.add('</div>');
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
      // JavaScript compat (emulates JSON.stringify); the values below are
      // the Ruby `Array#inspect` results, verified against the runtime.
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
        'MathJax.Hub.Register.StartupHook("AsciiMath Jax Ready", function () {\n'
        '  MathJax.InputJax.AsciiMath.postfilterHooks.Add(function (data, node) {\n'
        '    if ((node = data.script.parentNode) && (node = node.parentNode) && node.classList.contains("stemblock")) {\n'
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

    result.add('</body>');
    result.add('</html>');
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
        (node.attr('toc-placement') as String?) != 'macro' &&
        (node.attr('toc-placement') as String?) != 'preamble') {
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
  String? convertOutline(AbstractBlock node, [Map<String, Object?>? opts]) {
    if (!node.hasSections) {
      return null;
    }
    final sections = node.sections;
    final parts =
        node.context == 'document' && (node as Document).multipart == true;
    final sectlevel = parts ? 0 : sections[0].level!;
    final sectnumlevels = opts != null && opts['sectnumlevels'] is int
        ? opts['sectnumlevels'] as int
        : rubyToInteger(node.document!.attributes['sectnumlevels'] ?? 3);
    int toclevels;
    final optsToclevels = opts?['toclevels'];
    if (optsToclevels is int) {
      toclevels = optsToclevels;
    } else {
      final rawToclevels = node.document!.attributes['toclevels'];
      if (rawToclevels != null) {
        toclevels = rubyToInteger(rawToclevels);
        if (toclevels < 1 && !parts) {
          toclevels = 1;
        }
      } else {
        toclevels = 2;
      }
    }
    final result = <String>['<ul class="sectlevel$sectlevel">'];
    for (final child in sections) {
      final section = child as Section;
      final slevel = section.level!;
      final stoclevels = section.hasAttr('toclevels')
          ? rubyToInteger(section.attr('toclevels'))
          : toclevels;
      if (slevel > stoclevels) {
        continue;
      }
      final String stitle;
      if (section.caption != null) {
        stitle = section.captionedTitle();
      } else if (isTruthy(section.numbered) && slevel <= sectnumlevels) {
        if (slevel < 2 && (node.document! as Document).doctype == 'book') {
          final signifierAttrs = node.document!.attributes;
          switch (section.sectname) {
            case 'chapter':
              final signifier = signifierAttrs['chapter-signifier'];
              stitle =
                  '${isTruthy(signifier) ? '$signifier ' : ''}${section.sectnum()} ${section.title!}';
            case 'part':
              final signifier = signifierAttrs['part-signifier'];
              // Ruby calls `sectnum nil, ':'`; with level < 2 that renders
              // the bare numeral plus ':', identical to `sectnum('.', ':')`.
              stitle =
                  '${isTruthy(signifier) ? '$signifier ' : ''}${section.sectnum('.', ':')} ${section.title!}';
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
      final otag = slevel == sectlevel
          ? '<li>'
          : '<li class="sectlevel$slevel">';
      final String? childTocLevel;
      if (slevel < stoclevels) {
        childTocLevel = convertOutline(section, <String, Object?>{
          'toclevels': stoclevels,
          'sectnumlevels': sectnumlevels,
        });
      } else {
        childTocLevel = null;
      }
      if (childTocLevel != null) {
        result.add('$otag<a href="#${_s(section.id)}">$cleanTitle</a>');
        result.add(childTocLevel);
        result.add('</li>');
      } else {
        result.add('$otag<a href="#${_s(section.id)}">$cleanTitle</a></li>');
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
      } else if (isTruthy(node.numbered) &&
          level <= rubyToInteger(docAttrs['sectnumlevels'] ?? 3)) {
        if (level < 2 && (node.document! as Document).doctype == 'book') {
          switch (node.sectname) {
            case 'chapter':
              final signifier = docAttrs['chapter-signifier'];
              resolvedTitle =
                  '${isTruthy(signifier) ? '$signifier ' : ''}${node.sectnum()} ${node.title!}';
            case 'part':
              final signifier = docAttrs['part-signifier'];
              // See convertOutline for the `sectnum nil, ':'` mapping.
              resolvedTitle =
                  '${isTruthy(signifier) ? '$signifier ' : ''}${node.sectnum('.', ':')} ${node.title!}';
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
      if (isTruthy(docAttrs['sectlinks'])) {
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
      if (isTruthy(docAttrs['sectanchors'])) {
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
    if (level == 0) {
      return '<h1$idAttr class="sect0${isTruthy(role) ? ' ${_s(role)}' : ''}">$linkedTitle</h1>\n'
          '${_s(node.content())}';
    }
    return '<div class="sect$level${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
        '<h${level + 1}$idAttr>$linkedTitle</h${level + 1}>\n'
        '${level == 1 ? '<div class="sectionbody">\n${_s(node.content())}\n</div>' : _s(node.content())}\n'
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
            '<img src="${node.iconUri(name)}" alt="${_s(node.attr('textlabel'))}"$_voidElementSlash>';
      }
    } else {
      label = '<div class="title">${_s(node.attr('textlabel'))}</div>';
    }
    final role = node.role;
    return '<div$idAttr class="admonitionblock $name${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
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
    return '<div$idAttribute$classAttribute>\n'
        '$titleElement<div class="content">\n'
        '<audio src="${node.mediaUri(node.attr('target') as String)}$timeAnchor"${node.hasOption('autoplay') ? _appendBooleanAttribute('autoplay', xml) : ''}${node.hasOption('nocontrols') ? '' : _appendBooleanAttribute('controls', xml)}${node.hasOption('loop') ? _appendBooleanAttribute('loop', xml) : ''}>\n'
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
        final listItem = item as ListItem;
        num += 1;
        final String numLabel;
        if (fontIcons) {
          numLabel = '<i class="conum" data-value="$num"></i><b>$num</b>';
        } else {
          numLabel =
              '<img src="${node.iconUri('callouts/$num')}" alt="$num"$_voidElementSlash>';
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
        final listItem = item as ListItem;
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
        for (final pair in node.items) {
          final parts = pair as List<Object?>;
          final terms = parts[0] as List<Object?>;
          final dd = parts[1] as ListItem?;
          result.add('<li>');
          for (final term in terms) {
            result.add('<p><em>${_s((term as ListItem).text)}</em></p>');
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
              ? ' width="${_chompPercent(node.attr('labelwidth') as String)}%"'
              : '';
          result.add('<col$labelWidth$slash>');
          final itemWidth = node.hasAttr('itemwidth')
              ? ' width="${_chompPercent(node.attr('itemwidth') as String)}%"'
              : '';
          result.add('<col$itemWidth$slash>');
          result.add('</colgroup>');
        }
        for (final pair in node.items) {
          final parts = pair as List<Object?>;
          final terms = parts[0] as List<Object?>;
          final dd = parts[1] as ListItem?;
          result.add('<tr>');
          result.add(
            '<td class="hdlist1${node.hasOption('strong') ? ' strong' : ''}">',
          );
          var firstTerm = true;
          for (final term in terms) {
            if (!firstTerm) {
              result.add('<br$slash>');
            }
            result.add(_s((term as ListItem).text));
            firstTerm = false;
          }
          result.add('</td>');
          result.add('<td class="hdlist2">');
          if (dd != null) {
            if (dd.hasText) {
              result.add('<p>${_s(dd.text)}</p>');
            }
            if (dd.hasBlocks) {
              result.add(_s(dd.content()));
            }
          }
          result.add('</td>');
          result.add('</tr>');
        }
        result.add('</table>');
      default:
        result.add('<dl>');
        final dtStyleAttribute = node.style != null ? '' : ' class="hdlist1"';
        for (final pair in node.items) {
          final parts = pair as List<Object?>;
          final terms = parts[0] as List<Object?>;
          final dd = parts[1] as ListItem?;
          for (final term in terms) {
            result.add(
              '<dt$dtStyleAttribute>${_s((term as ListItem).text)}</dt>',
            );
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
      return '<details$idAttribute$classAttribute${node.hasOption('open') ? ' open' : ''}>\n'
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
    return '<div$idAttribute class="exampleblock${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
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
    final target = node.attr('target') as String;
    final widthAttr = node.hasAttr('width')
        ? ' width="${_s(node.attr('width'))}"'
        : '';
    final heightAttr = node.hasAttr('height')
        ? ' height="${_s(node.attr('height'))}"'
        : '';
    final String img;
    String? src;
    if ((node.hasAttr('format', 'svg') || target.contains('.svg')) &&
        node.document!.safe < SafeMode.secure) {
      if (node.hasOption('inline')) {
        img =
            readSvgContents(node, target) ??
            '<span class="alt">${_s(node.alt)}</span>';
      } else if (node.hasOption('interactive')) {
        final fallback = node.hasAttr('fallback')
            ? '<img src="${node.imageUri(node.attr('fallback') as String)}" alt="${_encodeAttributeValue(node.alt)}"$widthAttr$heightAttr$_voidElementSlash>'
            : '<span class="alt">${_s(node.alt)}</span>';
        src = node.imageUri(target);
        img =
            '<object type="image/svg+xml" data="$src"$widthAttr$heightAttr>$fallback</object>';
      } else {
        src = node.imageUri(target);
        img =
            '<img src="$src" alt="${_encodeAttributeValue(node.alt)}"$widthAttr$heightAttr$_voidElementSlash>';
      }
    } else {
      src = node.imageUri(target);
      img =
          '<img src="$src" alt="${_encodeAttributeValue(node.alt)}"$widthAttr$heightAttr$_voidElementSlash>';
    }
    var wrappedImg = img;
    Object? hrefAttrVal;
    if (node.hasAttr('link') &&
        (((hrefAttrVal = node.attr('link')) != 'self') ||
            ((hrefAttrVal = src) != null))) {
      wrappedImg =
          '<a class="image" href="${_s(hrefAttrVal)}"${_appendLinkConstraintAttrs(node).join()}>$img</a>';
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
    final NodeSyntaxHighlighter? syntaxHl;
    final Map<String, Object?> hlOpts;
    var preOpen = '';
    var preClose = '';
    if (node.style == 'source') {
      lang = node.attr('language') as String?;
      final syntaxHlValue = (node.document! as Document).syntaxHighlighter;
      if (isTruthy(syntaxHlValue)) {
        syntaxHl = syntaxHlValue as NodeSyntaxHighlighter;
        final docAttrs = node.document!.attributes;
        if (syntaxHl.canHighlight) {
          hlOpts = <String, Object?>{
            'css_mode': (docAttrs['${syntaxHl.name}-css'] ?? 'class')
                .toString(),
            'style': docAttrs['${syntaxHl.name}-style'],
          };
        } else {
          hlOpts = <String, Object?>{};
        }
        hlOpts['nowrap'] = nowrap;
      } else {
        syntaxHl = null;
        hlOpts = <String, Object?>{};
        preOpen =
            '<pre class="highlight${nowrap ? ' nowrap' : ''}"><code${lang != null ? ' class="language-$lang" data-lang="$lang"' : ''}>';
        preClose = '</code></pre>';
      }
    } else {
      lang = null;
      syntaxHl = null;
      hlOpts = <String, Object?>{};
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
    return '<div$idAttribute class="listingblock${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
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
    return '<div$idAttribute class="literalblock${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
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
    final style = node.style as String;
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
    return '<div$idAttribute class="stemblock${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
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
    final reversedAttribute = node.hasOption('reversed')
        ? _appendBooleanAttribute('reversed', _xmlMode)
        : '';
    result.add(
      '<ol class="${_s(node.style)}"$typeAttribute$startAttribute$reversedAttribute>',
    );

    for (final item in node.items) {
      final listItem = item as ListItem;
      if (listItem.id != null) {
        result.add(
          '<li id="${listItem.id}"${listItem.role != null ? ' class="${_s(listItem.role)}"' : ''}>',
        );
      } else if (listItem.role != null) {
        result.add('<li class="${_s(listItem.role)}">');
      } else {
        result.add('<li>');
      }
      result.add('<p>${_s(listItem.text)}</p>');
      if (listItem.hasBlocks) {
        result.add(_s(listItem.content()));
      }
      result.add('</li>');
    }

    result.add('</ol>');
    result.add('</div>');
    return result.join(lf);
  }

  /// Converts the [node] open block.
  String convertOpen(Block node) {
    final style = node.style;
    if (style == 'abstract') {
      if (identical(node.parent, node.document) &&
          (node.document! as Document).doctype == 'book') {
        logger.warn(
          'abstract block cannot be used in a document without a doctitle when doctype is book. Excluding block content.',
        );
        return '';
      }
      final idAttr = node.id != null ? ' id="${node.id}"' : '';
      final titleEl = node.hasTitle
          ? '<div class="title">${_s(node.title)}</div>\n'
          : '';
      final role = node.role;
      return '<div$idAttr class="quoteblock abstract${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
          '$titleEl<blockquote>\n'
          '${_s(node.content())}\n'
          '</blockquote>\n'
          '</div>';
    }
    if (style == 'partintro' &&
        (node.level! > 0 ||
            node.parent!.context != 'section' ||
            (node.document! as Document).doctype != 'book')) {
      logger.error(
        'partintro block can only be used when doctype is book and must be a child of a book part. Excluding block content.',
      );
      return '';
    }
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
    final titleEl = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final role = node.role;
    return '<div$idAttr class="openblock${style != null && style != 'open' ? ' $style' : ''}${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
        '$titleEl<div class="content">\n'
        '${_s(node.content())}\n'
        '</div>\n'
        '</div>';
  }

  /// Converts the [node] page break.
  String convertPageBreak(Block node) => '<div class="page-break"></div>';

  /// Converts the [node] paragraph.
  String convertParagraph(Block node) {
    final String attributes;
    if (node.role != null) {
      attributes =
          '${node.id != null ? ' id="${node.id}"' : ''} class="paragraph ${_s(node.role)}"';
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
    final attribution = node.hasAttr('attribution')
        ? node.attr('attribution')
        : null;
    final citetitle = node.hasAttr('citetitle') ? node.attr('citetitle') : null;
    final String attributionElement;
    if (attribution != null || citetitle != null) {
      final citeElement = citetitle != null
          ? '<cite>${_s(citetitle)}</cite>'
          : '';
      final attributionText = attribution != null
          ? '&#8212; ${_s(attribution)}${citetitle != null ? '<br$_voidElementSlash>\n' : ''}'
          : '';
      attributionElement =
          '\n<div class="attribution">\n$attributionText$citeElement\n</div>';
    } else {
      attributionElement = '';
    }

    return '<div$idAttribute$classAttribute>$titleElement\n'
        '<blockquote>\n'
        '${_s(node.content())}\n'
        '</blockquote>$attributionElement\n'
        '</div>';
  }

  /// Converts the [node] thematic break.
  String convertThematicBreak(Block node) {
    final classAttribute = node.role != null ? ' class="${_s(node.role)}"' : '';
    return '<hr$classAttribute$_voidElementSlash>';
  }

  /// Converts the [node] sidebar block.
  String convertSidebar(Block node) {
    final idAttribute = node.id != null ? ' id="${node.id}"' : '';
    final titleElement = node.hasTitle
        ? '<div class="title">${_s(node.title)}</div>\n'
        : '';
    final role = node.role;
    return '<div$idAttribute class="sidebarblock${isTruthy(role) ? ' ${_s(role)}' : ''}">\n'
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
    if (isTruthy(stripes)) {
      classes.add('stripes-${_s(stripes)}');
    }
    var widthAttribute = '';
    final autowidth = node.hasOption('autowidth') && !node.hasAttr('width');
    final tablewidth = node.attr('tablepcwidth');
    if (autowidth) {
      classes.add('fit-content');
    } else if (tablewidth == 100) {
      classes.add('stretch');
    } else {
      widthAttribute = ' width="${_s(tablewidth)}%"';
    }
    if (node.hasAttr('float')) {
      classes.add(_s(node.attr('float')));
    }
    final role = node.role;
    if (isTruthy(role)) {
      classes.add(_s(role));
    }
    final classAttribute = ' class="${classes.join(' ')}"';

    result.add('<table$idAttribute$classAttribute$widthAttribute>');
    if (node.hasTitle) {
      result.add('<caption class="title">${node.captionedTitle()}</caption>');
    }
    if ((node.attr('rowcount') as int) > 0) {
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
                : '<col width="${_s(col.attr('colpcwidth'))}%"$slash>',
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
                  final content = cell.content() as List<Object?>;
                  cellContent = content.isEmpty
                      ? ''
                      : '<p class="tableblock">${content.map(_s).join('</p>\n<p class="tableblock">')}</p>';
              }
            }

            final cellTagName = (tsec == 'head' || cell.style == 'header')
                ? 'th'
                : 'td';
            final cellClassAttribute =
                ' class="tableblock halign-${_s(cell.attr('halign'))} valign-${_s(cell.attr('valign'))}"';
            final cellColspanAttribute = isTruthy(cell.colspan)
                ? ' colspan="${_s(cell.colspan)}"'
                : '';
            final cellRowspanAttribute = isTruthy(cell.rowspan)
                ? ' rowspan="${_s(cell.rowspan)}"'
                : '';
            final cellStyleAttribute =
                (node.document! as Document).hasAttr('cellbgcolor')
                ? ' style="background-color: ${_s((node.document! as Document).attr('cellbgcolor'))};"'
                : '';
            result.add(
              '<$cellTagName$cellClassAttribute$cellColspanAttribute$cellRowspanAttribute$cellStyleAttribute>$cellContent</$cellTagName>',
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
        ? rubyToInteger(node.attr('levels'))
        : null;
    final role = node.hasRole()
        ? _s(node.role)
        : _s(doc.attr('toc-class', 'toc'));

    return '<div$idAttr class="$role">\n'
        '<div$titleIdAttr class="title">$title</div>\n'
        '${_s((doc.converter as Converter).convert(doc, 'outline', <String, Object?>{'toclevels': levels}))}\n'
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
      final listItem = item as ListItem;
      if (listItem.id != null) {
        result.add(
          '<li id="${listItem.id}"${listItem.role != null ? ' class="${_s(listItem.role)}"' : ''}>',
        );
      } else if (listItem.role != null) {
        result.add('<li class="${_s(listItem.role)}">');
      } else {
        result.add('<li>');
      }
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

    result.add('</ul>');
    result.add('</div>');
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
    final attribution = node.hasAttr('attribution')
        ? node.attr('attribution')
        : null;
    final citetitle = node.hasAttr('citetitle') ? node.attr('citetitle') : null;
    final String attributionElement;
    if (attribution != null || citetitle != null) {
      final citeElement = citetitle != null
          ? '<cite>${_s(citetitle)}</cite>'
          : '';
      final attributionText = attribution != null
          ? '&#8212; ${_s(attribution)}${citetitle != null ? '<br$_voidElementSlash>\n' : ''}'
          : '';
      attributionElement =
          '\n<div class="attribution">\n$attributionText$citeElement\n</div>';
    } else {
      attributionElement = '';
    }

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
        ) as String;
        if (assetUriScheme.isNotEmpty) {
          assetUriScheme = '$assetUriScheme:';
        }
        final startAnchor = node.hasAttr('start')
            ? '#at=${_s(node.attr('start'))}'
            : '';
        final delimiter = <String>['?'];
        String popDelimiter() =>
            delimiter.isNotEmpty ? delimiter.removeLast() : '&amp;';
        final targetAndHash = _split2(node.attr('target') as String, '/');
        final target = targetAndHash.$1;
        var hash = targetAndHash.$2;
        hash ??= node.attr('hash') as String?;
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
        ) as String;
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
        final targetAndList = _split2(node.attr('target') as String, '/');
        var target = targetAndList.$1;
        final list = targetAndList.$2 ?? node.attr('list') as String?;
        final String listParam;
        if (list != null) {
          listParam = '&amp;list=$list';
        } else {
          // parse dynamic playlist syntax: video_id1,video_id2,...
          final targetAndPlaylist = _split2(target, ',');
          target = targetAndPlaylist.$1;
          final playlist =
              targetAndPlaylist.$2 ?? node.attr('playlist') as String?;
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
      case 'wistia':
        var assetUriScheme = (node.document! as Document).attr(
          'asset-uri-scheme',
          'https',
        ) as String;
        if (assetUriScheme.isNotEmpty) {
          assetUriScheme = '$assetUriScheme:';
        }
        final delimiter = <String>['?'];
        String popDelimiter() =>
            delimiter.isNotEmpty ? delimiter.removeLast() : '&amp;';
        final startAnchor = node.hasAttr('start')
            ? '${popDelimiter()}time=${_s(node.attr('start'))}'
            : '';
        final endVideoBehaviorParam = node.hasOption('loop')
            ? '${popDelimiter()}endVideoBehavior=loop'
            : (node.hasOption('reset')
                  ? '${popDelimiter()}endVideoBehavior=reset'
                  : '');
        final target = node.attr('target') as String;
        final autoplayParam = node.hasOption('autoplay')
            ? '${popDelimiter()}autoPlay=true'
            : '';
        final mutedParam = node.hasOption('muted')
            ? '${popDelimiter()}muted=true'
            : '';
        return '<div$idAttribute$classAttribute>$titleElement\n'
            '<div class="content">\n'
            '<iframe$widthAttribute$heightAttribute src="$assetUriScheme//fast.wistia.com/embed/iframe/$target$startAnchor$autoplayParam$endVideoBehaviorParam$mutedParam" frameborder="0"${node.hasOption('nofullscreen') ? '' : _appendBooleanAttribute('allowfullscreen', xml)} class="wistia_embed" name="wistia_embed"></iframe>\n'
            '</div>\n'
            '</div>';
      default:
        final posterVal = node.attr('poster') as String?;
        final posterAttribute = posterVal == null || posterVal.isEmpty
            ? ''
            : ' poster="${node.mediaUri(posterVal)}"';
        final preloadVal = node.attr('preload') as String?;
        final preloadAttribute = preloadVal == null || preloadVal.isEmpty
            ? ''
            : ' preload="$preloadVal"';
        final startT = node.attr('start');
        final endT = node.attr('end');
        final timeAnchor = startT != null || endT != null
            ? '#t=${_s(startT)}${endT != null ? ',${_s(endT)}' : ''}'
            : '';
        return '<div$idAttribute$classAttribute>$titleElement\n'
            '<div class="content">\n'
            '<video src="${node.mediaUri(node.attr('target') as String)}$timeAnchor"$widthAttribute$heightAttribute$posterAttribute${node.hasOption('autoplay') ? _appendBooleanAttribute('autoplay', xml) : ''}${node.hasOption('muted') ? _appendBooleanAttribute('muted', xml) : ''}${node.hasOption('nocontrols') ? '' : _appendBooleanAttribute('controls', xml)}${node.hasOption('loop') ? _appendBooleanAttribute('loop', xml) : ''}$preloadAttribute>\n'
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
          final initial = isTruthy(node.role)
              ? <String>[' class="${_s(node.role)}"']
              : <String>[];
          final attrs = _appendLinkConstraintAttrs(node, initial).join();
          final text = node.text ?? _s(path);
          return '<a href="${_s(node.target)}"$attrs>$text</a>';
        }
        final attrs = node.role != null ? ' class="${_s(node.role)}"' : '';
        var text = node.text;
        if (text == null) {
          final refs = _refs ??=
              node.document!.catalog['refs'] as Map<String, Object?>;
          final refid = node.attributes['refid'] as String?;
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
                  node.attr('xrefstyle', null, true) as String?,
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
    final guard = node.attributes['guard'];
    if (guard is List<Object?>) {
      return '&lt;!--<b class="conum">(${_s(node.text)})</b>--&gt;';
    }
    return '${_s(guard)}<b class="conum">(${_s(node.text)})</b>';
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
    final target = node.target as String;
    final type = node.type ?? 'image';
    final String img;
    String? src;
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
      } else if (isTruthy(icons)) {
        var attrs = node.hasAttr('width')
            ? ' width="${_s(node.attr('width'))}"'
            : '';
        if (node.hasAttr('height')) {
          attrs = '$attrs height="${_s(node.attr('height'))}"';
        }
        if (node.hasAttr('title')) {
          attrs = '$attrs title="${_s(node.attr('title'))}"';
        }
        src = node.iconUri(target);
        img =
            '<img src="$src" alt="${_encodeAttributeValue(_s(node.alt))}"$attrs$_voidElementSlash>';
      } else {
        img = '[${_s(node.alt)}&#93;';
      }
    } else {
      var attrs = node.hasAttr('width')
          ? ' width="${_s(node.attr('width'))}"'
          : '';
      if (node.hasAttr('height')) {
        attrs = '$attrs height="${_s(node.attr('height'))}"';
      }
      if (node.hasAttr('title')) {
        attrs = '$attrs title="${_s(node.attr('title'))}"';
      }
      if ((node.hasAttr('format', 'svg') || target.contains('.svg')) &&
          node.document!.safe < SafeMode.secure) {
        if (node.hasOption('inline')) {
          img =
              readSvgContents(node, target) ??
              '<span class="alt">${_s(node.alt)}</span>';
        } else if (node.hasOption('interactive')) {
          final fallback = node.hasAttr('fallback')
              ? '<img src="${node.imageUri(node.attr('fallback') as String)}" alt="${_encodeAttributeValue(_s(node.alt))}"$attrs$_voidElementSlash>'
              : '<span class="alt">${_s(node.alt)}</span>';
          src = node.imageUri(target);
          img =
              '<object type="image/svg+xml" data="$src"$attrs>$fallback</object>';
        } else {
          src = node.imageUri(target);
          img =
              '<img src="$src" alt="${_encodeAttributeValue(_s(node.alt))}"$attrs$_voidElementSlash>';
        }
      } else {
        src = node.imageUri(target);
        img =
            '<img src="$src" alt="${_encodeAttributeValue(_s(node.alt))}"$attrs$_voidElementSlash>';
      }
    }
    var wrappedImg = img;
    Object? hrefAttrVal;
    if (node.hasAttr('link') &&
        (((hrefAttrVal = node.attr('link')) != 'self') ||
            ((hrefAttrVal = src) != null))) {
      wrappedImg =
          '<a class="image" href="${_s(hrefAttrVal)}"${_appendLinkConstraintAttrs(node).join()}>$img</a>';
    }
    final idAttr = node.id != null ? ' id="${node.id}"' : '';
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
    return '<span$idAttr class="$classAttrVal">$wrappedImg</span>';
  }

  /// Converts the [node] inline index term.
  String convertInlineIndexterm(Inline node) =>
      node.type == 'visible' ? _s(node.text) : '';

  /// Converts the [node] inline keyboard shortcut.
  String convertInlineKbd(Inline node) {
    final keys = node.attr('keys') as List<Object?>;
    if (keys.length == 1) {
      return '<kbd>${_s(keys[0])}</kbd>';
    }
    return '<span class="keyseq"><kbd>${keys.map(_s).join('</kbd>+<kbd>')}</kbd></span>';
  }

  /// Converts the [node] inline menu reference.
  String convertInlineMenu(Inline node) {
    final caret = node.document!.hasAttr('icons', 'font')
        ? '&#160;<i class="fa fa-angle-right caret"></i> '
        : '&#160;<b class="caret">&#8250;</b> ';
    final submenuJoiner = '</b>$caret<b class="submenu">';
    final menu = _s(node.attr('menu'));
    final submenus = node.attr('submenus') as List<Object?>;
    if (submenus.isEmpty) {
      final menuitem = node.attr('menuitem');
      if (menuitem != null) {
        return '<span class="menuseq"><b class="menu">$menu</b>$caret<b class="menuitem">${_s(menuitem)}</b></span>';
      }
      return '<b class="menuref">$menu</b>';
    }
    return '<span class="menuseq"><b class="menu">$menu</b>$caret<b class="submenu">${submenus.map(_s).join(submenuJoiner)}</b>$caret<b class="menuitem">${_s(node.attr('menuitem'))}</b></span>';
  }

  /// Converts the [node] inline quoted text.
  String convertInlineQuoted(Inline node) {
    final spec = quoteTags[node.type] ?? _defaultQuoteTags;
    final open = spec[0] as String;
    final close = spec[1] as String;
    final tag = spec.length > 2;
    if (node.id != null) {
      final classAttr = node.role != null ? ' class="${_s(node.role)}"' : '';
      if (tag) {
        return '${open.substring(0, open.length - 1)} id="${node.id}"$classAttr>${_s(node.text)}$close';
      }
      return '<span id="${node.id}"$classAttr>$open${_s(node.text)}$close</span>';
    }
    if (node.role != null) {
      if (tag) {
        return '${open.substring(0, open.length - 1)} class="${_s(node.role)}">${_s(node.text)}$close';
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
  /// NOTE exposed for Bespoke converters (as in Ruby).
  String? readSvgContents(AbstractNode node, String target) {
    var svg = node.readContents(
      target,
      start: node.document!.attr('imagesdir') as String?,
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
          '${newStartTag.substring(0, newStartTag.length - 1)} $dim="${_s(node.attr(dim))}">';
    }
    if (newStartTag != null) {
      svg = '$newStartTag${svg.substring(oldStartTag!.length)}';
    }
    return svg;
  }

  /// Renders the boolean HTML attribute [name] for [xml] mode.
  String _appendBooleanAttribute(String name, bool xml) =>
      xml ? ' $name="$name"' : ' $name';

  /// Appends link-constraint attributes (`target`, `rel`) for [node] to
  /// [attrs] (a fresh list when omitted) and returns it.
  List<String> _appendLinkConstraintAttrs(
    AbstractNode node, [
    List<String>? attrs,
  ]) {
    final result = attrs ?? <String>[];
    final rel = node.hasOption('nofollow') ? 'nofollow' : null;
    final window = node.attributes['window'];
    if (isTruthy(window)) {
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
        nextSectionTitle == nextSectionTitle.toUpperCase()) {
      mannameTitle = mannameTitle.toUpperCase();
    }
    final mannameId = node.attr('manname-id') as String?;
    final mannameIdAttr = mannameId != null ? ' id="$mannameId"' : '';
    return '<h2$mannameIdAttr>$mannameTitle</h2>\n'
        '<div class="sectionbody">\n'
        '<p>${(node.attr('mannames') as List<Object?>).map(_s).join(', ')} - ${_s(node.attr('manpurpose'))}</p>\n'
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
  String? _xreftextOf(Object? ref, String? xrefstyle) {
    if (ref is AbstractBlock) {
      return ref.xreftext(xrefstyle);
    }
    if (ref is Inline) {
      return ref.xreftext(xrefstyle);
    }
    return null;
  }
}
