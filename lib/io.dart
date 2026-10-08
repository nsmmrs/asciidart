/// Reading and writing files with Ptome.
///
/// Adds `PtomeFiles` methods to every `Ptome`:
///
/// ```dart
/// import 'package:ptome/ptome.dart';
/// import 'package:ptome/io.dart';
///
/// Future<void> main() async {
///   const ad = Ptome(safe: SafeMode.safe);
///   await ad.convertFile('docs/index.adoc', toDir: 'build');
/// }
/// ```
library;

export 'src/api/api.dart' show FileConversion, PtomeFiles;
