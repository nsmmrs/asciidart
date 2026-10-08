/// Hyphenation for the PDF backend: soft hyphens put into inline markup
/// where words may break, by plain_hyphenation's hyph-utf8 patterns for
/// the document's language.
library;

import 'package:plain_hyphenation/plain_hyphenation.dart';

export 'package:plain_hyphenation/plain_hyphenation.dart'
    show PatternHyphenator, hyphenatorFor, patternTag;

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
