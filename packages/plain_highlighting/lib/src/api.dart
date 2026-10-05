/// The public API of hilite.
library;

import 'package:hilite/src/highlighter.dart';
import 'package:hilite/src/languages/all.g.dart';

/// The result of highlighting code.
final class HighlightResult {
  const new _(
    this.language,
    this.html,
    this.relevance,
    this.illegal,
    this.secondBest,
  );

  factory _of(Highlighted result) => HighlightResult._(
    result.language,
    result.value,
    result.relevance,
    result.illegal,
    result.secondBest == null ? null : HighlightResult._of(result.secondBest!),
  );

  /// The language the code was highlighted as (its registered name), or
  /// `null` when no language fit and the code was left as plain text.
  final String? language;

  /// The highlighted code: HTML with `<span class="hljs-...">` elements, and
  /// special characters escaped.
  final String html;

  /// How well the language fits the code (higher is better).
  final num relevance;

  /// Whether highlighting stopped at something the language does not allow
  /// (only when illegal input is not ignored; the code is then escaped
  /// without highlighting).
  final bool illegal;

  /// For auto-detection, the runner-up language.
  final HighlightResult? secondBest;
}

/// A highlighter with every language of highlight.js 11.12.0.
///
/// Languages are built on first use. One instance can highlight any amount
/// of code; use [hilite] unless you need another [classPrefix].
final class Hilite {
  /// A highlighter whose CSS classes start with [classPrefix].
  new({this.classPrefix = 'hljs-'})
    : _engine = Engine(classPrefix: classPrefix) {
    for (final (name, aliases, build) in allLanguages) {
      _engine.registerLanguage(name, build, aliases: aliases);
    }
  }

  /// The prefix of the CSS classes in the output.
  final String classPrefix;

  final Engine _engine;

  /// The names of the languages, in registration order.
  List<String> get languages => _engine.languageNames;

  /// Whether [nameOrAlias] names a language (`dart`, `js`, `sh`, ...;
  /// case-insensitive).
  bool hasLanguage(String nameOrAlias) =>
      _engine.getLanguage(nameOrAlias) != null;

  /// The display name of the language [nameOrAlias] (`JavaScript`), or
  /// `null` when there is none.
  String? displayName(String nameOrAlias) =>
      _engine.getLanguage(nameOrAlias)?.name;

  /// Highlights [code] as [language] (a name or alias).
  ///
  /// Unless [ignoreIllegals] is `false`, input the language does not allow
  /// is highlighted as well as possible; otherwise the result is the escaped
  /// code with [HighlightResult.illegal] set. Throws an [ArgumentError] for
  /// an unknown language.
  HighlightResult highlight(
    String code, {
    required String language,
    bool ignoreIllegals = true,
  }) => HighlightResult._of(
    _engine.highlight(
      code,
      languageName: language,
      ignoreIllegals: ignoreIllegals,
    ),
  );

  /// Highlights [code] with the language that fits it best, among
  /// [languages] (default: all).
  HighlightResult highlightAuto(String code, {List<String>? languages}) =>
      HighlightResult._of(_engine.highlightAuto(code, languages));
}

/// The default highlighter (`hljs-` classes).
final Hilite hilite = Hilite();
