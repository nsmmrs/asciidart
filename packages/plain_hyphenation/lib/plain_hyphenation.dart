/// plain_hyphenation: hyphenation by Liang's algorithm (as TeX does) over
/// the hyph-utf8 patterns of 72 languages, in pure Dart.
///
/// ```dart
/// final english = hyphenatorFor('en')!;
/// english.hyphenate('hyphenation'); // [2, 6]: hy-phen-ation
/// ```
library;

export 'src/languages.dart'
    show hyphenationLanguages, hyphenatorFor, patternTag;
export 'src/liang.dart' show PatternHyphenator;
