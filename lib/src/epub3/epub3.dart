/// The EPUB3 backend (`-b epub3`): registration with the converter
/// registry and the document setup the asciidoctor-epub3 gem does through
/// an extension group.
///
/// The backend is registered by the CLI and by `package:asciidart/io.dart`
/// (it writes files and embeds fonts), not by the web-safe library.
library;

import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/epub3/converter.dart';
import 'package:asciidart/src/extensions.dart';
import 'package:asciidart/src/section.dart';

export 'package:asciidart/src/epub3/converter.dart' show Epub3Converter;

bool _registered = false;

/// Registers the `epub3` backend (once).
void registerEpub3() {
  if (_registered) return;
  _registered = true;
  Converter.register(Epub3Converter.new, ['epub3'], provided: true);
  Extensions.register(name: 'asciidart-epub3', build: _setUp);
}

/// For a document converted to `epub3`: the attributes the gem sets before
/// parsing, and the IDs it gives the document and the preamble (chapter
/// files are named after IDs).
void _setUp(Registry registry) {
  final document = registry.document;
  if (document == null || document.backend != 'epub3') return;
  // (Blocks keep where they start in the source: `epub-page-map` finds
  // their print pages by it.)
  document
    ..sourcemap = true
    ..setAttribute('listing-caption', 'Listing')
    ..setAttribute('ebook-format', 'epub3')
    ..setAttribute('ebook-format-epub3')
    ..setAttribute('sectids');
  if (!document.hasAttr('pygments-style')) {
    document.setAttribute('pygments-style', 'bw');
  }
  if (!document.hasAttr('rouge-style')) {
    document.setAttribute('rouge-style', 'bw');
  }
  registry.treeProcessor(
    build: (processor) => processor.onProcess = (doc) {
      if (doc.id == null || doc.id!.isEmpty) {
        doc.id = Section.generateId(
          doc.firstSection?.title ?? doc.attr('docname') ?? 'document',
          doc,
        );
      }
      final preamble = doc.blocks.isEmpty ? null : doc.blocks[0];
      if (preamble != null &&
          preamble.context.asciidoc == 'preamble' &&
          (preamble.id == null || preamble.id!.isEmpty)) {
        preamble.id = Section.generateId(preamble.title ?? 'preamble', doc);
      }
      return null;
    },
  );
}

/// The EPUB file for [document], converted to `epub3`.
List<int> epubOf(Document document) {
  final converter = document.converter;
  if (converter is! Epub3Converter) {
    throw StateError('the document was not converted to epub3');
  }
  return converter.package();
}
