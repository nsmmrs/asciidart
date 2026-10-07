/// The fonts vendored with asciidoctor-pdf (its Noto and M+ subsets and
/// prawn-icon's icon fonts), Noto Sans Math and asciidoctor-epub3's fonts,
/// which the tools' and the tests' PDFs and EPUBs are set in, so that they
/// don't depend on the fonts installed on the machine. Paths are relative
/// to the repository.
library;

import 'dart:io';

import 'package:asciidart/src/font_index.dart';

/// The folders of the vendored fonts.
const List<String> vendoredFontDirectories = [
  'vendor/asciidoctor-pdf/data/fonts',
  'vendor/asciidoctor-pdf/icons',
  'data/pdf-fonts',
  'vendor/asciidoctor-epub3/fonts',
];

/// Puts the vendored fonts on this process's font path, before the
/// machine's fonts.
void useVendoredFonts() => Fonts.extraDirectories = vendoredFontDirectories;

/// [environment] for a child process (the asciidart executable) with
/// `ASCIIDART_FONT_PATH` naming the vendored fonts, unless this process's
/// environment sets it.
Map<String, String> withVendoredFonts([
  Map<String, String> environment = const {},
]) => {
  'ASCIIDART_FONT_PATH':
      Platform.environment['ASCIIDART_FONT_PATH'] ??
      [for (final dir in vendoredFontDirectories) Directory(dir).absolute.path]
          .join(Platform.isWindows ? ';' : ':'),
  ...environment,
};
