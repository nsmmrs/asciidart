// Command-line entry point for the Dart port of Asciidoctor.
//
// Thin shim over the reusable library entrypoint (`runCli` in
// `package:ptome/cli.dart`), so custom binaries (ADR-0002 T6) can
// register their own transforms and then run this same CLI. The native
// executable also has the EPUB3 (`-b epub3`), PDF (`-b pdf`) and
// multi-page HTML (`-b multipage_html5`) backends, which the npm package
// leaves out (the first two embed fonts; the last writes many files).
import 'package:ptome/cli.dart';
import 'package:ptome/src/epub3/epub3.dart';
import 'package:ptome/src/multipage.dart';
import 'package:ptome/src/pdf/pdf.dart';

Future<void> main(List<String> args) async {
  registerEpub3();
  registerPdf();
  MultipageHtml5Converter.register();
  await runCli(args);
}
