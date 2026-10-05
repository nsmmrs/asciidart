/// Reading and writing files with asciidart.
///
/// Adds `AsciidartFiles` methods to every `Asciidart`:
///
/// ```dart
/// import 'package:asciidart/asciidart.dart';
/// import 'package:asciidart/io.dart';
///
/// Future<void> main() async {
///   const ad = Asciidart(safe: SafeMode.safe);
///   await ad.convertFile('docs/index.adoc', toDir: 'build');
/// }
/// ```
library;

export 'src/api/api.dart' show AsciidartFiles, FileConversion;
