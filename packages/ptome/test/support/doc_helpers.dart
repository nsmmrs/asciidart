/// Typed ports of the Ruby test-suite helpers that build and convert
/// documents (`empty_document`, `document_from_string`, `convert_string`,
/// `convert_string_to_embedded`).
library;

import 'package:ptome/src/internal.dart';

/// Creates an empty, unparsed document (port of `empty_document`).
Document emptyDocument([
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) => Document.lines(<String>[], options);

/// Creates a document from [src] (port of `document_from_string`).
///
/// Like the Ruby helper, the document is standalone unless [options] say
/// otherwise, a standalone document links its stylesheet (`linkcss`), and
/// the document is parsed. A `TEMPLATE_DIR` environment define adds a
/// template directory.
Document documentFromString(
  String src, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) {
  var opts = options;
  final standalone = opts.standalone ?? true;
  opts = opts.copyWith(standalone: standalone);
  if (standalone) {
    opts = opts.copyWith(
      attributes: <String, String?>{...opts.attributes, 'linkcss': ''},
    );
  }
  const templateDir = String.fromEnvironment('TEMPLATE_DIR');
  if (templateDir.isNotEmpty && opts.templateDirs.isEmpty) {
    opts = opts.copyWith(templateDirs: const <String>[templateDir]);
  }
  return Document(src, opts).parse();
}

/// Converts [src] to a standalone document (port of `convert_string`).
String convertString(
  String src, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) => documentFromString(src, options).convert();

/// Converts [src] to an embedded document (port of
/// `convert_string_to_embedded`).
String convertStringToEmbedded(
  String src, [
  AsciidoctorOptions options = const AsciidoctorOptions(),
]) => documentFromString(src, options.copyWith(standalone: false)).convert();

/// Parses a space-separated attribute string such as
/// `'linkcss copycss! toc=left'` into attribute overrides.
///
/// Unescaped whitespace separates entries and escaped whitespace is kept,
/// as on the command line; each entry is `name` or `name=value`.
Map<String, String> attributeString(String attrs) => {
  for (final entry
      in attrs
          .replaceAllMapped(spaceDelimiterRx, (m) => '${m[1]}\u0000')
          .replaceAllMapped(escapedSpaceRx, (m) => m[1]!)
          .split('\u0000'))
    if (entry.isNotEmpty)
      entry.split('=').first: entry.contains('=')
          ? entry.substring(entry.indexOf('=') + 1)
          : '',
};
