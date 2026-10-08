/// Languages as data: the mode graph of a highlight.js definition, as
/// `tool/generate/generate.mjs` writes it, read back into [Mode]s the
/// first time a language is used (rather than compiled-in code that
/// builds every language, 1.6 MB of the executable).
///
/// The grammars of all languages are one Brotli stream ([grammars], in
/// base64), decoded the first time a language is used. A grammar is:
///
/// * the strings it uses: their count, then each one's UTF-8 length and
///   bytes; further on, a string is its index in this table (an optional
///   one its index plus one, 0 for none);
/// * the language: its name, its aliases (a count and the strings), a
///   flags byte (1: case-insensitive, 2: Unicode mode, 4: no
///   auto-detection), the class name aliases (a count and pairs), the
///   language it is a superset of (optional);
/// * the modes, the language first: their count, then for each, its keys
///   in order (a count, then each key's [ModeKey] index, with 0x80 for
///   JavaScript's `null` and 0x40 for `undefined`, then its value), and
///   whether it is frozen (a byte).
///
/// Numbers are unsigned LEB128. Values: an expression is 0 and a string,
/// or 1 and a list; a scope 0 and a name, or 1 and pairs of a group and a
/// name; keywords their groups (scope, optional; the words; whether a
/// list) and pattern (optional); `contains` entries 0 and a mode, 1
/// (`self`) or 2 and a nested list; a number its text; a sub-language 0
/// and a name, or 1 and a list; a callback its index in [_callbacks].
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_highlighting/src/callbacks.dart' as callbacks;
import 'package:plain_highlighting/src/languages/all.g.dart';
import 'package:plain_highlighting/src/mode.dart';

/// The language whose grammar starts at [at] in [grammars].
Language readGrammar(int at) => _Reader(_grammars, at).language();

/// [grammars], decoded.
final Uint8List _grammars = brotliDecode(base64Decode(grammars));

/// The callbacks a grammar names, by index (the generator's order).
const List<ModeCallback> _callbacks = [
  callbacks.shebangOnBegin,
  callbacks.endSameAsBeginOnBegin,
  callbacks.endSameAsBeginOnEnd,
  callbacks.phpHeredocOnBegin,
  callbacks.phpHeredocOnEnd,
  callbacks.mathematicaSystemSymbol,
  callbacks.gcodeLetterBoundary,
  callbacks.javascriptIsTrulyOpeningTag,
];

final class _Reader {
  new(this._bytes, this._at);

  final Uint8List _bytes;
  int _at;
  late final List<String> _strings;
  late final List<Mode> _modes;

  int _byte() => _bytes[_at++];

  int _uint() {
    var value = 0;
    var shift = 0;
    while (true) {
      final b = _bytes[_at++];
      value |= (b & 0x7f) << shift;
      if (b < 0x80) return value;
      shift += 7;
    }
  }

  String _str() => _strings[_uint()];

  String? _optStr() {
    final index = _uint();
    return index == 0 ? null : _strings[index - 1];
  }

  List<T> _list<T>(T Function() item) => [
    for (var n = _uint(); n > 0; n--) item(),
  ];

  Language language() {
    _strings = _list(() {
      final length = _uint();
      final from = _at;
      _at += length;
      return utf8.decode(Uint8List.sublistView(_bytes, from, _at));
    });
    final name = _str();
    final aliases = _list(_str);
    final flags = _byte();
    final classNameAliases = {for (var n = _uint(); n > 0; n--) _str(): _str()};
    final language = Language(
      name: name,
      aliases: aliases,
      caseInsensitive: flags & 1 != 0,
      unicodeRegex: flags & 2 != 0,
      classNameAliases: classNameAliases,
      disableAutodetect: flags & 4 != 0,
      supersetOf: _optStr(),
    );
    final count = _uint();
    _modes = [language, for (var i = 1; i < count; i++) Mode()];
    _modes.forEach(_mode);
    return language;
  }

  void _mode(Mode mode) {
    for (var n = _uint(); n > 0; n--) {
      final code = _byte();
      final key = ModeKey.values[code & 0x3f];
      if (code & 0x80 != 0) {
        mode.setJsNull(key);
      } else {
        _set(mode, key, unset: code & 0x40 != 0);
      }
    }
    mode.frozen = _byte() != 0;
  }

  /// Sets [key] of [mode] to the value read (to `null` when [unset]).
  void _set(Mode mode, ModeKey key, {required bool unset}) {
    switch (key) {
      case ModeKey.begin:
        mode.begin = unset ? null : _regex();
      case ModeKey.end:
        mode.end = unset ? null : _regex();
      case ModeKey.match:
        mode.match = unset ? null : _regex();
      case ModeKey.beforeMatch:
        mode.beforeMatch = unset ? null : _regex();
      case ModeKey.illegal:
        mode.illegal = unset ? null : _regex();
      case ModeKey.keywords:
        mode.keywords = unset ? null : _keywords();
      case ModeKey.beginKeywords:
        mode.beginKeywords = unset ? null : _str();
      case ModeKey.scope:
        mode.scope = unset ? null : _scope();
      case ModeKey.className:
        mode.className = unset ? null : _scope();
      case ModeKey.beginScope:
        mode.beginScope = unset ? null : _scope();
      case ModeKey.endScope:
        mode.endScope = unset ? null : _scope();
      case ModeKey.contains:
        mode.contains = unset ? null : _contains();
      case ModeKey.variants:
        mode.variants = unset ? null : _list(() => _modes[_uint()]);
      case ModeKey.starts:
        mode.starts = unset ? null : _modes[_uint()];
      case ModeKey.relevance:
        mode.relevance = unset ? null : num.parse(_str());
      case ModeKey.excludeBegin:
        mode.excludeBegin = unset ? null : _byte() != 0;
      case ModeKey.excludeEnd:
        mode.excludeEnd = unset ? null : _byte() != 0;
      case ModeKey.returnBegin:
        mode.returnBegin = unset ? null : _byte() != 0;
      case ModeKey.returnEnd:
        mode.returnEnd = unset ? null : _byte() != 0;
      case ModeKey.endsParent:
        mode.endsParent = unset ? null : _byte() != 0;
      case ModeKey.endsWithParent:
        mode.endsWithParent = unset ? null : _byte() != 0;
      case ModeKey.skip:
        mode.skip = unset ? null : _byte() != 0;
      case ModeKey.subLanguage:
        mode.subLanguage = unset
            ? null
            : (_byte() == 0
                  ? SubLanguageName(_str())
                  : SubLanguageList(_list(_str)));
      case ModeKey.onBegin:
        mode.onBegin = unset ? null : _callbacks[_byte()];
      case ModeKey.onEnd:
        mode.onEnd = unset ? null : _callbacks[_byte()];
      case ModeKey.label:
        mode.label = unset ? null : _str();
    }
  }

  RegexSpec _regex() =>
      _byte() == 0 ? RegexSource(_str()) : RegexList(_list(_str));

  ScopeSpec _scope() => _byte() == 0
      ? ScopeName(_str())
      : ScopeGroups({for (var n = _uint(); n > 0; n--) _uint(): _str()});

  Keywords _keywords() {
    final groups = _list(
      () => (scope: _optStr(), words: _list(_str), fromList: _byte() != 0),
    );
    return RawKeywords(groups, pattern: _optStr());
  }

  List<ContainsEntry> _contains() => _list(
    () => switch (_byte()) {
      0 => _modes[_uint()],
      1 => self,
      _ => ModeGroup(_contains()),
    },
  );
}
