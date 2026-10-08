// Compiled to JavaScript in CI and run with Node.js on a folder of fonts:
// the index reads it through Node's file system, the WOFF and WOFF2
// decoder loaded on demand, and prints the families it finds.
import 'dart:js_interop';

import 'package:plain_fonts/plain_fonts.dart';

@JS('process.argv')
external JSArray<JSString> get _argv;

Future<void> main() async {
  // (dart2js passes no arguments to main: they are Node's.)
  final folder = _argv.toDart.last.toDart;
  final before = FontIndex([folder])..fonts;
  await FontIndex.loadWebFontDecoder();
  final index = FontIndex([folder]);
  final families = {
    for (final font in index.fonts) '${font.fileName}: ${font.family}',
  }.toList()..sort();
  // The families are the program's output.
  // ignore: avoid_print
  print(
    [
      'passed over web fonts before loading: ${before.passedOverWebFonts}',
      ...families,
    ].join('\n'),
  );
}
