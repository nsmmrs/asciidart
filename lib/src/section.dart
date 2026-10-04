/// Structural document model: sections.
///
/// Port of `lib/asciidoctor/section.rb` (complete).
library;

// `toString` ports Ruby `#inspect` (`#<ClassName@hash ...>`), pinned
// by tests; the concrete (subclass-aware) class name is load-bearing.
// ignore_for_file: no_runtimetype_tostring

import 'package:asciidoctor/src/abstract_block.dart';
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
  /// parent, else to 1. [numbered] mirrors the Ruby positional argument of
  /// the same name.
  new([
    AbstractBlock? parent,
    int? level,
    this.numbered = false,
    Map<String, Object?>? attributes,
  ]) : super(parent, 'section', attributes: attributes) {
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

  /// Whether this section is numbered (`'chapter'`-style markers aside, this
  /// is a boolean; `sectnum` must only be called when it is truthy).
  @override
  Object? numbered;

  /// The name of this section (an alias of the section title).
  String? get name => title;

  /// Generates a string ID from the title of this section.
  ///
  /// Named `generateIdFromTitle` because Dart forbids an instance member and
  /// a static member sharing the name `generateId`, as Ruby's
  /// `Section#generate_id` / `Section.generate_id` pair does.
  String generateIdFromTitle() => Section.generateId(title!, document);

  /// Whether this section has child sections.
  @override
  bool get hasSections => nextSectionIndex > 0;

  /// The section number for this section: a delimiter-separated string that
  /// uniquely describes its position in the document (e.g. `'1.1.'`).
  ///
  /// Port of `Asciidoctor::Section#sectnum`.
  String sectnum([String delimiter = '.', Object? append]) {
    final app = isTruthy(append)
        ? '$append'
        : (append == false ? '' : delimiter);
    if (level! > 1 && parent is Section) {
      // Unwrappable long literal (no valid split point).
      // ignore: lines_longer_than_80_chars
      return '${(parent! as Section).sectnum(delimiter, delimiter)}${numeral ?? ''}$app';
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
    if (!isTruthy(xrefstyle)) return title;
    if (isTruthy(numbered)) {
      switch (xrefstyle) {
        case 'full':
          final type = sectname;
          final quotedTitle = type == 'chapter' || type == 'appendix'
              ? subPlaceholder(subQuotes('_%s_'), title)
              : subPlaceholder(
                  subQuotes(document!.compatMode ? "``%s''" : '"`%s`"'),
                  title,
                );
          final signifier = document!.attributes['$type-refsig'];
          if (isTruthy(signifier)) {
            return '$signifier ${sectnum('.', ',')} $quotedTitle';
          }
          return '${sectnum('.', ',')} $quotedTitle';
        case 'short':
          final signifier = document!.attributes['$sectname-refsig'];
          if (isTruthy(signifier)) {
            return '$signifier ${sectnum('.', '')}';
          }
          return sectnum('.', '');
        default:
          final type = sectname;
          return type == 'chapter' || type == 'appendix'
              ? subPlaceholder(subQuotes('_%s_'), title)
              : title;
      }
    }
    final type = sectname;
    return type == 'chapter' || type == 'appendix'
        ? subPlaceholder(subQuotes('_%s_'), title)
        : title;
  }

  /// Appends [block] to this section's children, assigning an index (and
  /// numeral) first when the child is a section. Returns this section.
  ///
  /// Port of `Asciidoctor::Section#<<`.
  @override
  AbstractBlock operator <<(AbstractBlock block) {
    if (block.context == 'section') assignNumeral(block as Section);
    return super << block;
  }

  @override
  String toString() {
    final rawTitle = sourceTitle;
    if (rawTitle != null) {
      final formalTitle = isTruthy(numbered)
          ? '${sectnum()} $rawTitle'
          : rawTitle;
      return '#$runtimeType@${identityHashCode(this)} {level: $level, '
          'title: ${inspectString(formalTitle)}, blocks: ${blocks.length}}';
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
  /// observable side effect on the document attributes, as in Ruby).
  ///
  /// Port of `Asciidoctor::Section.generate_id`.
  static String generateId(String title, dynamic document) {
    // `document` is dynamic so tests can pass fakes; production callers pass
    // a Document. The two dynamic member accesses below are intentional.
    // ignore: avoid_dynamic_calls
    final attrs = document.attributes as Map<String, Object?>;
    final pre = isTruthy(attrs['idprefix'])
        ? attrs['idprefix']! as String
        : '_';
    late final String sep;
    String? sepSub;
    var noSep = false;
    final rawSep = attrs['idseparator'];
    if (isTruthy(rawSep)) {
      var s = rawSep! as String;
      if (s.length == 1) {
        sepSub = (s == '-' || s == '.') ? ' .-' : ' $s.-';
      } else {
        noSep = s.isEmpty;
        if (!noSep) {
          // Ruby `String#chr`: the first character (not UTF-16 unit).
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
    // Shared table regex: Ruby `CC_WORD` (`\p{Word}`) keeps non-ASCII letters
    // such as `ü` (`lib/asciidoctor/rx.rb:263`, `lib/asciidoctor/section.rb:208`);
    // Dart `\w` stays ASCII-only even with `unicode: true`, so the `ccWord`
    // spelling in `rx.dart` is required here.
    var genId =
        '$pre${title.toLowerCase().replaceAll(invalidSectionIdCharsRx, '')}';
    if (noSep) {
      genId = genId.replaceAll(' ', '');
    } else {
      // Replace spaces with the separator and drop repeating and trailing
      // separator characters.
      genId = transliterateSqueeze(genId, sepSub!, sep);
      if (genId.endsWith(sep)) genId = chopLast(genId);
      // Ensure the ID doesn't begin with the separator when the prefix is
      // empty (assuming the separator is not empty).
      if (pre.isEmpty && genId.startsWith(sep)) {
        genId = genId.substring(1);
      }
    }
    // See above: `document` may be a test fake, so this stays dynamic.
    // ignore: avoid_dynamic_calls
    final refs = document.catalog['refs'] as Map<String, Object?>;
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
