/// Structural document model: sections.
///
/// Port of `lib/asciidoctor/section.rb` (complete).
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart' show NodeDocument;
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/rx.dart' show invalidSectionIdCharsRx;

/// First index used when generating a unique ID suffix.
///
/// Port of `Asciidoctor::Compliance.unique_id_start_index` (the sole
/// consumer is [Section.generateId]).
const int _complianceUniqueIdStartIndex = 2;

/// Methods for managing sections of AsciiDoc content in a document.
///
/// Port of `Asciidoctor::Section`.
class Section extends AbstractBlock implements NodeSection {
  /// Creates a section with [parent] and [level].
  ///
  /// The [level] defaults to one more than the parent level for a [Section]
  /// parent, else to 1.
  new([AbstractBlock? parent, int? level])
    : numbered = false,
      super(parent, 'section') {
    if (parent is Section) {
      this.level = level ?? (parent.level! + 1);
      special = parent.special;
    } else {
      this.level = level ?? 1;
      special = false;
    }
    index = 0;
  }

  /// The 0-based index order of this section within the parent block.
  @override
  int index = 0;

  /// The section name of this section (e.g. `'chapter'`, `'appendix'`).
  @override
  String? sectname;

  /// Whether this is a special section or a child of one.
  bool special = false;

  /// Whether this section is numbered.
  @override
  bool numbered;

  /// Whether this section, when numbered, takes the next chapter number.
  @override
  bool chapterNumbering = false;

  /// The name of this section (an alias of the section title).
  String? get name => title;

  /// Generates a string ID from the title of this section.
  ///
  /// Named `generateIdFromTitle` because an instance member cannot share the
  /// name of the static [generateId].
  String generateIdFromTitle() => Section.generateId(title!, document!);

  /// Whether this section has child sections.
  @override
  bool get hasSections => nextSectionIndex > 0;

  /// The section number for this section: a delimiter-separated string that
  /// uniquely describes its position in the document (e.g. `'1.1.'`).
  ///
  /// [append] is the text after the last numeral (default [delimiter]).
  ///
  /// Port of `Asciidoctor::Section#sectnum`.
  String sectnum([String delimiter = '.', String? append]) {
    final app = append ?? delimiter;
    if (level! > 1 && parent is Section) {
      final parentSectnum = (parent! as Section).sectnum(delimiter, delimiter);
      return '$parentSectnum${numeral ?? ''}$app';
    }
    return '${numeral ?? ''}$app';
  }

  /// Generates cross reference text (xreftext) that can be used to refer to
  /// this section.
  ///
  /// Port of `Asciidoctor::Section#xreftext`.
  @override
  String? xreftext([String? xrefstyle]) {
    final val = reftext;
    if (val != null && val.isNotEmpty) return val;
    if (xrefstyle == null) return title;
    final titleText = title ?? '';
    if (numbered) {
      switch (xrefstyle) {
        case 'full':
          final type = sectname;
          final quotedTitle = type == 'chapter' || type == 'appendix'
              ? subPlaceholder(subQuotes('_%s_'), titleText)
              : subPlaceholder(
                  subQuotes(document!.compatMode ? "``%s''" : '"`%s`"'),
                  titleText,
                );
          final signifier = document!.attributes['$type-refsig'];
          if (signifier != null) {
            return '$signifier ${sectnum('.', ',')} $quotedTitle';
          }
          return '${sectnum('.', ',')} $quotedTitle';
        case 'short':
          final signifier = document!.attributes['$sectname-refsig'];
          if (signifier != null) {
            return '$signifier ${sectnum('.', '')}';
          }
          return sectnum('.', '');
        default:
          final type = sectname;
          return type == 'chapter' || type == 'appendix'
              ? subPlaceholder(subQuotes('_%s_'), titleText)
              : title;
      }
    }
    final type = sectname;
    return type == 'chapter' || type == 'appendix'
        ? subPlaceholder(subQuotes('_%s_'), titleText)
        : title;
  }

  /// Appends [block] to this section's children, assigning an index (and
  /// numeral) first when the child is a section.
  ///
  /// Port of `Asciidoctor::Section#<<`.
  @override
  void append(AbstractBlock block) {
    if (block.context == 'section') assignNumeral(block as Section);
    super.append(block);
  }

  @override
  String toString() {
    final rawTitle = sourceTitle;
    if (rawTitle != null) {
      final formalTitle = numbered ? '${sectnum()} $rawTitle' : rawTitle;
      return 'Section(level: $level, title: ${debugQuote(formalTitle)}, '
          'blocks: ${blocks.length})';
    }
    return super.toString();
  }

  /// Generates a string ID from the section [title].
  ///
  /// The ID is prefixed with the `idprefix` attribute (`'_'` by default),
  /// invalid characters are removed, and spaces become the `idseparator`
  /// attribute (`'_'` by default). When the ID is already referenced in the
  /// document catalog, a count is appended until a unique ID is found.
  /// A multi-character separator is truncated to its first character (an
  /// observable side effect on the document attributes).
  ///
  /// Port of `Asciidoctor::Section.generate_id`.
  static String generateId(String title, NodeDocument document) {
    final attrs = document.attributes;
    final pre = attrs['idprefix'] ?? '_';
    late final String sep;
    String? sepSub;
    var noSep = false;
    final rawSep = attrs['idseparator'];
    if (rawSep != null) {
      var s = rawSep;
      if (s.length == 1) {
        sepSub = (s == '-' || s == '.') ? ' .-' : ' $s.-';
      } else {
        noSep = s.isEmpty;
        if (!noSep) {
          // The first character (not UTF-16 unit).
          s = String.fromCharCode(s.runes.first);
          attrs['idseparator'] = s;
          sepSub = (s == '-' || s == '.') ? ' .-' : ' $s.-';
        }
      }
      sep = s;
    } else {
      sep = '_';
      sepSub = ' _.-';
    }
    // Shared table regex: word characters include non-ASCII letters such as
    // `ü`. Dart `\w` stays ASCII-only even with `unicode: true`, so the
    // `ccWord` spelling in `rx.dart` is required here.
    var genId =
        '$pre${title.toLowerCase().replaceAll(invalidSectionIdCharsRx, '')}';
    if (noSep) {
      genId = genId.replaceAll(' ', '');
    } else {
      // Replace spaces with the separator and drop repeating and trailing
      // separator characters.
      genId = transliterateSqueeze(genId, sepSub!, sep);
      if (genId.endsWith(sep)) genId = dropLastChar(genId);
      // Ensure the ID doesn't begin with the separator when the prefix is
      // empty (assuming the separator is not empty).
      if (pre.isEmpty && genId.startsWith(sep)) {
        genId = genId.substring(1);
      }
    }
    final refs = document.catalog.refs;
    if (refs.containsKey(genId)) {
      var count = _complianceUniqueIdStartIndex;
      late String candidateId;
      do {
        candidateId = '$genId$sep$count';
        count += 1;
      } while (refs.containsKey(candidateId));
      return candidateId;
    }
    return genId;
  }
}
