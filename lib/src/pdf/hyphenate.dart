/// Hyphenation for the PDF backend: the hyph-utf8 patterns embedded in
/// `hyphenation.g.dart`, by language, and soft hyphens put into inline
/// markup where words may break.
library;

import 'dart:convert';

import 'package:asciidart/src/pdf/hyphenation.g.dart';
import 'package:libpdf/libpdf.dart' show PatternHyphenator, zlibDecode;

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

final Map<String, PatternHyphenator?> _hyphenators = {};

/// The tag of the patterns for [language] (`en_US`, `de`, `pt-BR`...),
/// or null when there are none.
String? patternTag(String language) {
  final tag = language.trim().toLowerCase().replaceAll('_', '-');
  for (final candidate in [
    tag,
    ?_aliases[tag],
    if (tag.contains('-')) tag.substring(0, tag.indexOf('-')),
    if (tag.contains('-')) ?_aliases[tag.substring(0, tag.indexOf('-'))],
  ]) {
    if (hyphenationPatterns.containsKey(candidate)) return candidate;
  }
  return null;
}

/// The hyphenator of [language], or null when there are no patterns for
/// it.
PatternHyphenator? hyphenatorFor(String language) {
  final tag = patternTag(language);
  if (tag == null) return null;
  return _hyphenators.putIfAbsent(tag, () {
    final (left, right, patterns, exceptions) = hyphenationPatterns[tag]!;
    String unpack(String data) =>
        data.isEmpty ? '' : utf8.decode(zlibDecode(base64Decode(data)));
    return PatternHyphenator(
      unpack(patterns),
      exceptions: unpack(exceptions),
      left: left,
      right: right,
    );
  });
}

const String _softHyphen = '­';

/// [markup] (inline markup: tags and character references) with soft
/// hyphens where [hyphenator] may break its words, but in bare links
/// (asciidoctor-pdf's `hyphenate_words_pcdata`), and with [skipCode] but
/// in code spans.
String hyphenateMarkup(
  String markup,
  PatternHyphenator hyphenator, {
  bool skipCode = false,
  bool lettersOnly = false,
}) {
  // With [lettersOnly] (Typst's rule): a word as Unicode word boundaries
  // (UAX #29) have it, letters, digits and underscores joined by an
  // apostrophe or a period between them, hyphenated only when it is all
  // letters (not `_hyperscript`, `html5` or `don’t`).
  String words(String text) => text.replaceAllMapped(
    lettersOnly ? _uaxWord : _word,
    (m) => lettersOnly && !_letters.hasMatch(m[0]!)
        ? m[0]!
        : _hyphenateWord(m[0]!, hyphenator),
  );
  if (!markup.contains('<') && !markup.contains('&')) return words(markup);
  var inLink = false;
  var inCode = 0;
  return markup.replaceAllMapped(RegExp(r'(&#?[a-z\d]+;|<[^>]+>)|([^&<]+)'), (
    m,
  ) {
    if (m[2] case final text?) {
      return inLink || inCode > 0 ? text : words(text);
    }
    final tag = m[1]!;
    if (skipCode && (tag == '<code>' || tag.startsWith('<code '))) {
      inCode++;
    } else if (skipCode && tag == '</code>' && inCode > 0) {
      inCode--;
    }
    inLink = inLink
        ? tag != '</a>'
        : tag.startsWith('<a ') && RegExp(' class="bare[" ]').hasMatch(tag);
    return tag;
  });
}

final RegExp _word = RegExp(r'[\p{L}\p{M}\p{N}\p{Pc}]+', unicode: true);

final RegExp _uaxWord = RegExp(
  r"[\p{L}\p{M}\p{N}\p{Pc}]+(?:['’.:·][\p{L}\p{M}\p{N}\p{Pc}]+)*",
  unicode: true,
);

final RegExp _letters = RegExp(r'^[\p{L}\p{M}]+$', unicode: true);

String _hyphenateWord(String word, PatternHyphenator hyphenator) {
  final points = hyphenator.hyphenate(word);
  if (points.isEmpty) return word;
  final runes = word.runes.toList();
  final out = StringBuffer();
  for (var i = 0; i < runes.length; i++) {
    if (points.contains(i)) out.write(_softHyphen);
    out.writeCharCode(runes[i]);
  }
  return out.toString();
}
