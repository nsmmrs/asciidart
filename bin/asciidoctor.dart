// Command-line entry point for the Dart port of Asciidoctor.
//
// Thin shim over the reusable library entrypoint (`runCli` in
// `package:asciidoctor/cli.dart`), so custom binaries (ADR-0002 T6) can
// register their own transforms and then run this same CLI.
import 'package:asciidoctor/cli.dart';

void main(List<String> args) => runCli(args);
