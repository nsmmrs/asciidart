/// The JavaScript callbacks of highlight.js language definitions, ported.
///
/// The generator (`tool/generate/generate.mjs`) maps each upstream callback
/// to one of these by its source text, so a new or changed callback fails
/// generation instead of being silently dropped.
library;

import 'dart:convert';

import 'package:plain_compression/plain_compression.dart';
import 'package:plain_highlighting/src/languages/mathematica_symbols.g.dart';
import 'package:plain_highlighting/src/mode.dart';

/// `SHEBANG`: a shebang only counts on the first line.
void shebangOnBegin(ModeMatch match, CallbackResponse response) {
  if (match.index != 0) response.ignoreMatch();
}

/// `END_SAME_AS_BEGIN`: remembers the delimiter the begin match captured.
void endSameAsBeginOnBegin(ModeMatch match, CallbackResponse response) {
  response.data['_beginMatch'] = match[1];
}

/// `END_SAME_AS_BEGIN`: only the remembered delimiter ends the mode.
void endSameAsBeginOnEnd(ModeMatch match, CallbackResponse response) {
  if (response.data['_beginMatch'] != match[1]) response.ignoreMatch();
}

/// PHP heredocs: the delimiter is the first or the second group.
void phpHeredocOnBegin(ModeMatch match, CallbackResponse response) {
  final first = match[1];
  response.data['_beginMatch'] = first != null && first.isNotEmpty
      ? first
      : match[2];
}

/// PHP heredocs end on the remembered delimiter (as [endSameAsBeginOnEnd]).
void phpHeredocOnEnd(ModeMatch match, CallbackResponse response) =>
    endSameAsBeginOnEnd(match, response);

/// Mathematica: only the system symbols are built-ins.
void mathematicaSystemSymbol(ModeMatch match, CallbackResponse response) {
  if (!_mathematicaSystemSymbols.contains(match[0])) response.ignoreMatch();
}

/// The system symbols of Mathematica, decoded when first needed.
final Set<String> _mathematicaSystemSymbols = utf8
    .decode(brotliDecode(base64Decode(mathematicaSystemSymbolsData)))
    .split('\n')
    .toSet();

/// G-code: a command letter must not follow another letter.
void gcodeLetterBoundary(ModeMatch match, CallbackResponse response) {
  if (match.index == 0) return;
  final before = match.input.codeUnitAt(match.index - 1);
  if (before >= 0x30 && before <= 0x39) return; // 0-9
  if (before == 0x5f) return; // _
  response.ignoreMatch();
}

final RegExp _assignmentAfter = RegExp(r'^\s*=');
final RegExp _extendsAfter = RegExp(r'^\s+extends\s+');

/// JavaScript: tells JSX tags from TypeScript generics (`<T,`, `<T = `,
/// `<T extends`), and requires a closing tag for `<tag>`.
void javascriptIsTrulyOpeningTag(ModeMatch match, CallbackResponse response) {
  final whole = match[0]!;
  final afterMatchIndex = whole.length + match.index;
  final input = match.input;
  final nextChar = afterMatchIndex < input.length
      ? input[afterMatchIndex]
      : null;
  if (nextChar == '<' || nextChar == ',') {
    response.ignoreMatch();
    return;
  }
  if (nextChar == '>') {
    final tag = '</${whole.substring(1)}';
    if (!input.contains(tag, afterMatchIndex)) response.ignoreMatch();
  }
  final afterMatch = input.substring(afterMatchIndex);
  if (_assignmentAfter.hasMatch(afterMatch)) {
    response.ignoreMatch();
    return;
  }
  if (_extendsAfter.firstMatch(afterMatch) case final m? when m.start == 0) {
    response.ignoreMatch();
    return;
  }
}
