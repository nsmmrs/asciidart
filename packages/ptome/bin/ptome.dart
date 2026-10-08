// Command-line entry point for the Dart port of Asciidoctor.
//
// Thin shim over the library's command line (the `runCli` that
// `package:ptome/cli.dart` wraps for custom binaries, ADR-0002 T6). The
// native executable also has the EPUB3 (`-b epub3`), PDF (`-b pdf`) and
// multi-page HTML (`-b multipage_html5`) backends, which the npm package
// leaves out (the first two embed fonts; the last writes many files),
// registered here and on each `-j` worker.
import 'package:ptome/src/cli/run.dart';
import 'package:ptome/src/epub3/epub3.dart';
import 'package:ptome/src/multipage.dart';
import 'package:ptome/src/pdf/pdf.dart';

Future<void> main(List<String> args) => runCli(args, setup: _backends);

void _backends() {
  registerEpub3();
  registerPdf();
  MultipageHtml5Converter.register();
}
