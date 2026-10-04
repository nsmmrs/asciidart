/// Output writer for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/writer.rb` (`Asciidoctor::Writer` and
/// `Asciidoctor::VoidWriter`). Converters mix in [Writer] to control how the
/// converted output is written to disk.
library;

import 'dart:io' show File;

/// Mixes the [write] method into a converter implementation.
///
/// Mirrors `Asciidoctor::Writer`.
mixin Writer {
  /// Writes [output] to [target].
  ///
  /// When [target] is a [StringSink] (e.g. a [StringBuffer] or an `IOSink`
  /// such as stdout), [output] is chomped (one trailing line break removed)
  /// and written with a single trailing `\n`. When [target] is a [File] or a
  /// [String] file path, [output] is written to that file as UTF-8, without
  /// any trailing newline adjustment (the same asymmetry as Asciidoctor). Any
  /// other [target] type throws an [ArgumentError].
  ///
  /// Mirrors `Writer#write`.
  void write(String output, Object target) {
    if (target is StringSink) {
      target.write('${_chomp(output)}\n');
    } else if (target is File) {
      target.writeAsStringSync(output);
    } else if (target is String) {
      File(target).writeAsStringSync(output);
    } else {
      throw ArgumentError.value(
        target,
        'target',
        'expected a StringSink, File, or file path',
      );
    }
  }

  /// Removes one trailing line break (`\r\n`, `\r`, or `\n`) from [value].
  ///
  /// Removes one trailing line terminator.
  static String _chomp(String value) {
    var result = value;
    if (result.endsWith('\n')) {
      result = result.substring(0, result.length - 1);
      if (result.endsWith('\r')) {
        result = result.substring(0, result.length - 1);
      }
    } else if (result.endsWith('\r')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}

/// Mixes a no-op [Writer.write] into a converter implementation.
///
/// Mirrors `Asciidoctor::VoidWriter` (which includes `Writer` and overrides
/// `write` with an empty method; applying this mixin alone has the same
/// observable effect).
mixin VoidWriter {
  /// Discards [output]; [target] is untouched.
  void write(String output, Object target) {}
}
