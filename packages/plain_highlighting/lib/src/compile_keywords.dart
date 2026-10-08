/// Port of `src/lib/compile_keywords.js`.
library;

import 'package:plain_highlighting/src/js_string.dart';
import 'package:plain_highlighting/src/mode.dart';

// Keywords that should have no default relevance value.
const List<String> _commonKeywords = [
  'of',
  'and',
  'for',
  'in',
  'not',
  'or',
  'if',
  'then',
  'parent', // common variable name
  'list', // common variable name
  'value', // common variable name
];

const String _defaultKeywordScope = 'keyword';

/// Compiles the [raw] keywords of a definition: scope and relevance by word,
/// lower-cased when the language is [caseInsensitive].
CompiledKeywords compileKeywords(
  RawKeywords raw, {
  required bool caseInsensitive,
}) {
  final compiled = <String, ({String scope, num relevance})>{};
  for (final group in raw.groups) {
    final scope = group.scope ?? _defaultKeywordScope;
    var words = group.words;
    if (caseInsensitive) words = [for (final word in words) jsLowerCase(word)];
    for (final keyword in words) {
      final pair = keyword.split('|');
      compiled[pair[0]] = (
        scope: scope,
        relevance: _scoreForKeyword(pair[0], pair.length > 1 ? pair[1] : null),
      );
    }
  }
  return CompiledKeywords(compiled);
}

/// The relevance of [keyword]: [providedScore] when given (it always wins),
/// else 0 for common words and 1 for the rest.
num _scoreForKeyword(String keyword, String? providedScore) {
  if (providedScore != null && providedScore.isNotEmpty) {
    return jsNumber(providedScore);
  }
  return _commonKeywords.contains(jsLowerCase(keyword)) ? 0 : 1;
}
