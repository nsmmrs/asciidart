/// The folders of the fonts vendored with asciidoctor-pdf, prawn-icon,
/// Noto Sans Math and asciidoctor-epub3, relative to the package (without
/// `dart:io`, so tests on Node.js can name them too).
library;

/// The folders of the vendored fonts.
const List<String> vendoredFontDirectories = [
  'vendor/asciidoctor-pdf/data/fonts',
  'vendor/asciidoctor-pdf/icons',
  'data/pdf-fonts',
  'vendor/asciidoctor-epub3/fonts',
];
