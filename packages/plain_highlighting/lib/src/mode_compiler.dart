/// Compiles a language: every mode gets its regular expressions and a
/// matcher for the rules that can start, end or interrupt it.
///
/// Port of `src/lib/mode_compiler.js`.
library;

import 'dart:typed_data';

import 'package:plain_highlighting/src/compile_keywords.dart';
import 'package:plain_highlighting/src/compiler_extensions.dart' as ext;
import 'package:plain_highlighting/src/first_chars.dart';
import 'package:plain_highlighting/src/mode.dart';
import 'package:plain_highlighting/src/regex.dart' as regex;

/// What a rule of a [MultiRegex] stands for.
final class _RuleOptions {
  new({required this.type, this.rule});

  final MatchType type;
  final Mode? rule;
  int position = 0;
}

/// Several regular expressions searched at once, as one alternation; a
/// match tells which of them matched.
///
/// With [prefilter], when the first characters of every rule can be read
/// from its source ([firstChars]), a search goes through the text itself
/// and tries, at each position, only the rules that can start with the
/// character there (and start there, for a rule that starts a word), each
/// compiled alone, in order: the alternation's match, since its first
/// alternative that matches at the leftmost position wins. (Dart's engine
/// runs a long alternation slowly at every position.)
final class MultiRegex {
  /// A matcher compiling its regular expressions with [_compile]; with
  /// [prefilter] (the language's [ignoreCase]), trying them only where
  /// they can start.
  new(this._compile, {this.prefilter = false, this.ignoreCase = false});

  final RegExp Function(String source, {bool global}) _compile;

  /// Whether searches try each rule only where it can start.
  final bool prefilter;

  /// Whether the rules ignore case.
  final bool ignoreCase;

  final Map<int, _RuleOptions> _matchIndexes = {};
  final List<(_RuleOptions, String)> _regexes = [];

  /// The alternation's group of each rule, in order.
  final List<int> _groups = [];
  int _matchAt = 1;
  int _position = 0;
  RegExp? _matcherRe;

  /// The rules that can start with each ASCII character, in order (by
  /// index into [_regexes]); then those that can start with any other
  /// ([_beyondAscii]) and those that can match at the end ([_atEnd]).
  List<List<int>>? _byChar;

  /// Whether each rule only matches at the start of a word.
  late final List<bool> _wordStart = List.filled(_regexes.length, false);

  /// The class of the run each rule's matches start with, if one (see
  /// [FirstChars.run]), and where the rule last didn't match in a run:
  /// the text, the position and the run's end, between which it doesn't
  /// match either.
  late final List<Uint8List?> _run = List.filled(_regexes.length, null);
  late final List<String?> _missIn = List.filled(_regexes.length, null);
  late final List<int> _missAt = List.filled(_regexes.length, 0);
  late final List<int> _missTo = List.filled(_regexes.length, 0);

  /// What must follow the run each rule's matches take whole, if one (see
  /// [FirstChars.follow]).
  late final List<RunFollow?> _follow = List.filled(_regexes.length, null);

  /// Each rule alone (compiled when first tried).
  late final List<RegExp?> _alone = List.filled(_regexes.length, null);

  /// Where the next search starts.
  int lastIndex = 0;

  static const int _beyondAscii = 128;
  static const int _atEnd = 129;

  /// Adds [re], matching a rule described by [opts].
  void _addRule(String re, _RuleOptions opts) {
    opts.position = _position++;
    _matchIndexes[_matchAt] = opts;
    _regexes.add((opts, re));
    _groups.add(_matchAt);
    _matchAt += regex.countMatchGroups(re) + 1;
  }

  void _build() {
    if (_regexes.isEmpty) return;
    final terminators = [for (final (_, re) in _regexes) re];
    _matcherRe = _compile(
      regex.rewriteBackreferences(terminators, joinWith: '|'),
      global: true,
    );
    if (prefilter) _byChar = _dispatchTable();
    lastIndex = 0;
  }

  /// The rules by the character they can start with (see [_byChar]), or
  /// null when one's first characters can't be read.
  List<List<int>>? _dispatchTable() {
    final table = List.generate(130, (_) => <int>[]);
    for (final (i, (_, source)) in _regexes.indexed) {
      final first = firstChars(source, ignoreCase: ignoreCase);
      if (first == null) return null;
      for (var c = 0; c < 128; c++) {
        if (first.has(c)) table[c].add(i);
      }
      if (first.nonAscii) table[_beyondAscii].add(i);
      if (first.atEnd) table[_atEnd].add(i);
      _wordStart[i] = first.wordStart;
      _run[i] = first.run;
      _follow[i] = first.follow;
    }
    return table;
  }

  /// The first match in [s] at or after [lastIndex], or `null`.
  ModeMatch? exec(String s) {
    final re = _matcherRe;
    if (re == null || lastIndex > s.length) return null;
    if (_byChar case final byChar?) return _dispatch(byChar, s);
    final match = re.allMatches(s, lastIndex).firstOrNull;
    if (match == null) return null;
    var i = 1;
    while (i <= match.groupCount && match.group(i) == null) {
      i++;
    }
    final data = _matchIndexes[i]!;
    return ModeMatch(
      s,
      match.start,
      match,
      i,
      type: data.type,
      rule: data.rule,
      position: data.position,
    );
  }

  /// [exec] trying each rule alone where it can start.
  ModeMatch? _dispatch(List<List<int>> byChar, String s) {
    final length = s.length;
    for (var at = lastIndex; at <= length; at++) {
      final List<int> rules;
      if (at == length) {
        rules = byChar[_atEnd];
      } else {
        final c = s.codeUnitAt(at);
        rules = byChar[c < 128 ? c : _beyondAscii];
      }
      if (rules.isEmpty) continue;
      final afterWord = at > 0 && isWordChar(s.codeUnitAt(at - 1));
      for (final i in rules) {
        if (afterWord && _wordStart[i]) continue;
        if (at < _missTo[i] && at > _missAt[i] && identical(s, _missIn[i])) {
          continue;
        }
        if (_follow[i] case final follow? when !follow.admits(s, at)) {
          if (_run[i] case final run?) _missed(i, run, s, at);
          continue;
        }
        final alone = _alone[i] ??= _compile(_regexes[i].$2);
        if (alone.matchAsPrefix(s, at) case final RegExpMatch match) {
          final data = _regexes[i].$1;
          return ModeMatch(
            s,
            at,
            match,
            0,
            type: data.type,
            rule: data.rule,
            position: data.position,
            // (As many groups as the alternation's from the rule's on.)
            length: _matchAt - _groups[i],
          );
        }
        if (_run[i] case final run?) _missed(i, run, s, at);
      }
    }
    return null;
  }

  /// Rule [i], whose matches start with a run of [run]'s characters,
  /// didn't match in [s] at [at]: nor does it further into the run.
  void _missed(int i, Uint8List run, String s, int at) {
    var c = s.codeUnitAt(at);
    if (c >= 128 || run[c] == 0) return;
    var end = at + 1;
    while (end < s.length && (c = s.codeUnitAt(end)) < 128 && run[c] != 0) {
      end++;
    }
    _missIn[i] = s;
    _missAt[i] = at;
    _missTo[i] = end;
  }
}

/// A [MultiRegex] that can resume a search at the same position, skipping
/// the rules already tried there (so a callback can ignore a match and let
/// a later rule match instead).
final class ResumableMultiRegex {
  /// A matcher compiling its regular expressions with [_compile] (see
  /// [MultiRegex] for [prefilter] and [ignoreCase]).
  new(this._compile, {this.prefilter = false, this.ignoreCase = false});

  final RegExp Function(String source, {bool global}) _compile;

  /// Whether searches try each rule only where it can start.
  final bool prefilter;

  /// Whether the rules ignore case.
  final bool ignoreCase;
  final List<(String, _RuleOptions)> _rules = [];
  final Map<int, MultiRegex> _multiRegexes = {};
  int _count = 0;

  /// Where the next search starts.
  int lastIndex = 0;

  /// The first rule the next search considers.
  int regexIndex = 0;

  MultiRegex _getMatcher(int index) {
    final cached = _multiRegexes[index];
    if (cached != null) return cached;
    final matcher = MultiRegex(
      _compile,
      prefilter: prefilter,
      ignoreCase: ignoreCase,
    );
    for (final (re, opts) in _rules.skip(index)) {
      matcher._addRule(re, opts);
    }
    matcher._build();
    return _multiRegexes[index] = matcher;
  }

  bool get _resumingScanAtSamePosition => regexIndex != 0;

  /// Considers every rule again on the next search.
  void considerAll() => regexIndex = 0;

  void _addRule(String re, _RuleOptions opts) {
    _rules.add((re, opts));
    if (opts.type == MatchType.begin) _count++;
  }

  /// The next match in [s].
  ModeMatch? exec(String s) {
    final m = _getMatcher(regexIndex)..lastIndex = lastIndex;
    var result = m.exec(s);
    // The following is because we have no easy way to say "resume scanning
    // at the existing position but also skip the current rule ONLY". What
    // happens is all prior rules are also skipped which can result in
    // matching the wrong thing.
    if (_resumingScanAtSamePosition) {
      if (result != null && result.index == lastIndex) {
        // Only the rules after the skipped one can match here.
      } else {
        final m2 = _getMatcher(0)..lastIndex = lastIndex + 1;
        result = m2.exec(s);
      }
    }
    if (result != null) {
      regexIndex += result.position + 1;
      if (regexIndex == _count) considerAll();
    }
    return result;
  }
}

/// Compiles [language] in place (once) and returns it.
Mode compileLanguage(Language language) {
  RegExp langRe(String source, {bool global = false}) => RegExp(
    source,
    multiLine: true,
    caseSensitive: !language.caseInsensitive,
    unicode: language.unicodeRegex,
  );

  ResumableMultiRegex buildModeRegex(Mode mode) {
    final mm = ResumableMultiRegex(
      langRe,
      // (On the VM, whose engine runs alternations slowly; not in Unicode
      // mode, which the first characters aren't read for.)
      prefilter: !_onJavaScript && !language.unicodeRegex,
      ignoreCase: language.caseInsensitive,
    );
    for (final term in mode.contains!.cast<Mode>()) {
      mm._addRule(
        ext.sourceOf(term.begin) ?? '',
        _RuleOptions(type: MatchType.begin, rule: term),
      );
    }
    final terminatorEnd = mode.terminatorEnd;
    if (terminatorEnd != null && terminatorEnd.isNotEmpty) {
      mm._addRule(terminatorEnd, _RuleOptions(type: MatchType.end));
    }
    if (ext.truthy(mode.illegal)) {
      mm._addRule(
        ext.sourceOf(mode.illegal)!,
        _RuleOptions(type: MatchType.illegal),
      );
    }
    return mm;
  }

  Mode compileMode(Mode mode, Mode? parent) {
    if (mode.isCompiled) return mode;

    for (final extension in <ext.CompilerExtension>[
      ext.scopeClassName,
      ext.compileMatch,
      ext.multiClass,
      ext.beforeMatch,
    ]) {
      extension(mode, parent);
    }
    mode.beforeBegin = null;
    for (final extension in <ext.CompilerExtension>[
      ext.beginKeywords,
      ext.compileIllegal,
      ext.compileRelevance,
    ]) {
      extension(mode, parent);
    }
    mode.isCompiled = true;

    String? keywordPattern;
    final keywords = mode.keywords;
    if (keywords is RawKeywords) {
      final pattern = keywords.pattern;
      if (pattern != null && pattern.isNotEmpty) keywordPattern = pattern;
    }
    keywordPattern ??= r'\w+';
    if (ext.keywordsTruthy(keywords) && keywords is RawKeywords) {
      mode.keywords = compileKeywords(
        keywords,
        caseInsensitive: language.caseInsensitive,
      );
    }
    mode.keywordPatternRe = langRe(keywordPattern, global: true);

    if (parent != null) {
      if (!ext.truthy(mode.begin)) mode.begin = const RegexSource(r'\B|\b');
      mode.beginRe = langRe(ext.sourceOf(mode.begin)!);
      if (!ext.truthy(mode.end) && !(mode.endsWithParent ?? false)) {
        mode.end = const RegexSource(r'\B|\b');
      }
      if (ext.truthy(mode.end)) mode.endRe = langRe(ext.sourceOf(mode.end)!);
      var terminatorEnd = ext.sourceOf(mode.end) ?? '';
      final parentEnd = parent.terminatorEnd;
      if ((mode.endsWithParent ?? false) &&
          parentEnd != null &&
          parentEnd.isNotEmpty) {
        terminatorEnd += '${ext.truthy(mode.end) ? '|' : ''}$parentEnd';
      }
      mode.terminatorEnd = terminatorEnd;
    }
    if (ext.truthy(mode.illegal)) {
      mode.illegalRe = langRe(ext.sourceOf(mode.illegal)!);
    }
    mode.contains ??= [];

    mode.contains = [
      for (final c in mode.contains!)
        ...switch (c) {
          // Nested lists are flattened one level, their entries kept as is.
          ModeGroup(:final modes) => modes,
          SelfReference() => _expandOrCloneMode(mode),
          final Mode m => _expandOrCloneMode(m),
        },
    ];
    for (final c in mode.contains!) {
      if (c is Mode) compileMode(c, mode);
    }
    final starts = mode.starts;
    if (starts != null) compileMode(starts, parent);

    mode.matcher = buildModeRegex(mode);
    return mode;
  }

  if (language.contains?.any((c) => c is SelfReference) ?? false) {
    throw StateError(
      'ERR: contains `self` is not supported at the top-level of a '
      'language.  See documentation.',
    );
  }
  language.classNameAliases = {...language.classNameAliases};
  return compileMode(language, null);
}

bool _dependencyOnParent(Mode? mode) {
  if (mode == null) return false;
  return (mode.endsWithParent ?? false) || _dependencyOnParent(mode.starts);
}

/// Expands a mode's variants (cached), or clones a mode that depends on its
/// parent or is frozen (shared between places).
List<ContainsEntry> _expandOrCloneMode(Mode mode) {
  final variants = mode.variants;
  if (variants != null && mode.cachedVariants == null) {
    mode.cachedVariants = [
      for (final variant in variants)
        inherit(mode, [Mode()..variants = null, variant]),
    ];
  }
  final cached = mode.cachedVariants;
  if (cached != null) return cached;
  if (_dependencyOnParent(mode)) {
    final starts = mode.starts;
    return [
      inherit(mode, [Mode()..starts = starts == null ? null : inherit(starts)]),
    ];
  }
  if (mode.frozen) return [inherit(mode)];
  return [mode];
}

/// Whether this runs as JavaScript (or WebAssembly), on the platform's
/// regular expression engine.
const bool _onJavaScript = bool.fromEnvironment('dart.library.js_interop');
