/// TEMP-SHIM: replaced by port/load merge.
///
/// Temporary signatures for the `lib/asciidoctor/load.rb` (+ `convert.rb`)
/// port (card TASK-0ypc0b, sibling branch `port/load`), derived mechanically
/// from the Ruby entry points `Asciidoctor.load`, `.load_file`, `.convert`
/// and `.convert_file`. Every function throws [UnimplementedError].
///
/// The merger deletes this file on conflict and rewires `cli/invoker.dart`
/// to the real implementation. Do not add behavior here.
library;

import 'document.dart';

/// Parses AsciiDoc [input] into a [Document]. TEMP-SHIM: always throws.
///
/// Mirrors `Asciidoctor.load(input, options = {})`.
Document load(Object? input, [Map<String, Object?> options = const {}]) {
  throw UnimplementedError('TEMP-SHIM: replaced by port/load merge');
}

/// Parses the AsciiDoc file [filename] into a [Document]. TEMP-SHIM.
///
/// Mirrors `Asciidoctor.load_file(filename, options = {})`.
Document loadFile(String filename, [Map<String, Object?> options = const {}]) {
  throw UnimplementedError('TEMP-SHIM: replaced by port/load merge');
}

/// Parses [input] and converts it. TEMP-SHIM: always throws.
///
/// Mirrors `Asciidoctor.convert(input, options = {})`: returns the [Document]
/// when the output is written to a file or stream, otherwise the converted
/// [String].
Object convert(Object? input, [Map<String, Object?> options = const {}]) {
  throw UnimplementedError('TEMP-SHIM: replaced by port/load merge');
}

/// Parses the file [filename] and converts it. TEMP-SHIM: always throws.
///
/// Mirrors `Asciidoctor.convert_file(filename, options = {})`; same return
/// contract as [convert].
Object convertFile(String filename, [Map<String, Object?> options = const {}]) {
  throw UnimplementedError('TEMP-SHIM: replaced by port/load merge');
}
