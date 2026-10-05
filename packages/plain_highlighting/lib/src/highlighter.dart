/// The highlighter: language registry, highlighting and auto-detection.
///
/// Port of the core of `src/highlight.js` (`_highlight`, `highlightAuto`
/// and the registry functions; the browser-only parts are left out).
library;

import 'package:hilite/src/js_string.dart';
import 'package:hilite/src/logger.dart' as logger;
import 'package:hilite/src/mode.dart';
import 'package:hilite/src/mode_compiler.dart';
import 'package:hilite/src/regex.dart' as regex;
import 'package:hilite/src/token_tree.dart';
import 'package:hilite/src/utils.dart';

const int _maxKeywordHits = 7;

/// The result of highlighting.
final class Highlighted {
  /// A result.
  new({
    required this.language,
    required this.value,
    required this.relevance,
    required this.illegal,
    required this.code,
    this.emitter,
    this.top,
  });

  /// The language name, or `null` for plain text.
  final String? language;

  /// The highlighted HTML.
  final String value;

  /// How well the language fits the code.
  final num relevance;

  /// Whether highlighting stopped at an illegal lexeme.
  final bool illegal;

  /// The code that was highlighted.
  String code;

  /// The second best language of an auto-detection.
  Highlighted? secondBest;

  /// The token tree, for embedding in another language's result.
  final Emitter? emitter;

  /// The mode where highlighting ended (for continuations).
  final Frame? top;
}

/// A mode as entered while highlighting, with the frame it was entered
/// from (`Object.create(mode, {parent})` upstream).
final class Frame {
  /// The frame of [mode], entered from [parent].
  new(this.mode, this.parent);

  /// The mode.
  final Mode mode;

  /// The frame this mode was entered from, or `null` at the top level.
  final Frame? parent;
}

final class _NoMatch {
  const new();
}

const _noMatch = _NoMatch();

final class _IllegalLexeme implements Exception {
  new(this.message);
  final String message;
}

/// Highlights code with registered languages.
final class Engine {
  /// An engine writing CSS classes with [classPrefix].
  new({this.classPrefix = 'hljs-'});

  /// The prefix of the CSS classes in the output.
  final String classPrefix;

  final Map<String, Language Function()> _definitions = {};
  final Map<String, Language> _languages = {};
  final Map<String, String> _aliases = {};
  final List<String> _order = [];

  static final Language _plaintext = Language(
    name: 'Plain text',
    disableAutodetect: true,
  )..contains = [];

  /// Registers [definition] as [name], with [aliases]; the definition is
  /// built on first use.
  void registerLanguage(
    String name,
    Language Function() definition, {
    List<String> aliases = const [],
  }) {
    if (!_definitions.containsKey(name)) _order.add(name);
    _definitions[name] = definition;
    _languages.remove(name);
    registerAliases(aliases, languageName: name);
  }

  Language _build(String name) {
    final cached = _languages[name];
    if (cached != null) return cached;
    Language lang;
    try {
      lang = _definitions[name]!();
    } on Object catch (error) {
      logger.error("Language definition for '$name' could not be registered.");
      logger.error('$error');
      lang = _plaintext;
    }
    if (lang.name.isEmpty) lang.name = name;
    return _languages[name] = lang;
  }

  /// The registered language names, in registration order.
  List<String> get languageNames => List.unmodifiable(_order);

  /// The language registered as [name] or with [name] as an alias.
  Language? getLanguage(String? name) {
    final key = jsLowerCase(name ?? '');
    if (_definitions.containsKey(key)) return _build(key);
    final alias = _aliases[key];
    return alias == null || !_definitions.containsKey(alias)
        ? null
        : _build(alias);
  }

  /// Registers [aliases] for the language [languageName].
  void registerAliases(
    Iterable<String> aliases, {
    required String languageName,
  }) {
    for (final alias in aliases) {
      _aliases[jsLowerCase(alias)] = languageName;
    }
  }

  bool _autoDetection(String name) {
    final lang = getLanguage(name);
    return lang != null && !lang.disableAutodetect;
  }

  /// Highlights [code] as [languageName].
  Highlighted highlight(
    String code, {
    required String languageName,
    bool ignoreIllegals = true,
  }) {
    return _highlight(languageName, code, ignoreIllegals, null)..code = code;
  }

  /// Highlights [code] with the language that fits it best, among
  /// [languageSubset] (default: every registered language).
  Highlighted highlightAuto(String code, [List<String>? languageSubset]) {
    final subset = languageSubset ?? _order;
    final plaintext = _justTextHighlightResult(code);
    final results = <Highlighted>[
      plaintext,
      for (final name in subset)
        if (getLanguage(name) != null && _autoDetection(name))
          _highlight(name, code, false, null),
    ];
    final sorted = stableSort(results, (a, b) {
      if (a.relevance != b.relevance) {
        return b.relevance.compareTo(a.relevance);
      }
      final aLang = a.language;
      final bLang = b.language;
      if (aLang != null && bLang != null) {
        if (getLanguage(aLang)!.supersetOf == bLang) return 1;
        if (getLanguage(bLang)!.supersetOf == aLang) return -1;
      }
      return 0;
    });
    return sorted[0]..secondBest = sorted.length > 1 ? sorted[1] : null;
  }

  Highlighted _justTextHighlightResult(String code) {
    final emitter = Emitter(classPrefix)..addText(code);
    return Highlighted(
      language: null,
      value: escapeHtml(code),
      relevance: 0,
      illegal: false,
      code: code,
      emitter: emitter,
      top: Frame(_plaintext, null),
    );
  }

  Highlighted _highlight(
    String languageName,
    String codeToHighlight,
    bool ignoreIllegals,
    Frame? continuation,
  ) {
    final keywordHits = <String, int>{};
    final language = getLanguage(languageName);
    if (language == null) {
      logger.error(
        "Could not find the language '$languageName', did you forget to "
        'load/include a language module?',
      );
      throw ArgumentError('Unknown language: "$languageName"');
    }
    final emitter = Emitter(classPrefix);
    late Frame top;
    var modeBuffer = '';
    num relevance = 0;
    var index = 0;
    var iterations = 0;
    var resumeScanAtSamePosition = false;
    final continuations = <String, Frame>{};
    ModeMatch? lastMatch;

    void emitKeyword(String keyword, String scope) {
      if (keyword.isEmpty) return;
      emitter
        ..openNode(scope)
        ..addText(keyword)
        ..closeNode();
    }

    String alias(String scope) => language.classNameAliases[scope] ?? scope;

    void processKeywords() {
      final keywords = top.mode.keywords;
      if (keywords is! CompiledKeywords) {
        emitter.addText(modeBuffer);
        return;
      }
      var lastIndex = 0;
      final buf = StringBuffer();
      for (final match in top.mode.keywordPatternRe!.allMatches(modeBuffer)) {
        buf.write(modeBuffer.substring(lastIndex, match.start));
        final text = match[0]!;
        final word = language.caseInsensitive ? jsLowerCase(text) : text;
        final data = keywords.byWord[word];
        if (data != null) {
          emitter.addText(buf.toString());
          buf.clear();
          final hits = (keywordHits[word] ?? 0) + 1;
          keywordHits[word] = hits;
          if (hits <= _maxKeywordHits) relevance += data.relevance;
          if (data.scope.startsWith('_')) {
            // `_` scopes count for relevance only: no highlighting.
            buf.write(text);
          } else {
            emitKeyword(text, alias(data.scope));
          }
        } else {
          buf.write(text);
        }
        lastIndex = match.end;
        // JavaScript's exec loop would stall on an empty match; the global
        // regex then advances by itself, as allMatches does.
      }
      buf.write(modeBuffer.substring(lastIndex));
      emitter.addText(buf.toString());
    }

    void processSubLanguage() {
      if (modeBuffer.isEmpty) return;
      final Highlighted result;
      switch (top.mode.subLanguage!) {
        case SubLanguageName(:final name):
          if (getLanguage(name) == null) {
            emitter.addText(modeBuffer);
            return;
          }
          result = _highlight(name, modeBuffer, true, continuations[name]);
          continuations[name] = result.top!;
        case SubLanguageList(:final names):
          result = highlightAuto(modeBuffer, names.isEmpty ? null : names);
      }
      if ((top.mode.relevance ?? 0) > 0) relevance += result.relevance;
      emitter.addSublanguage(result.emitter!, result.language);
    }

    void processBuffer() {
      if (top.mode.subLanguage != null) {
        processSubLanguage();
      } else {
        processKeywords();
      }
      modeBuffer = '';
    }

    void emitMultiClass(CompiledScope scope, ModeMatch match) {
      var i = 1;
      final max = match.length - 1;
      while (i <= max) {
        if (!scope.emit.contains(i)) {
          i++;
          continue;
        }
        final name = scope.positions[i];
        final klass = name == null ? null : alias(name);
        final text = match[i];
        if (klass != null && klass.isNotEmpty) {
          emitKeyword(text ?? '', klass);
        } else {
          modeBuffer = text ?? '';
          processKeywords();
          modeBuffer = '';
        }
        i++;
      }
    }

    Frame startNewMode(Mode mode, ModeMatch match) {
      if (mode.scope case ScopeName(:final name) when name.isNotEmpty) {
        emitter.openNode(alias(name));
      }
      final beginScope = mode.beginScope;
      if (beginScope is CompiledScope) {
        if (beginScope.wrap case final wrap? when wrap.isNotEmpty) {
          emitKeyword(modeBuffer, alias(wrap));
          modeBuffer = '';
        } else if (beginScope.multi) {
          emitMultiClass(beginScope, match);
          modeBuffer = '';
        }
      }
      return top = Frame(mode, top);
    }

    Frame? endOfMode(Frame? frame, ModeMatch match, String matchPlusRemainder) {
      if (frame == null) return null;
      final mode = frame.mode;
      var matched = regex.startsWith(mode.endRe, matchPlusRemainder);
      if (matched) {
        final onEnd = mode.onEnd;
        if (onEnd != null) {
          final resp = CallbackResponse(mode.data ??= {});
          onEnd(match, resp);
          if (resp.isMatchIgnored) matched = false;
        }
        if (matched) {
          var result = frame;
          while ((result.mode.endsParent ?? false) && result.parent != null) {
            result = result.parent!;
          }
          return result;
        }
      }
      // Even if on:end ignores the match, a parent mode may still end.
      if (mode.endsWithParent ?? false) {
        return endOfMode(frame.parent, match, matchPlusRemainder);
      }
      return null;
    }

    int doIgnore(String lexeme) {
      if (top.mode.matcher!.regexIndex == 0) {
        // No more rules can match here: move on one character.
        modeBuffer += lexeme.isEmpty ? '' : lexeme[0];
        return 1;
      }
      // More rules can match at this very spot.
      resumeScanAtSamePosition = true;
      return 0;
    }

    int doBeginMatch(ModeMatch match) {
      final lexeme = match[0]!;
      final newMode = match.rule!;
      final resp = CallbackResponse(newMode.data ??= {});
      for (final cb in [newMode.beforeBegin, newMode.onBegin]) {
        if (cb == null) continue;
        cb(match, resp);
        if (resp.isMatchIgnored) return doIgnore(lexeme);
      }
      if (newMode.skip ?? false) {
        modeBuffer += lexeme;
      } else {
        if (newMode.excludeBegin ?? false) modeBuffer += lexeme;
        processBuffer();
        if (!(newMode.returnBegin ?? false) &&
            !(newMode.excludeBegin ?? false)) {
          modeBuffer = lexeme;
        }
      }
      startNewMode(newMode, match);
      return (newMode.returnBegin ?? false) ? 0 : lexeme.length;
    }

    Object doEndMatch(ModeMatch match) {
      final lexeme = match[0]!;
      final matchPlusRemainder = codeToHighlight.substring(match.index);
      final endMode = endOfMode(top, match, matchPlusRemainder);
      if (endMode == null) return _noMatch;
      final origin = top.mode;
      final endScope = origin.endScope;
      if (endScope is CompiledScope && (endScope.wrap?.isNotEmpty ?? false)) {
        processBuffer();
        emitKeyword(lexeme, endScope.wrap!);
      } else if (endScope is CompiledScope && endScope.multi) {
        processBuffer();
        emitMultiClass(endScope, match);
      } else if (origin.skip ?? false) {
        modeBuffer += lexeme;
      } else {
        if (!((origin.returnEnd ?? false) || (origin.excludeEnd ?? false))) {
          modeBuffer += lexeme;
        }
        processBuffer();
        if (origin.excludeEnd ?? false) modeBuffer = lexeme;
      }
      do {
        if (_truthyScope(top.mode.scope)) emitter.closeNode();
        if (!(top.mode.skip ?? false) && top.mode.subLanguage == null) {
          relevance += top.mode.relevance ?? 0;
        }
        top = top.parent!;
      } while (!identical(top, endMode.parent));
      final starts = endMode.mode.starts;
      if (starts != null) startNewMode(starts, match);
      return (origin.returnEnd ?? false) ? 0 : lexeme.length;
    }

    void processContinuations() {
      final list = <String>[];
      for (
        var current = top;
        current.parent != null;
        current = current.parent!
      ) {
        if (current.mode.scope case ScopeName(:final name)
            when name.isNotEmpty) {
          list.insert(0, name);
        }
      }
      list.forEach(emitter.openNode);
    }

    int processLexeme(String textBeforeMatch, [ModeMatch? match]) {
      final lexeme = match?[0];
      modeBuffer += textBeforeMatch;
      if (match == null || lexeme == null) {
        processBuffer();
        return 0;
      }
      // A zero-width match got us stuck: let the character through.
      if (lastMatch?.type == MatchType.begin &&
          match.type == MatchType.end &&
          lastMatch?.index == match.index &&
          lexeme.isEmpty) {
        modeBuffer += codeToHighlight.substring(
          match.index,
          (match.index + 1).clamp(0, codeToHighlight.length),
        );
        return 1;
      }
      lastMatch = match;
      if (match.type == MatchType.begin) return doBeginMatch(match);
      if (match.type == MatchType.illegal && !ignoreIllegals) {
        throw _IllegalLexeme(
          'Illegal lexeme "$lexeme" for mode '
          '"${_scopeName(top.mode.scope) ?? '<unnamed>'}"',
        );
      } else if (match.type == MatchType.end) {
        final processed = doEndMatch(match);
        if (processed is int) return processed;
      }
      // An illegal match of `$` (a zero-width match at a line end).
      if (match.type == MatchType.illegal && lexeme.isEmpty) {
        if (match.index != codeToHighlight.length) modeBuffer += '\n';
        return 1;
      }
      if (iterations > 100000 && iterations > match.index * 3) {
        throw StateError(
          'potential infinite loop, way more iterations than matches',
        );
      }
      // An end match that could not complete (a callback ignored it).
      modeBuffer += lexeme;
      return lexeme.length;
    }

    final md = compileLanguage(language);
    top = continuation ?? Frame(md, null);
    processContinuations();
    try {
      top.mode.matcher!.considerAll();
      for (;;) {
        iterations++;
        if (resumeScanAtSamePosition) {
          resumeScanAtSamePosition = false;
        } else {
          top.mode.matcher!.considerAll();
        }
        top.mode.matcher!.lastIndex = index;
        final match = top.mode.matcher!.exec(codeToHighlight);
        if (match == null) break;
        final beforeMatch = codeToHighlight.substring(index, match.index);
        final processedCount = processLexeme(beforeMatch, match);
        index = match.index + processedCount;
      }
      processLexeme(
        codeToHighlight.substring(index.clamp(0, codeToHighlight.length)),
      );
      emitter.finalize();
      return Highlighted(
        language: languageName,
        value: emitter.toHtml(),
        relevance: relevance,
        illegal: false,
        code: codeToHighlight,
        emitter: emitter,
        top: top,
      );
    } on _IllegalLexeme {
      return Highlighted(
        language: languageName,
        value: escapeHtml(codeToHighlight),
        relevance: 0,
        illegal: true,
        code: codeToHighlight,
        emitter: emitter,
      );
    } on Object {
      // Safe mode: any other failure falls back to plain text.
      return Highlighted(
        language: languageName,
        value: escapeHtml(codeToHighlight),
        relevance: 0,
        illegal: false,
        code: codeToHighlight,
        emitter: emitter,
        top: top,
      );
    }
  }
}

bool _truthyScope(ScopeSpec? scope) => switch (scope) {
  null => false,
  ScopeName(:final name) => name.isNotEmpty,
  _ => true,
};

String? _scopeName(ScopeSpec? scope) => switch (scope) {
  ScopeName(:final name) when name.isNotEmpty => name,
  _ => null,
};

/// [list] sorted by [compare] without reordering equal elements (as
/// JavaScript's `Array.prototype.sort` does).
List<T> stableSort<T>(List<T> list, int Function(T a, T b) compare) {
  final indexed = [for (var i = 0; i < list.length; i++) (i, list[i])]
    ..sort((a, b) {
      final c = compare(a.$2, b.$2);
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final (_, e) in indexed) e];
}
