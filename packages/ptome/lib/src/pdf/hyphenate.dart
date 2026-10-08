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
///
/// With [acrossTags], a word goes on across the tags of formatted text
/// (`__Tree__beard` is one word, hyphenated whole, as Typst does);
/// otherwise each text between tags is hyphenated alone, as
/// asciidoctor-pdf does.
String hyphenateMarkup(
  String markup,
  PatternHyphenator hyphenator, {
  bool skipCode = false,
  bool lettersOnly = false,
  bool acrossTags = false,
}) {
  // With [lettersOnly] (Typst's rule): a word as Unicode word boundaries
  // (UAX #29) have it, letters, digits and underscores joined by an
  // apostrophe or a period between them, hyphenated only when it is all
  // letters (not `_hyperscript`, `html5` or `don’t`).
  final wordRx = lettersOnly ? _uaxWord : _word;
  if (!markup.contains('<') && !markup.contains('&')) {
    return _hyphenateTexts([markup], wordRx, hyphenator, lettersOnly).single;
  }
  // Tags and character references, texts, and what neither takes (a lone
  // `&` or `<`, kept as it is).
  final tokens = <({String? tag, String? text, String? other})>[];
  var last = 0;
  for (final m in _tokenRx.allMatches(markup)) {
    if (m.start > last) {
      tokens.add((
        tag: null,
        text: null,
        other: markup.substring(last, m.start),
      ));
    }
    tokens.add((tag: m[1], text: m[2], other: null));
    last = m.end;
  }
  if (last < markup.length) {
    tokens.add((tag: null, text: null, other: markup.substring(last)));
  }
  final out = List<String?>.filled(tokens.length, null);
  // The texts hyphenated together (their token indices): one, or with
  // [acrossTags], those with only formatting tags between them.
  var group = <int>[];
  void flush() {
    if (group.isEmpty) return;
    final texts = _hyphenateTexts(
      [for (final i in group) tokens[i].text!],
      wordRx,
      hyphenator,
      lettersOnly,
    );
    for (final (k, i) in group.indexed) {
      out[i] = texts[k];
    }
    group = [];
  }

  var inLink = false;
  var inCode = 0;
  for (final (i, token) in tokens.indexed) {
    if (token.text case final text?) {
      if (inLink || inCode > 0) {
        flush();
        out[i] = text;
      } else {
        group.add(i);
        if (!acrossTags) flush();
      }
      continue;
    }
    if (token.other case final other?) {
      flush();
      out[i] = other;
      continue;
    }
    final tag = token.tag!;
    out[i] = tag;
    if (skipCode && (tag == '<code>' || tag.startsWith('<code '))) {
      inCode++;
    } else if (skipCode && tag == '</code>' && inCode > 0) {
      inCode--;
    }
    final wasInLink = inLink;
    inLink = inLink
        ? tag != '</a>'
        : tag.startsWith('<a ') && _bareLinkRx.hasMatch(tag);
    // A word ends at a character reference, and at any tag but those of
    // formatted text.
    if (inLink != wasInLink || !_formattingTagRx.hasMatch(tag)) flush();
  }
  flush();
  return out.join();
}

/// [texts] (adjacent pieces of text) with soft hyphens where their words
/// may break, the words read across the pieces.
List<String> _hyphenateTexts(
  List<String> texts,
  RegExp wordRx,
  PatternHyphenator hyphenator,
  bool lettersOnly,
) {
  final whole = texts.join();
  // The offsets (in [whole]) before which a soft hyphen goes.
  final points = <int>[];
  for (final m in wordRx.allMatches(whole)) {
    final word = m[0]!;
    if (lettersOnly && !_letters.hasMatch(word)) continue;
    final breaks = hyphenator.hyphenate(word);
    if (breaks.isEmpty) continue;
    var offset = m.start;
    var rune = 0;
    for (final code in word.runes) {
      if (breaks.contains(rune)) points.add(offset);
      offset += code > 0xffff ? 2 : 1;
      rune++;
    }
  }
  if (points.isEmpty) return texts;
  // A point at the end of a piece stays in it (before the tag that
  // follows).
  final result = <String>[];
  var start = 0;
  var next = 0;
  for (final text in texts) {
    final end = start + text.length;
    final piece = StringBuffer();
    var from = start;
    while (next < points.length && points[next] <= end) {
      final point = points[next++];
      if (point <= start) continue;
      piece
        ..write(whole.substring(from, point))
        ..write(_softHyphen);
      from = point;
    }
    piece.write(whole.substring(from, end));
    result.add(piece.toString());
    start = end;
  }
  return result;
}

final RegExp _tokenRx = RegExp(r'(&#?[a-z\d]+;|<[^>]+>)|([^&<]+)');

final RegExp _bareLinkRx = RegExp(' class="bare[" ]');

/// The tags of formatted text, across which a word goes on.
final RegExp _formattingTagRx = RegExp(
  r'^</?(?:em|strong|b|i|u|s|del|ins|mark|span|font|sup|sub|a)(?:[\s>]|$)',
);

final RegExp _word = RegExp(r'[\p{L}\p{M}\p{N}\p{Pc}]+', unicode: true);

final RegExp _uaxWord = RegExp(
  r"[\p{L}\p{M}\p{N}\p{Pc}]+(?:['’.:·][\p{L}\p{M}\p{N}\p{Pc}]+)*",
  unicode: true,
);

final RegExp _letters = RegExp(r'^[\p{L}\p{M}]+$', unicode: true);
