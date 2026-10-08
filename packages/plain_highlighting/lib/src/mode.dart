/// The model of highlight.js language definitions: modes and languages.
///
/// Upstream language definitions are plain JavaScript objects that the
/// compiler mutates in place, and whose keys matter even when their value
/// is `null` (`inherit` copies every key a mode has). [Mode] mirrors that:
/// each definition key is a typed field whose presence is tracked, and the
/// compiled state lives in further fields that copies carry along.
library;

import 'package:plain_highlighting/src/mode_compiler.dart'
    show ResumableMultiRegex;

/// A regular expression as a definition gives it. highlight.js compiles
/// only the source of a regular expression (with the language's flags), so
/// strings and regular expression literals are both a [RegexSource].
sealed class RegexSpec {
  const new();
}

/// One regular expression, by its source.
final class RegexSource extends RegexSpec {
  /// The expression with [source].
  const new(this.source);

  /// The source of the expression.
  final String source;
}

/// Several regular expressions: a sequence for `begin`, `end` and `match`
/// (each one a group that `beginScope`/`endScope` can name), alternatives
/// for `illegal`.
final class RegexList extends RegexSpec {
  /// The list of [sources].
  const new(this.sources);

  /// The sources of the expressions.
  final List<String> sources;
}

/// The keywords of a mode.
sealed class Keywords {
  const new();
}

/// Keywords as a definition gives them: words by scope (a `null` scope is
/// the default, `keyword`), and the `$pattern` that finds candidate words.
final class RawKeywords extends Keywords {
  /// Keywords with [groups] and an optional [pattern].
  const new(this.groups, {this.pattern});

  /// Keywords from a space-separated string (`'if else|0 for'`).
  new fromString(String words)
    : groups = [(scope: null, words: words.split(' '), fromList: false)],
      pattern = null;

  /// The words, in order, by scope (`null` for the default scope), and
  /// whether the definition gave them as a list (rather than a
  /// space-separated string; an empty string is falsy upstream, an empty
  /// list is not). A word may carry a relevance after `|` (`'else|0'`).
  final List<({String? scope, List<String> words, bool fromList})> groups;

  /// The source of the `$pattern` regular expression, if any.
  final String? pattern;
}

/// Keywords after compilation: scope and relevance by word.
final class CompiledKeywords extends Keywords {
  /// The compiled keywords [byWord].
  const new(this.byWord);

  /// The scope and relevance of each word.
  final Map<String, ({String scope, num relevance})> byWord;
}

/// A scope as a definition gives it (`scope`, `className`, `beginScope`,
/// `endScope`).
sealed class ScopeSpec {
  const new();
}

/// A scope name, such as `string` or `title.function`.
final class ScopeName extends ScopeSpec {
  /// The scope [name].
  const new(this.name);

  /// The name of the scope.
  final String name;
}

/// Scope names by match group (`{1: 'keyword', 3: 'title.class'}`).
final class ScopeGroups extends ScopeSpec {
  /// The scope names [byGroup].
  const new(this.byGroup);

  /// The scope names by group number.
  final Map<int, String> byGroup;
}

/// A `beginScope` or `endScope` after compilation: either one scope that
/// wraps the whole match, or scope names by (renumbered) match group.
final class CompiledScope extends ScopeSpec {
  /// A scope wrapping the whole match.
  const new wrap(String this.wrap) : positions = const {}, emit = const {};

  /// Scope names by group, where only the groups in [emit] are output.
  const new multi(this.positions, this.emit) : wrap = null;

  /// The scope wrapping the whole match (`_wrap`), if any.
  final String? wrap;

  /// Scope names by group number (a `null` name: keywords apply).
  final Map<int, String?> positions;

  /// The top-level groups (`_emit`).
  final Set<int> emit;

  /// Whether this names scopes by group (`_multi`).
  bool get multi => wrap == null;
}

/// The language(s) a mode's content is highlighted with.
sealed class SubLanguage {
  const new();
}

/// One sub-language, by name.
final class SubLanguageName extends SubLanguage {
  /// The sub-language [name].
  const new(this.name);

  /// The name of the language.
  final String name;
}

/// Auto-detection among [names] (all languages when empty).
final class SubLanguageList extends SubLanguage {
  /// Auto-detection among [names].
  const new(this.names);

  /// The candidate languages.
  final List<String> names;
}

/// An entry of a mode's `contains`.
sealed class ContainsEntry {
  const new();
}

/// The mode containing this entry itself (`'self'`).
final class SelfReference extends ContainsEntry {
  /// The `'self'` entry.
  const new();
}

/// The singleton `'self'` entry.
const SelfReference self = SelfReference();

/// A nested list of modes inside `contains`, which compilation flattens.
final class ModeGroup extends ContainsEntry {
  /// The group of [modes].
  const new(this.modes);

  /// The modes of the group.
  final List<ContainsEntry> modes;
}

/// How a match was found.
enum MatchType {
  /// A mode's `begin`.
  begin,

  /// A mode's `end` (or a parent's, for `endsWithParent`).
  end,

  /// An `illegal` expression.
  illegal,
}

/// A match of a mode's rules: the matched text and its groups, as
/// upstream's enhanced `RegExp` match after `match.splice(0, i)` (group 0
/// is the whole match of the rule that matched, then that rule's groups).
///
/// A view of the regular expression's match: the combined expression of a
/// mode can have hundreds of groups, so they are not copied.
final class ModeMatch {
  /// A view of a regular expression match, from the group of the rule that
  /// matched.
  new(
    this.input,
    this.index,
    this._match,
    this._offset, {
    this.type,
    this.rule,
    this.position = 0,
    this._length,
  });

  /// A match of groups listed in [groups] (for tests and callers outside
  /// the matcher).
  new of(this.input, this.index, List<String?> groups, {this.type, this.rule})
    : _match = null,
      _offset = 0,
      _groups = groups,
      _length = null,
      position = 0;

  /// The text that was searched.
  final String input;

  /// Where the match starts in [input].
  final int index;

  final RegExpMatch? _match;
  final int _offset;
  List<String?>? _groups;

  /// [length], when the match is of the rule alone (the alternation's
  /// groups after the rule's are null).
  final int? _length;

  /// What kind of rule matched.
  final MatchType? type;

  /// The mode whose `begin` matched, for [MatchType.begin].
  final Mode? rule;

  /// The position of the rule among the matcher's rules.
  final int position;

  /// Group [i] (0 is the whole match), or `null`.
  String? operator [](int i) {
    final groups = _groups;
    if (groups != null) return i < groups.length ? groups[i] : null;
    final match = _match!;
    final g = _offset + i;
    return g <= match.groupCount ? match.group(g) : null;
  }

  /// The number of groups, including group 0.
  int get length =>
      _groups?.length ?? _length ?? (_match!.groupCount - _offset + 1);
}

/// Lets a callback ignore the match it was called for, and keep state for
/// its mode (`resp.data`).
final class CallbackResponse {
  /// A response with the state [data].
  new(this.data);

  /// State kept for the mode, such as the text a heredoc ends with.
  final Map<String, String?> data;

  /// Whether the callback ignored the match.
  bool isMatchIgnored = false;

  /// Ignores the match: highlighting goes on as if it had not matched.
  void ignoreMatch() => isMatchIgnored = true;
}

/// A callback run when a mode begins or ends (`on:begin`, `on:end`).
typedef ModeCallback = void Function(
  ModeMatch match,
  CallbackResponse response,
);

/// The keys of a mode, whose presence [Mode] tracks.
enum ModeKey {
  /// `begin`.
  begin,

  /// `end`.
  end,

  /// `match`.
  match,

  /// `beforeMatch`.
  beforeMatch,

  /// `illegal`.
  illegal,

  /// `keywords`.
  keywords,

  /// `beginKeywords`.
  beginKeywords,

  /// `scope`.
  scope,

  /// `className`.
  className,

  /// `beginScope`.
  beginScope,

  /// `endScope`.
  endScope,

  /// `contains`.
  contains,

  /// `variants`.
  variants,

  /// `starts`.
  starts,

  /// `relevance`.
  relevance,

  /// `excludeBegin`.
  excludeBegin,

  /// `excludeEnd`.
  excludeEnd,

  /// `returnBegin`.
  returnBegin,

  /// `returnEnd`.
  returnEnd,

  /// `endsParent`.
  endsParent,

  /// `endsWithParent`.
  endsWithParent,

  /// `skip`.
  skip,

  /// `subLanguage`.
  subLanguage,

  /// `on:begin`.
  onBegin,

  /// `on:end`.
  onEnd,

  /// `label`.
  label,
}

/// A mode of a language definition: what to match, how to scope it, and
/// what it contains.
///
/// Setting a field makes its key present, even when the value is `null`;
/// [delete] removes it.
class Mode extends ContainsEntry {
  /// An empty mode; definitions set its fields.
  new();

  final Set<ModeKey> _present = {};

  /// The keys set to JavaScript's `null` rather than `undefined` (both are
  /// `null` here). The difference shows only where upstream compares with
  /// `undefined`: `className` and `relevance`.
  final Set<ModeKey> _jsNull = {};

  /// Whether the mode has [key], possibly with a `null` value.
  bool has(ModeKey key) => _present.contains(key);

  /// Whether [key] is set to JavaScript's `null` (not `undefined`).
  bool isJsNull(ModeKey key) => _jsNull.contains(key);

  /// Sets [key] to JavaScript's `null`.
  void setJsNull(ModeKey key) {
    _clear(key);
    _present.add(key);
    _jsNull.add(key);
  }

  /// Removes [key] (`delete mode[key]`).
  void delete(ModeKey key) {
    _present.remove(key);
    _jsNull.remove(key);
    _clear(key);
  }

  /// Deletes every definition key (`Object.keys(mode).forEach(delete)`):
  /// compiled state, which lives in other fields, is kept.
  void clearAll() => ModeKey.values.forEach(delete);

  /// A core mode shared by all languages (`Object.isFrozen`): it is never
  /// compiled itself, only copies of it.
  bool frozen = false;

  RegexSpec? _begin;
  RegexSpec? _end;
  RegexSpec? _match;
  RegexSpec? _beforeMatch;
  RegexSpec? _illegal;
  Keywords? _keywords;
  String? _beginKeywords;
  ScopeSpec? _scope;
  ScopeSpec? _className;
  ScopeSpec? _beginScope;
  ScopeSpec? _endScope;
  List<ContainsEntry>? _contains;
  List<Mode>? _variants;
  Mode? _starts;
  num? _relevance;
  bool? _excludeBegin;
  bool? _excludeEnd;
  bool? _returnBegin;
  bool? _returnEnd;
  bool? _endsParent;
  bool? _endsWithParent;
  bool? _skip;
  SubLanguage? _subLanguage;
  ModeCallback? _onBegin;
  ModeCallback? _onEnd;
  String? _label;

  /// The expression that begins the mode.
  RegexSpec? get begin => _begin;
  set begin(RegexSpec? value) => _put(ModeKey.begin, () => _begin = value);

  /// The expression that ends the mode.
  RegexSpec? get end => _end;
  set end(RegexSpec? value) => _put(ModeKey.end, () => _end = value);

  /// A single expression for the whole mode (sugar for [begin]).
  RegexSpec? get match => _match;
  set match(RegexSpec? value) => _put(ModeKey.match, () => _match = value);

  /// What must come right before [begin].
  RegexSpec? get beforeMatch => _beforeMatch;
  set beforeMatch(RegexSpec? value) =>
      _put(ModeKey.beforeMatch, () => _beforeMatch = value);

  /// What is illegal inside the mode.
  RegexSpec? get illegal => _illegal;
  set illegal(RegexSpec? value) =>
      _put(ModeKey.illegal, () => _illegal = value);

  /// The keywords of the mode.
  Keywords? get keywords => _keywords;
  set keywords(Keywords? value) =>
      _put(ModeKey.keywords, () => _keywords = value);

  /// Keywords that begin the mode (space-separated).
  String? get beginKeywords => _beginKeywords;
  set beginKeywords(String? value) =>
      _put(ModeKey.beginKeywords, () => _beginKeywords = value);

  /// The scope of the mode.
  ScopeSpec? get scope => _scope;
  set scope(ScopeSpec? value) => _put(ModeKey.scope, () => _scope = value);

  /// The former name of [scope].
  ScopeSpec? get className => _className;
  set className(ScopeSpec? value) =>
      _put(ModeKey.className, () => _className = value);

  /// The scope of the [begin] match.
  ScopeSpec? get beginScope => _beginScope;
  set beginScope(ScopeSpec? value) =>
      _put(ModeKey.beginScope, () => _beginScope = value);

  /// The scope of the [end] match.
  ScopeSpec? get endScope => _endScope;
  set endScope(ScopeSpec? value) =>
      _put(ModeKey.endScope, () => _endScope = value);

  /// The modes inside this one.
  List<ContainsEntry>? get contains => _contains;
  set contains(List<ContainsEntry>? value) =>
      _put(ModeKey.contains, () => _contains = value);

  /// Variants of this mode, each one replacing it with its own keys.
  List<Mode>? get variants => _variants;
  set variants(List<Mode>? value) =>
      _put(ModeKey.variants, () => _variants = value);

  /// The mode that starts when this one ends.
  Mode? get starts => _starts;
  set starts(Mode? value) => _put(ModeKey.starts, () => _starts = value);

  /// How much a match counts toward language detection.
  num? get relevance => _relevance;
  set relevance(num? value) =>
      _put(ModeKey.relevance, () => _relevance = value);

  /// Whether the [begin] match is outside the mode's scope.
  bool? get excludeBegin => _excludeBegin;
  set excludeBegin(bool? value) =>
      _put(ModeKey.excludeBegin, () => _excludeBegin = value);

  /// Whether the [end] match is outside the mode's scope.
  bool? get excludeEnd => _excludeEnd;
  set excludeEnd(bool? value) =>
      _put(ModeKey.excludeEnd, () => _excludeEnd = value);

  /// Whether the [begin] match is parsed again inside the mode.
  bool? get returnBegin => _returnBegin;
  set returnBegin(bool? value) =>
      _put(ModeKey.returnBegin, () => _returnBegin = value);

  /// Whether the [end] match is parsed again in the parent.
  bool? get returnEnd => _returnEnd;
  set returnEnd(bool? value) =>
      _put(ModeKey.returnEnd, () => _returnEnd = value);

  /// Whether ending this mode also ends its parent.
  bool? get endsParent => _endsParent;
  set endsParent(bool? value) =>
      _put(ModeKey.endsParent, () => _endsParent = value);

  /// Whether the mode ends where its parent ends.
  bool? get endsWithParent => _endsWithParent;
  set endsWithParent(bool? value) =>
      _put(ModeKey.endsWithParent, () => _endsWithParent = value);

  /// Whether the mode's content is passed to its parent unscoped.
  bool? get skip => _skip;
  set skip(bool? value) => _put(ModeKey.skip, () => _skip = value);

  /// The language(s) the mode's content is highlighted with.
  SubLanguage? get subLanguage => _subLanguage;
  set subLanguage(SubLanguage? value) =>
      _put(ModeKey.subLanguage, () => _subLanguage = value);

  /// Called when [begin] matches (`on:begin`).
  ModeCallback? get onBegin => _onBegin;
  set onBegin(ModeCallback? value) =>
      _put(ModeKey.onBegin, () => _onBegin = value);

  /// Called when [end] matches (`on:end`).
  ModeCallback? get onEnd => _onEnd;
  set onEnd(ModeCallback? value) => _put(ModeKey.onEnd, () => _onEnd = value);

  /// A name for the mode, for debugging.
  String? get label => _label;
  set label(String? value) => _put(ModeKey.label, () => _label = value);

  void _put(ModeKey key, void Function() assign) {
    assign();
    _present.add(key);
    _jsNull.remove(key);
  }

  void _clear(ModeKey key) {
    switch (key) {
      case ModeKey.begin:
        _begin = null;
      case ModeKey.end:
        _end = null;
      case ModeKey.match:
        _match = null;
      case ModeKey.beforeMatch:
        _beforeMatch = null;
      case ModeKey.illegal:
        _illegal = null;
      case ModeKey.keywords:
        _keywords = null;
      case ModeKey.beginKeywords:
        _beginKeywords = null;
      case ModeKey.scope:
        _scope = null;
      case ModeKey.className:
        _className = null;
      case ModeKey.beginScope:
        _beginScope = null;
      case ModeKey.endScope:
        _endScope = null;
      case ModeKey.contains:
        _contains = null;
      case ModeKey.variants:
        _variants = null;
      case ModeKey.starts:
        _starts = null;
      case ModeKey.relevance:
        _relevance = null;
      case ModeKey.excludeBegin:
        _excludeBegin = null;
      case ModeKey.excludeEnd:
        _excludeEnd = null;
      case ModeKey.returnBegin:
        _returnBegin = null;
      case ModeKey.returnEnd:
        _returnEnd = null;
      case ModeKey.endsParent:
        _endsParent = null;
      case ModeKey.endsWithParent:
        _endsWithParent = null;
      case ModeKey.skip:
        _skip = null;
      case ModeKey.subLanguage:
        _subLanguage = null;
      case ModeKey.onBegin:
        _onBegin = null;
      case ModeKey.onEnd:
        _onEnd = null;
      case ModeKey.label:
        _label = null;
    }
  }

  void _copyKey(ModeKey key, Mode from) {
    switch (key) {
      case ModeKey.begin:
        begin = from._begin;
      case ModeKey.end:
        end = from._end;
      case ModeKey.match:
        match = from._match;
      case ModeKey.beforeMatch:
        beforeMatch = from._beforeMatch;
      case ModeKey.illegal:
        illegal = from._illegal;
      case ModeKey.keywords:
        keywords = from._keywords;
      case ModeKey.beginKeywords:
        beginKeywords = from._beginKeywords;
      case ModeKey.scope:
        scope = from._scope;
      case ModeKey.className:
        className = from._className;
      case ModeKey.beginScope:
        beginScope = from._beginScope;
      case ModeKey.endScope:
        endScope = from._endScope;
      case ModeKey.contains:
        contains = from._contains;
      case ModeKey.variants:
        variants = from._variants;
      case ModeKey.starts:
        starts = from._starts;
      case ModeKey.relevance:
        relevance = from._relevance;
      case ModeKey.excludeBegin:
        excludeBegin = from._excludeBegin;
      case ModeKey.excludeEnd:
        excludeEnd = from._excludeEnd;
      case ModeKey.returnBegin:
        returnBegin = from._returnBegin;
      case ModeKey.returnEnd:
        returnEnd = from._returnEnd;
      case ModeKey.endsParent:
        endsParent = from._endsParent;
      case ModeKey.endsWithParent:
        endsWithParent = from._endsWithParent;
      case ModeKey.skip:
        skip = from._skip;
      case ModeKey.subLanguage:
        subLanguage = from._subLanguage;
      case ModeKey.onBegin:
        onBegin = from._onBegin;
      case ModeKey.onEnd:
        onEnd = from._onEnd;
      case ModeKey.label:
        label = from._label;
    }
  }

  // Compiled state (set by the compiler, copied by [inherit]).

  /// Whether the mode was compiled.
  bool isCompiled = false;

  /// An internal callback run before [onBegin] (`__beforeBegin`).
  ModeCallback? beforeBegin;

  /// The compiled `$pattern` of the keywords.
  RegExp? keywordPatternRe;

  /// The compiled [begin].
  RegExp? beginRe;

  /// The compiled [end].
  RegExp? endRe;

  /// The compiled [illegal].
  RegExp? illegalRe;

  /// The source of what ends the mode, the parent's end included for
  /// [endsWithParent].
  String? terminatorEnd;

  /// The matcher of everything that can begin, end or be illegal here.
  ResumableMultiRegex? matcher;

  /// The modes the [variants] expand to.
  List<Mode>? cachedVariants;

  /// State the callbacks keep for this mode (`data`).
  Map<String, String?>? data;

  /// Copies the compiled state [from] has. Upstream copies the keys an
  /// object has, and the compiler sets each of these keys only with a value
  /// (`__beforeBegin` and `isCompiled` with every compilation), so a key is
  /// present exactly when its value is set here.
  void _copyCompiled(Mode from) {
    if (from.isCompiled) {
      isCompiled = true;
      beforeBegin = from.beforeBegin;
    }
    keywordPatternRe = from.keywordPatternRe ?? keywordPatternRe;
    beginRe = from.beginRe ?? beginRe;
    endRe = from.endRe ?? endRe;
    illegalRe = from.illegalRe ?? illegalRe;
    terminatorEnd = from.terminatorEnd ?? terminatorEnd;
    matcher = from.matcher ?? matcher;
    cachedVariants = from.cachedVariants ?? cachedVariants;
    data = from.data ?? data;
  }

  /// Copies the keys of [from] (present ones only) onto this mode.
  void assignFrom(Mode from) {
    for (final key in from._present) {
      if (from._jsNull.contains(key)) {
        setJsNull(key);
      } else {
        _copyKey(key, from);
      }
    }
  }
}

/// A shallow merge of [original] and [objects] into a new mode
/// (`inherit`): every key present in [original], then those of each object
/// in turn.
Mode inherit(Mode original, [List<Mode> objects = const []]) {
  final result = Mode()
    .._copyCompiled(original)
    ..assignFrom(original);
  for (final object in objects) {
    result
      .._copyCompiled(object)
      ..assignFrom(object);
  }
  return result;
}

/// A language: the top-level mode of a definition, with its metadata.
class Language extends Mode {
  /// A language named [name].
  new({
    required this.name,
    this.aliases = const [],
    this.caseInsensitive = false,
    this.unicodeRegex = false,
    this.classNameAliases = const {},
    this.disableAutodetect = false,
    this.supersetOf,
  });

  /// The display name (`name`).
  String name;

  /// Other names the language is found by.
  final List<String> aliases;

  /// Whether keywords and expressions ignore case (`case_insensitive`).
  final bool caseInsensitive;

  /// Whether expressions use Unicode mode.
  final bool unicodeRegex;

  /// CSS classes standing in for scope names.
  Map<String, String> classNameAliases;

  /// Whether auto-detection skips this language.
  final bool disableAutodetect;

  /// The language this one extends, which wins ties in auto-detection.
  final String? supersetOf;
}
