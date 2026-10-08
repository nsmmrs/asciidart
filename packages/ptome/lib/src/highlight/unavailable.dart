/// The highlighters Ptome does not provide: Rouge, Pygments and
/// CodeRay. Ptome highlights with highlight.js (hilite) only; these
/// names behave as they do in Asciidoctor when their gem is not installed.
library;

import 'package:meta/meta.dart';
import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/highlight/highlight.dart';
import 'package:ptome/src/highlight/syntax_highlighter.dart';
import 'package:ptome/src/logging.dart';

/// A highlighter whose library is not available.
///
/// It warns once (per highlighter, per process) when the first source block
/// asks for it, and wraps source blocks in its `<pre>` element without
/// highlighting them, as Asciidoctor does without the gem.
final class UnavailableHighlighter extends SyntaxHighlighterBase {
  /// The highlighter [name] with [preClass], called [label] in the warning;
  /// [stripLanguageQuery] drops a `?options` suffix of the language in the
  /// output (Rouge does).
  new(
    this.name, {
    required this.preClass,
    required this.label,
    this.stripLanguageQuery = false,
  });

  /// Rouge, as Asciidoctor behaves without the `rouge` gem.
  new rouge()
    : this(
        'rouge',
        preClass: 'rouge',
        label: 'Rouge',
        stripLanguageQuery: true,
      );

  /// Pygments, as Asciidoctor behaves without the `pygments.rb` gem.
  new pygments() : this('pygments', preClass: 'pygments', label: 'Pygments');

  /// CodeRay, as Asciidoctor behaves without the `coderay` gem.
  new coderay() : this('coderay', preClass: 'CodeRay', label: 'CodeRay');

  @override
  final String name;

  @override
  final String preClass;

  /// The name of the highlighter in the warning.
  final String label;

  /// Whether the language loses a `?options` suffix in the output.
  final bool stripLanguageQuery;

  static final Set<String> _warned = {};

  /// Forgets which highlighters warned, so they warn again.
  @visibleForTesting
  static void resetWarnings() => _warned.clear();

  void _warn() {
    if (_warned.add(name)) {
      LoggerManager.logger.warn(
        '$label syntax highlighting is not available. '
        'Functionality disabled.',
      );
    }
  }

  @override
  bool get canHighlight {
    _warn();
    return false;
  }

  @override
  String format(AbstractBlock node, String? language, FormatOptions opts) {
    _warn();
    var lang = language;
    if (stripLanguageQuery && lang != null) {
      final query = lang.indexOf('?');
      if (query >= 0) lang = lang.substring(0, query);
    }
    return wrapSourceBlock(
      preClass: preClass,
      content: node.content() ?? '',
      language: lang,
      nowrap: opts.nowrap,
      transform: opts.transform,
    );
  }
}
