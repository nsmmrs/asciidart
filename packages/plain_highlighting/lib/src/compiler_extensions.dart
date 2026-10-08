/// Grammar extensions: syntactic sugar the compiler expands before it
/// compiles a mode.
///
/// Port of `src/lib/compiler_extensions.js`, `src/lib/ext/multi_class.js`
/// and `src/lib/exts/before_match.js`.
library;

import 'package:plain_highlighting/src/logger.dart' as logger;
import 'package:plain_highlighting/src/mode.dart';
import 'package:plain_highlighting/src/regex.dart' as regex;

/// A compiler extension: adjusts [mode] (with [parent], `null` for the
/// language itself) before compilation.
typedef CompilerExtension = void Function(Mode mode, Mode? parent);

/// Whether [spec] counts as true in JavaScript: an empty string does not,
/// every regular expression and list does.
bool truthy(RegexSpec? spec) => switch (spec) {
  null => false,
  RegexSource(:final source) => source.isNotEmpty,
  RegexList() => true,
};

/// The source of [spec] (`regex.source`): `null` for nothing, and for a
/// list, `undefined` as JavaScript would stringify it.
String? sourceOf(RegexSpec? spec) => switch (spec) {
  null => null,
  RegexSource(:final source) => source.isEmpty ? null : source,
  RegexList() => 'undefined',
};

/// The sources of a sequence or single expression.
List<String> sourcesOf(RegexSpec spec) => switch (spec) {
  RegexSource(:final source) => [source],
  RegexList(:final sources) => sources,
};

/// Skips a match that follows a dot, so that `beginKeywords` do not match
/// `bob.keyword.do()` (`skipIfHasPrecedingDot`).
void skipIfHasPrecedingDot(ModeMatch match, CallbackResponse response) {
  if (match.index > 0 && match.input[match.index - 1] == '.') {
    response.ignoreMatch();
  }
}

/// `className` is the former name of `scope`.
void scopeClassName(Mode mode, Mode? parent) {
  // `className !== undefined`: `null` moves (clearing the scope), an
  // undefined className stays.
  if (mode.className != null || mode.isJsNull(ModeKey.className)) {
    if (mode.isJsNull(ModeKey.className)) {
      mode.setJsNull(ModeKey.scope);
    } else {
      mode.scope = mode.className;
    }
    mode.delete(ModeKey.className);
  }
}

/// `beginKeywords`: begins the mode at one of the keywords (not after a
/// dot), and makes them its keywords.
void beginKeywords(Mode mode, Mode? parent) {
  if (parent == null) return;
  final words = mode.beginKeywords;
  if (words == null || words.isEmpty) return;

  // For languages with keywords that include non-word characters checking
  // for a word boundary is not sufficient, so instead we check for a word
  // boundary or whitespace - this does no harm in any case since our keyword
  // engine doesn't allow spaces in keywords anyways and we still check for
  // the boundary first.
  mode
    ..begin = RegexSource(
      '\\b(${words.split(' ').join('|')})(?!\\.)(?=\\b|\\s)',
    )
    ..beforeBegin = skipIfHasPrecedingDot
    ..keywords = keywordsTruthy(mode.keywords)
        ? mode.keywords
        : RawKeywords.fromString(words)
    ..delete(ModeKey.beginKeywords);

  // Prevents double relevance: the keywords themselves provide relevance,
  // the mode doesn't need to double it.
  if (mode.relevance == null && !mode.isJsNull(ModeKey.relevance)) {
    mode.relevance = 0;
  }
}

/// Whether [keywords] is truthy in JavaScript terms: anything but a missing
/// value or an empty string.
bool keywordsTruthy(Keywords? keywords) => switch (keywords) {
  null => false,
  RawKeywords(:final groups, :final pattern) =>
    !(pattern == null &&
        groups.length == 1 &&
        groups.single.scope == null &&
        groups.single.words.length == 1 &&
        groups.single.words.single.isEmpty &&
        !groups.single.fromList),
  CompiledKeywords() => true,
};

/// `illegal` may list several expressions.
void compileIllegal(Mode mode, Mode? parent) {
  final illegal = mode.illegal;
  if (illegal is! RegexList) return;
  mode.illegal = RegexSource(regex.either(illegal.sources));
}

/// `match` is a single expression for the whole mode.
void compileMatch(Mode mode, Mode? parent) {
  if (!truthy(mode.match)) return;
  if (truthy(mode.begin) || truthy(mode.end)) {
    throw StateError('begin & end are not supported with match');
  }
  mode
    ..begin = mode.match
    ..delete(ModeKey.match);
}

/// Modes count 1 toward relevance unless they say otherwise.
void compileRelevance(Mode mode, Mode? parent) {
  if (mode.relevance == null && !mode.isJsNull(ModeKey.relevance)) {
    mode.relevance = 1;
  }
}

/// `beforeMatch` qualifies the match: the whole begin must be
/// `beforeMatch` followed by `begin`.
void beforeMatch(Mode mode, Mode? parent) {
  final before = mode.beforeMatch;
  if (!truthy(before)) return;
  // starts conflicts with endsParent which we need to make sure the child
  // rule is not matched multiple times
  if (mode.starts != null) {
    throw StateError('beforeMatch cannot be used with starts');
  }

  final originalMode = inherit(mode);
  mode
    ..clearAll()
    ..keywords = originalMode.keywords
    ..begin = RegexSource(
      regex.concat([
        sourceOf(before) ?? 'null',
        regex.lookahead(sourceOf(originalMode.begin) ?? 'undefined'),
      ]),
    )
    ..starts = (Mode()
      ..relevance = 0
      ..contains = [originalMode..endsParent = true])
    ..relevance = 0;

  originalMode.delete(ModeKey.beforeMatch);
}

/// Renumbers labeled scope names to account for inner match groups, and
/// records which groups are top-level (`remapScopeNames`).
CompiledScope _remapScopeNames(ScopeSpec? scopeNames, List<String> regexes) {
  var offset = 0;
  final positions = <int, String?>{};
  final emit = <int>{};
  for (var i = 1; i <= regexes.length; i++) {
    positions[i + offset] = switch (scopeNames) {
      ScopeGroups(:final byGroup) => byGroup[i],
      _ => null,
    };
    emit.add(i + offset);
    offset += regex.countMatchGroups(regexes[i - 1]);
  }
  return CompiledScope.multi(positions, emit);
}

/// Thrown when a mode misuses `beginScope`/`endScope`.
class MultiClassError extends Error;

bool _isScopeObject(ScopeSpec? scope) =>
    scope is ScopeGroups || scope is CompiledScope;

void _beginMultiClass(Mode mode) {
  final begin = mode.begin;
  if (begin is! RegexList) return;
  if (mode.skip ?? false) _multiClassError('skip', 'Begin', 'begin');
  if (mode.excludeBegin ?? false) _multiClassError('skip', 'Begin', 'begin');
  if (mode.returnBegin ?? false) _multiClassError('skip', 'Begin', 'begin');
  if (!_isScopeObject(mode.beginScope)) {
    logger.error('beginScope must be object');
    throw MultiClassError();
  }
  mode
    ..beginScope = _remapScopeNames(mode.beginScope, begin.sources)
    ..begin = RegexSource(
      regex.rewriteBackreferences(begin.sources, joinWith: ''),
    );
}

void _endMultiClass(Mode mode) {
  final end = mode.end;
  if (end is! RegexList) return;
  if (mode.skip ?? false) _multiClassError('skip', 'End', 'end');
  if (mode.excludeEnd ?? false) _multiClassError('skip', 'End', 'end');
  if (mode.returnEnd ?? false) _multiClassError('skip', 'End', 'end');
  if (!_isScopeObject(mode.endScope)) {
    logger.error('endScope must be object');
    throw MultiClassError();
  }
  mode
    ..endScope = _remapScopeNames(mode.endScope, end.sources)
    ..end = RegexSource(regex.rewriteBackreferences(end.sources, joinWith: ''));
}

Never _multiClassError(String _, String which, String key) {
  logger.error(
    'skip, exclude$which, return$which not compatible with '
    '${key}Scope: {}',
  );
  throw MultiClassError();
}

/// Multi-class scopes: `scope: {}` beside `match`, `beginScope`/`endScope`
/// as a scope name or by group (`MultiClass`).
void multiClass(Mode mode, Mode? parent) {
  // `scope: {}` is sugar for `beginScope: {}` beside `match:`.
  if (mode.scope is ScopeGroups) {
    mode
      ..beginScope = mode.scope
      ..delete(ModeKey.scope);
  }
  if (mode.beginScope case ScopeName(:final name)) {
    mode.beginScope = CompiledScope.wrap(name);
  }
  if (mode.endScope case ScopeName(:final name)) {
    mode.endScope = CompiledScope.wrap(name);
  }
  _beginMultiClass(mode);
  _endMultiClass(mode);
}
