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

/// A rule of a [MultiRegex]: its expression, what it stands for, where its
/// groups are in the alternation, and what the dispatcher keeps for it.
final class _Rule {
  new(
    this.source,
    this.options, {
    required this.group,
    required this.groupCount,
  });

  /// The expression's source.
  final String source;

  /// What the rule stands for (shared by the matchers of a mode, which
  /// number its position in turn, as upstream does).
  final _RuleOptions options;

  /// The alternation's group of the rule, and the number of its own.
  final int group;
  final int groupCount;

  /// The number of the alternation's groups from the rule's on (a match
  /// of the rule alone has as many, the ones after its own unmatched).
  int tail = 0;

  /// What the rule's matches can start with; null for the rule that
  /// matches the empty string anywhere (when dispatched).
  FirstChars? first;

  /// The rule alone (compiled when first tried).
  RegExp? alone;

  /// Where the rule last didn't match in a run of [FirstChars.run]'s
  /// class: the text, the position and the run's end, between which it
  /// doesn't match either.
  String? missIn;
  int missAt = 0;
  int missTo = 0;

  /// Where [FirstChars.anchor] was last searched for: the text, the
  /// position and the occurrence found there (-1 for none), which stays
  /// the next one for any position up to it.
  String? anchorIn;
  int anchorFrom = 0;
  int anchorAt = 0;

  /// Whether the anchor's literal is where a match starting at [at] in
  /// [s] has it: its next occurrence, searched for once for the positions
  /// up to it.
  bool nearAnchor(Anchor anchor, String s, int at) {
    final from = at + anchor.min;
    var next = anchorAt;
    if (!identical(s, anchorIn) ||
        from < anchorFrom ||
        (next >= 0 && next < from)) {
      next = s.indexOf(anchor.literal, from);
      anchorIn = s;
      anchorFrom = from;
      anchorAt = next;
    }
    return next >= 0 && next <= at + anchor.max;
  }

  /// The rule, whose matches start with a run of [run]'s characters,
  /// didn't match in [s] at [at]: nor does it further into the run.
  void missed(Uint8List run, String s, int at) {
    var c = s.codeUnitAt(at);
    if (c >= 128 || run[c] == 0) return;
    var end = at + 1;
    while (end < s.length && (c = s.codeUnitAt(end)) < 128 && run[c] != 0) {
      end++;
    }
    missIn = s;
    missAt = at;
    missTo = end;
  }

  /// The match of the rule at [at] in [s] that is [lexeme] alone.
  ModeMatch literalMatch(String s, int at, String lexeme) => ModeMatch.literal(
    s,
    at,
    lexeme,
    type: options.type,
    rule: options.rule,
    position: options.position,
    length: tail,
  );
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
  new(
    this._compile, {
    this.prefilter = false,
    this.ignoreCase = false,
    this.unicode = false,
  });

  final RegExp Function(String source, {bool global}) _compile;

  /// Whether searches try each rule only where it can start.
  final bool prefilter;

  /// Whether the rules ignore case.
  final bool ignoreCase;

  /// Whether the rules are in Unicode mode (where a match never starts
  /// inside a surrogate pair).
  final bool unicode;

  /// The rules, in order.
  final List<_Rule> _rules = [];
  int _matchAt = 1;
  int _position = 0;

  /// The rules as one alternation (compiled when first searched, which on
  /// the VM is only for a mode that isn't dispatched).
  late final RegExp _matcherRe = _compile(
    regex.rewriteBackreferences([
      for (final rule in _rules) rule.source,
    ], joinWith: '|'),
    global: true,
  );

  /// The rules that can start with each ASCII character, in order: for
  /// the character c, [_byChar] from `_byCharStart[c]` to
  /// `_byCharStart[c + 1]`; then those that can start with any other
  /// ([_beyondAscii]) and those that can match at the end ([_atEnd]).
  /// Null when the rules aren't dispatched.
  Int32List? _byCharStart;
  List<_Rule> _byChar = const [];

  /// Where the next search starts.
  int lastIndex = 0;

  static const int _beyondAscii = 128;
  static const int _atEnd = 129;

  /// Adds [re], matching a rule described by [opts].
  void _addRule(String re, _RuleOptions opts) {
    opts.position = _position++;
    final groupCount = _groupCountOf[re] ??= regex.countMatchGroups(re);
    _rules.add(_Rule(re, opts, group: _matchAt, groupCount: groupCount));
    _matchAt += groupCount + 1;
  }

  /// The group count of each rule source seen (the same rules make many
  /// matchers).
  static final Map<String, int> _groupCountOf = {};

  /// The [FirstChars] of each rule source seen, by its flags.
  static final Map<(String, bool, bool), FirstChars?> _firstCharsOf = {};

  void _build() {
    if (_rules.isEmpty) return;
    for (final rule in _rules) {
      rule.tail = _matchAt - rule.group;
    }
    if (prefilter) _dispatchTable();
    lastIndex = 0;
  }

  /// Fills [_byCharStart] and [_byChar], unless one rule's first
  /// characters can't be read.
  void _dispatchTable() {
    // The rules dispatched: up to one that matches the empty string
    // anywhere (with no first characters), which no rule after it can.
    final dispatched = <_Rule>[];
    for (final rule in _rules) {
      dispatched.add(rule);
      final source = rule.source;
      if (matchesEmptyEverywhere(source)) break;
      final first = _firstCharsOf.putIfAbsent((
        source,
        ignoreCase,
        unicode,
      ), () => firstChars(source, ignoreCase: ignoreCase, unicode: unicode));
      if (first == null) return;
      rule.first = first;
    }
    final starts = Int32List(131);
    final byChar = <_Rule>[];
    for (var slot = 0; slot < 130; slot++) {
      starts[slot] = byChar.length;
      for (final rule in dispatched) {
        final first = rule.first;
        if (first == null ||
            switch (slot) {
              _beyondAscii => first.nonAscii,
              _atEnd => first.atEnd,
              _ => first.has(slot),
            }) {
          byChar.add(rule);
        }
      }
    }
    starts[130] = byChar.length;
    _byCharStart = starts;
    _byChar = byChar;
  }

  /// The first match in [s] at or after [lastIndex], or `null`.
  ModeMatch? exec(String s) {
    if (_rules.isEmpty || lastIndex > s.length) return null;
    if (_byCharStart case final starts?) {
      // (Started inside a surrogate pair, the engine steps back to the
      // pair's start: left to it.)
      if (!unicode || !_inPair(s, lastIndex)) return _dispatch(starts, s);
    }
    final match = _matcherRe.allMatches(s, lastIndex).firstOrNull;
    if (match == null) return null;
    // (The first rule whose group matched: a rule's own groups come after
    // its group.)
    var k = 0;
    while (k < _rules.length - 1 && match.group(_rules[k].group) == null) {
      k++;
    }
    final rule = _rules[k];
    final options = rule.options;
    return ModeMatch(
      s,
      match.start,
      match,
      rule.group,
      type: options.type,
      rule: options.rule,
      position: options.position,
      groupCount: _matchAt - 1,
    );
  }

  /// [exec] trying each rule alone where it can start.
  ModeMatch? _dispatch(Int32List starts, String s) {
    final byChar = _byChar;
    final length = s.length;
    for (var at = lastIndex; at <= length; at++) {
      final int slot;
      if (at == length) {
        slot = _atEnd;
      } else {
        final c = s.codeUnitAt(at);
        slot = c < 128 ? c : _beyondAscii;
      }
      final end = starts[slot + 1];
      if (starts[slot] == end) continue;
      if (unicode && _inPair(s, at)) continue;
      final afterWord = at > 0 && isWordChar(s.codeUnitAt(at - 1));
      for (var k = starts[slot]; k < end; k++) {
        final rule = byChar[k];
        final first = rule.first;
        if (first == null) {
          // (The rule that matches the empty string anywhere.)
          return rule.literalMatch(s, at, '');
        }
        if (afterWord && first.wordStart) continue;
        if (!first.admitsLine(s, at) || !first.admitsPrefix(s, at)) continue;
        if (first.literal && rule.groupCount == 0) {
          return rule.literalMatch(
            s,
            at,
            s.substring(at, at + first.prefix!.length),
          );
        }
        if (at < rule.missTo && at > rule.missAt && identical(s, rule.missIn)) {
          continue;
        }
        if (first.anchor case final anchor?
            when !rule.nearAnchor(anchor, s, at)) {
          continue;
        }
        if (first.follow case final follow? when !follow.admits(s, at)) {
          if (first.run case final run?) rule.missed(run, s, at);
          continue;
        }
        if (first.stop case final stop? when !stop.admits(s, at)) continue;
        final alone = rule.alone ??= _compile(rule.source);
        if (alone.matchAsPrefix(s, at) case final RegExpMatch match) {
          final options = rule.options;
          return ModeMatch(
            s,
            at,
            match,
            0,
            type: options.type,
            rule: options.rule,
            position: options.position,
            length: rule.tail,
            groupCount: rule.groupCount,
          );
        }
        if (first.run case final run?) rule.missed(run, s, at);
      }
    }
    return null;
  }

  /// Whether [at] is inside a surrogate pair of [s] (where no match of a
  /// Unicode-mode expression starts).
  static bool _inPair(String s, int at) =>
      at > 0 &&
      at < s.length &&
      (s.codeUnitAt(at) & 0xfc00) == 0xdc00 &&
      (s.codeUnitAt(at - 1) & 0xfc00) == 0xd800;
}

/// A [MultiRegex] that can resume a search at the same position, skipping
/// the rules already tried there (so a callback can ignore a match and let
/// a later rule match instead).
final class ResumableMultiRegex {
  /// A matcher compiling its regular expressions with [_compile] (see
  /// [MultiRegex] for [prefilter], [ignoreCase] and [unicode]).
  new(
    this._compile, {
    this.prefilter = false,
    this.ignoreCase = false,
    this.unicode = false,
  });

  final RegExp Function(String source, {bool global}) _compile;

  /// Whether searches try each rule only where it can start.
  final bool prefilter;

  /// Whether the rules ignore case.
  final bool ignoreCase;

  /// Whether the rules are in Unicode mode.
  final bool unicode;
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
      unicode: unicode,
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
      // (On the VM, whose engine runs alternations slowly.)
      prefilter: !_onJavaScript,
      ignoreCase: language.caseInsensitive,
      unicode: language.unicodeRegex,
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
    mode
      ..keywordPatternRe = langRe(keywordPattern, global: true)
      ..keywordsAreWords =
          keywordPattern == r'\w+' &&
          !(language.unicodeRegex && language.caseInsensitive);

    if (parent != null) {
      if (!ext.truthy(mode.begin)) mode.begin = const RegexSource(r'\B|\b');
      mode.beginRe = langRe(ext.sourceOf(mode.begin)!);
      if (!ext.truthy(mode.end) && !(mode.endsWithParent ?? false)) {
        mode.end = const RegexSource(r'\B|\b');
      }
      if (ext.truthy(mode.end)) {
        final source = ext.sourceOf(mode.end)!;
        mode
          ..endRe = langRe(source)
          ..endMatch = source == r'\B|\b'
              ? EndMatch.anywhere
              : source.contains(_startContext)
              ? EndMatch.onRest
              : EndMatch.inPlace;
      }
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

/// What makes a match depend on the text before it.
final RegExp _startContext = RegExp(r'\^|\\[bB]|\(\?<[=!]');

/// Whether this runs as JavaScript (or WebAssembly), on the platform's
/// regular expression engine.
const bool _onJavaScript = bool.fromEnvironment('dart.library.js_interop');
