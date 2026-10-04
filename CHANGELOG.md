# Changelog

## 0.1.0

Initial release: Dart port of Asciidoctor.

- Converts AsciiDoc to HTML 5, DocBook 5, and Unix man pages.
- Library API: top-level `convert`, `convertFile`, `load`, `loadFile`,
  plus the full document/AST model.
- CLI (`bin/asciidoctor.dart`, also activatable as `asciidoctor` via
  `dart pub global activate`): option parser, safe modes, extension
  framework, custom converter templates (Mustache files and Dart
  functions).
- Output is byte-identical to Ruby Asciidoctor 2.1 on the differential
  corpus (`tool/differential.dart`); the bats e2e suite passes 131/131.
