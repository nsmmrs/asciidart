/// The hyph-utf8 patterns by language: tags, aliases, and hyphenators
/// built when a language is first used.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:plain_compression/plain_compression.dart' show brotliDecode;
import 'package:plain_hyphenation/src/liang.dart';
import 'package:plain_hyphenation/src/patterns.g.dart';

/// Language tags read as another tag of the patterns.
const Map<String, String> _aliases = {
  'en': 'en-us',
  'en-uk': 'en-gb',
  'de': 'de-1996',
  'de-de': 'de-1996',
  'de-at': 'de-1996',
  'de-ch': 'de-ch-1901',
  'el': 'el-monoton',
  'mn': 'mn-cyrl',
  'sh': 'sh-latn',
  'sr': 'sh-cyrl',
  'sr-latn': 'sh-latn',
  'zh': 'zh-latn-pinyin',
  'nb-no': 'nb',
  'nn-no': 'nn',
};

/// The tags of the languages with patterns (`af`, `de-1996`, `en-us`...).
Iterable<String> get hyphenationLanguages => hyphenationPatterns.keys;

/// The tag of the patterns for [language] (`en_US`, `de`, `pt-BR`...): the
/// tag itself, its alias, its primary language or that language's alias;
/// null when there are none.
String? patternTag(String language) {
  final tag = language.trim().toLowerCase().replaceAll('_', '-');
  final primary = tag.contains('-') ? tag.substring(0, tag.indexOf('-')) : null;
  for (final candidate in [
    tag,
    ?_aliases[tag],
    ?primary,
    if (primary != null) ?_aliases[primary],
  ]) {
    if (hyphenationPatterns.containsKey(candidate)) return candidate;
  }
  return null;
}

final Map<String, PatternHyphenator> _hyphenators = {};
final Map<String, Uint8List> _families = {};

/// The hyphenator of [language] (see [patternTag]), with the language's
/// hyphenmins, or null when there are no patterns for it. Its patterns
/// (compiled to a trie by the generator) are decoded the first time a
/// language of its family is asked for.
PatternHyphenator? hyphenatorFor(String language) {
  final tag = patternTag(language);
  if (tag == null) return null;
  return _hyphenators.putIfAbsent(tag, () {
    final (left, right, family, at, length, exceptionsAt, exceptionsLength) =
        hyphenationPatterns[tag]!;
    final bytes = _families.putIfAbsent(
      family,
      () => brotliDecode(base64Decode(patternFamilies[family]!)),
    );
    return compiledHyphenator(
      Uint8List.sublistView(bytes, at, at + length),
      exceptions: utf8.decode(
        Uint8List.sublistView(
          bytes,
          exceptionsAt,
          exceptionsAt + exceptionsLength,
        ),
      ),
      left: left,
      right: right,
    );
  });
}
