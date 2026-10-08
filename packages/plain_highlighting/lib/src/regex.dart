/// Helpers for composing regular expression sources.
///
/// Port of `src/lib/regex.js`. highlight.js compiles only the source of a
/// regular expression (with the language's own flags), so sources are plain
/// strings here. JavaScript and Dart regular expressions share the ECMAScript
/// syntax, so upstream sources run unchanged.
library;

/// The source of [re]: the string itself (`regex.source`).
String? source(String? re) => re;

/// `(?=re)`.
String lookahead(String re) => concat(['(?=', re, ')']);

/// `(?:re)*`.
String anyNumberOfTimes(String re) => concat(['(?:', re, ')*']);

/// `(?:re)?`.
String optional(String re) => concat(['(?:', re, ')?']);

/// The sources of [args], joined.
String concat(List<String> args) => args.join();

/// Any of [args]: `(?:a|b|c)`, or a capturing group when [capture] is set.
String either(List<String> args, {bool capture = false}) =>
    '(${capture ? '' : '?:'}${args.join('|')})';

/// The number of capture groups in [re] (counted as
/// [rewriteBackreferences] counts them, without compiling [re]).
int countMatchGroups(String re) {
  var count = 0;
  for (final match in _backrefRe.allMatches(re)) {
    final whole = match[0]!;
    if (whole == '(' || _namedGroupStart.hasMatch(whole)) count++;
  }
  return count;
}

/// Whether [lexeme] starts with a match of [re].
bool startsWith(RegExp? re, String lexeme) =>
    re != null && re.matchAsPrefix(lexeme) != null;

// Matches an open parenthesis or backreference. To avoid an incorrect parse,
// it also matches the constructs where the meaning of parentheses, escapes,
// or capture counting changes.
final RegExp _backrefRe = RegExp(
  either([
    // A character class, inside which ( and \ lose their meaning.
    r'\[(?:[^\\\]]|\\.)*\]',
    // A named capture group `(?<name>` (not a lookbehind `(?<=` / `(?<!`).
    r'\(\?<(?![=!])[^>]+>',
    // A named capture group `(?'name'`.
    r"\(\?'[^']+'",
    // An opening parenthesis, capturing or non-capturing / lookahead.
    r'\(\??',
    // A backreference like `\1`.
    r'\\([1-9][0-9]*)',
    // Any other escape sequence.
    r'\\.',
  ]),
);

final RegExp _namedGroupStart = RegExp(r"^\(\?[<']");

/// Joins [regexps] with [joinWith], putting each in its own capture group
/// and renumbering backreferences so that they still match
/// (`_rewriteBackreferences`).
String rewriteBackreferences(List<String> regexps, {required String joinWith}) {
  var numCaptures = 0;
  return regexps
      .map((regex) {
        numCaptures += 1;
        final offset = numCaptures;
        final out = StringBuffer();
        var from = 0;
        // (The tokens in order, as matching the rest each time finds
        // them: the pattern has no anchors and matches no empty string.)
        for (final match in _backrefRe.allMatches(regex)) {
          out.write(regex.substring(from, match.start));
          from = match.end;
          final whole = match[0]!;
          final backref = match[1];
          if (whole.startsWith(r'\') && backref != null) {
            // Adjust the backreference.
            out.write('\\${int.parse(backref) + offset}');
          } else {
            out.write(whole);
            if (whole == '(' || _namedGroupStart.hasMatch(whole)) {
              numCaptures++;
            }
          }
        }
        out.write(regex.substring(from));
        return '($out)';
      })
      .join(joinWith);
}
