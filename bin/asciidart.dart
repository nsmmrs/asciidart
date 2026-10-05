// Command-line entry point for the Dart port of Asciidoctor.
//
// Thin shim over the reusable library entrypoint (`runCli` in
// `package:asciidart/cli.dart`), so custom binaries (ADR-0002 T6) can
// register their own transforms and then run this same CLI. The native
// executable also has the EPUB3 (`-b epub3`) and PDF (`-b pdf`) backends,
// which the npm package leaves out (they embed fonts).
import 'package:asciidart/cli.dart';
import 'package:asciidart/src/epub3/epub3.dart';
import 'package:asciidart/src/pdf/pdf.dart';

Future<void> main(List<String> args) async {
  registerEpub3();
  registerPdf();
  await runCli(args);
}
