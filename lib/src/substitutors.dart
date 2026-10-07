/// Substitutions applied to lines of AsciiDoc text.
///
/// Port of `lib/asciidoctor/substitutors.rb`.
///
/// The substitutions are top-level functions:
///
/// * Functions that act on a node take an [AbstractNode] first (e.g.
///   [applySubs], [subQuotes], [subMacros]); the document is derived from
///   the node.
/// * Pure functions take no node (e.g. [subSpecialchars], [subReplacements],
///   [normalizeText], [splitSimpleCsv]).
/// * Substitution names are strings (`'quotes'`, `'highlight'`, ...), and
///   the standard substitution groups are constants ([normalSubs],
///   [basicSubs], ...).
///
/// Shared constants ([intrinsicAttributes], [quoteSubs], [replacements],
/// [hardLineBreak], [stemTypeAliases], [asciidocExtensions], the compliance
/// flags) live in `constants.dart`, and the regular expressions in
/// `rx.dart`.
///
/// Implementation notes:
///
/// * Every function requires a real [Document] behind the node
///   ([_documentOf] throws a [StateError] otherwise), because
///   [NodeDocument] does not expose `register`, `resolveId`, `footnotes`,
///   `outfilesuffix`, attribute locking, extensions or the syntax
///   highlighter.
/// * The passthrough lock is kept in a private [Expando] rather than on
///   [AbstractNode].
/// * `{set:...}` attribute assignments go through [_storeAttribute], which
///   reproduces the parser's attribute storing.
/// * Missed references are always passed to the logger at info level
///   ([_logPossibleInvalidReference]); the default logger drops them.
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/attribute_list.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/constants.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/extensions.dart' show MacroAttributes;
import 'package:asciidart/src/helpers.dart';
import 'package:asciidart/src/highlight/highlight.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/inline_tree.dart';
import 'package:asciidart/src/ruby_semantics.dart';
import 'package:asciidart/src/rx.dart';
import 'package:asciidart/src/text_case.dart';
import 'package:meta/meta.dart';

/// Matches XML special characters. Port of `SpecialCharsRx`.
final RegExp specialCharsRx = RegExp('[<&>]');

/// Replacement table for XML special characters. Port of `SpecialCharsTr`.
const Map<String, String> specialCharsTr = <String, String>{
  '>': '&gt;',
  '<': '&lt;',
  '&': '&amp;',
};

/// Detects whether text may contain quoted text, keyed by compat mode.
/// Port of `QuotedTextSniffRx`.
final Map<bool, RegExp> quotedTextSniffRx = <bool, RegExp>{
  false: RegExp('[*_`#^~]'),
  true: RegExp("[*'_+#^~]"),
};

/// Substitutions for a bare special-characters pass. Port of `BASIC_SUBS`.
const List<Sub> basicSubs = [Sub.specialcharacters];

/// Substitutions for header metadata and attribute assignments.
/// Port of `HEADER_SUBS`.
const List<Sub> headerSubs = [Sub.specialcharacters, Sub.attributes];

/// No substitutions. Port of `NO_SUBS`.
const List<Sub> noSubs = [];

/// The default paragraph substitutions. Port of `NORMAL_SUBS`.
const List<Sub> normalSubs = [
  Sub.specialcharacters,
  Sub.quotes,
  Sub.attributes,
  Sub.replacements,
  Sub.macros,
  Sub.postReplacements,
];

/// Substitutions for reference text. Port of `REFTEXT_SUBS`.
const List<Sub> reftextSubs = [
  Sub.specialcharacters,
  Sub.quotes,
  Sub.replacements,
];

/// Substitutions for verbatim blocks. Port of `VERBATIM_SUBS`.
const List<Sub> verbatimSubs = [Sub.specialcharacters, Sub.callouts];

/// Named substitution groups. Port of `SUB_GROUPS`.
const Map<String, List<Sub>> subGroups = {
  'none': noSubs,
  'normal': normalSubs,
  'verbatim': verbatimSubs,
  'specialchars': basicSubs,
};

/// Single-letter substitution hints for the inline context.
/// Port of `SUB_HINTS`.
const Map<String, String> subHints = <String, String>{
  'a': 'attributes',
  'm': 'macros',
  'n': 'normal',
  'p': 'post_replacements',
  'q': 'quotes',
  'r': 'replacements',
  'c': 'specialcharacters',
  'v': 'verbatim',
};

/// Cancel marker for a dropped line. Port of `CAN` (`\u0018`).
const String can = '\u0018';

/// Delete marker for a dropped empty line. Port of `DEL` (`\u007f`).
const String del = '\u007f';

/// [text] with its quoted text substituted, each index term on its own
/// (asciidart's: Asciidoctor lets a mark inside a term, as in
/// `_hyperscript`, pair with one after it): a term's marks pair only
/// within it, and quoted text may still enclose a whole term.
String _subQuotesKeepingIndexterms(AbstractNode node, String text) {
  if (!(text.contains('((') && text.contains('))')) &&
      !text.contains('dexterm')) {
    return subQuotes(node, text);
  }
  final terms = <String>[];
  final masked = text.replaceAllMapped(inlineIndextermMacroRx, (match) {
    final term = match[0]!;
    if (term.startsWith(r'\')) return term;
    terms.add(subQuotes(node, term));
    return '$_termStart${terms.length - 1}$_termEnd';
  });
  if (terms.isEmpty) return subQuotes(node, text);
  return subQuotes(node, masked).replaceAllMapped(
    RegExp('$_termStart(\\d+)$_termEnd'),
    (match) => terms[int.parse(match[1]!)],
  );
}

/// The ends of an index term's placeholder while quotes are substituted.
const String _termStart = '\u0098';
const String _termEnd = '\u0099';

/// Start of a guarded passthrough placeholder (`\u0096`). Port of `PASS_START`.
const String passStart = '\u0096';

/// End of a guarded passthrough placeholder (`\u0097`). Port of `PASS_END`.
const String passEnd = '\u0097';

/// Matches a passthrough slot. Port of `PassSlotRx`.
final RegExp passSlotRx = RegExp('$passStart(\\d+)$passEnd');

/// Matches a passthrough slot mangled by syntax highlighting.
/// Port of `HighlightedPassSlotRx`.
final RegExp highlightedPassSlotRx = RegExp(
  '<span\\b[^>]*>$passStart</span>[^\\d]*(\\d+)[^\\d]*'
  '<span\\b[^>]*>$passEnd</span>',
);

/// A single backslash. Port of `RS`.
const String rs = r'\';

/// A closing square bracket. Port of `R_SB`.
const String rSb = ']';

/// An escaped closing square bracket. Port of `ESC_R_SB`.
const String escRSb = r'\]';

/// A plus sign. Port of `PLUS`.
const String plus = '+';

/// A passthrough stashed while substitutions run, restored afterwards.
final class Passthrough {
  /// Creates a passthrough of [text] with [subs], optionally converted as
  /// quoted text of [type] with [attributes].
  const new(this.text, {this.subs, this.type, this.attributes});

  /// The passthrough text.
  final String text;

  /// The substitutions applied when the text is restored (`null` for
  /// none).
  final List<Sub>? subs;

  /// The quoted text type the restored text is converted as, if any.
  final String? type;

  /// The attributes of the quoted text, if any.
  final Map<String, String>? attributes;
}

/// The passthroughs stashed per node while substitutions run.
final Expando<List<Passthrough>> _passthroughs = Expando<List<Passthrough>>(
  'passthroughs',
);

/// The passthroughs stashed for [node].
List<Passthrough> _passthroughsOf(AbstractNode node) =>
    _passthroughs[node] ??= <Passthrough>[];

/// The passthroughs stashed for [node], exposed for tests.
@visibleForTesting
List<Passthrough> passthroughsOf(AbstractNode node) => _passthroughsOf(node);

/// Tracks the passthrough lock per node.
///
/// [AbstractNode] has no field for it, so the lock lives here. Placeholders
/// can move around, so only the outermost substitution call clears them.
final Expando<bool> _passthroughsLocked = Expando<bool>('passthroughsLocked');

/// Returns the [Document] behind [node].
///
/// [NodeDocument] does not expose the members substitutors need
/// (`register`, `resolveId`, `footnotes`, `outfilesuffix`, attribute
/// locking, extensions, the syntax highlighter), so every function requires
/// a real document. Throws a [StateError] for foreign node implementations.
Document _documentOf(AbstractNode node) {
  final doc = node is Document ? node : node.document;
  if (doc is! Document) {
    throw StateError('Substitutions require the node to belong to a Document.');
  }
  return doc;
}

/// Returns [node] as a block, for constructing [Inline] children.
///
/// Substitutions normally run on block-level nodes; a non-block node falls
/// back to its parent.
AbstractBlock _blockOf(AbstractNode node) {
  if (node is AbstractBlock) return node;
  final parent = node.parent;
  if (parent == null) {
    throw StateError(
      'Substitutors require a block-level node or a parent block.',
    );
  }
  return parent;
}

/// Whether [value] ends with any of [suffixes].
bool _endsWithAny(String value, Iterable<String> suffixes) {
  for (final suffix in suffixes) {
    if (value.endsWith(suffix)) return true;
  }
  return false;
}

/// Splits [source] on [separator] into at most [limit] parts, keeping
/// trailing empty fields.
List<String> _splitLimit(String source, String separator, int limit) {
  final parts = <String>[];
  var start = 0;
  while (parts.length < limit - 1) {
    final idx = source.indexOf(separator, start);
    if (idx == -1) break;
    parts.add(source.substring(start, idx));
    start = idx + separator.length;
  }
  parts.add(source.substring(start));
  return parts;
}

/// Logs a possible invalid reference to [refid] unless it is registered.
///
/// The message is logged at info level, which the default logger drops.
void _logPossibleInvalidReference(
  AbstractNode node,
  Document doc,
  String refid,
) {
  if (!doc.catalog.refs.containsKey(refid)) {
    node.logger.info('possible invalid reference: $refid');
  }
}

/// Applies [SubsApplier] substitutions on behalf of `node`.
///
/// [AttributeList] calls this for single-quoted values.
final class _BlockSubsApplier implements SubsApplier {
  /// Creates an applier delegating to `node`.
  new(this._node);

  final AbstractNode _node;

  @override
  String applySubs(String value) => _applySubsString(_node, value);
}

/// Applies normal substitutions to [value] on behalf of [node].
String _applySubsString(AbstractNode node, String value) =>
    applySubs(node, value);

/// Applies the specified substitutions to [text].
///
/// [subs] are the substitutions to perform (defaults to [normalSubs]); a
/// `null` [subs] returns [text] unchanged.
///
/// Port of `Substitutors#apply_subs`.
String applySubs(
  AbstractNode node,
  String text, [
  List<Sub>? subs = normalSubs,
]) {
  if (text.isEmpty || subs == null) return text;
  return _applySubsInRun(node, text, subs);
}

/// Applies [subs] to [text] as [applySubs] does, and returns the inline
/// elements found with the text between them (see [InlineRun.track]).
List<InlineContent> applySubsTree(
  AbstractNode node,
  String text, [
  List<Sub>? subs = normalSubs,
]) {
  if (text.isEmpty || subs == null) {
    return text.isEmpty ? const [] : [InlineText(text)];
  }
  return InlineRun.track(text, () => _applySubsInRun(node, text, subs)).$2;
}

String _applySubsInRun(AbstractNode node, String text, List<Sub> subs) {
  var subject = text;

  List<Passthrough>? passthrus;
  var clearPassthrus = false;
  if (subs.contains(Sub.macros)) {
    subject = extractPassthroughs(node, subject);
    if (_passthroughsOf(node).isNotEmpty) {
      passthrus = _passthroughsOf(node);
      // NOTE placeholders can move around, so we can only clear in the
      // outermost substitution call
      if (_passthroughsLocked[node] != true) {
        _passthroughsLocked[node] = true;
        clearPassthrus = true;
      }
    }
  }

  for (final sub in subs) {
    InlineRun.advance(subject);
    switch (sub) {
      case Sub.specialcharacters:
        subject = subSpecialchars(subject);
      case Sub.quotes:
        subject = _subQuotesKeepingIndexterms(node, subject);
      case Sub.attributes:
        if (subject.contains(attrRefHead)) {
          subject = subAttributes(node, subject);
        }
      case Sub.replacements:
        subject = subReplacements(subject);
      case Sub.macros:
        subject = subMacros(node, subject);
      case Sub.highlight:
        subject = highlightSource(
          node,
          subject,
          processCallouts: subs.contains(Sub.callouts),
        );
      case Sub.callouts:
        if (!subs.contains(Sub.highlight)) {
          subject = subCallouts(node, subject);
        }
      case Sub.postReplacements:
        subject = subPostReplacements(node, subject);
    }
  }

  if (passthrus != null) {
    // Placeholders can be inside the markup of inline elements, as in
    // Asciidoctor, which converts them before restoring passthroughs.
    subject = restorePassthroughs(node, subject);
    if (clearPassthrus) {
      passthrus.clear();
      _passthroughsLocked[node] = false;
    }
  }

  return subject;
}

/// Applies the specified substitutions to [lines] as one text, returning
/// the result split back into lines (a new list).
///
/// Port of `Substitutors#apply_subs` for an array of lines.
List<String> applySubsToLines(
  AbstractNode node,
  List<String> lines, [
  List<Sub>? subs = normalSubs,
]) {
  if (lines.isEmpty || subs == null) return List<String>.of(lines);
  final result = applySubs(
    node,
    lines.length > 1 ? lines.join(lf) : lines[0],
    subs,
  );
  // An empty result has no lines.
  return result.isEmpty ? <String>[] : result.split(lf);
}

/// Applies normal substitutions to [text].
///
/// Port of `Substitutors#apply_normal_subs`.
String applyNormalSubs(AbstractNode node, String text) => applySubs(node, text);

/// Applies header substitutions (for header metadata and attribute
/// assignments) to [text].
///
/// Port of `Substitutors#apply_header_subs`.
String applyHeaderSubs(AbstractNode node, String text) =>
    applySubs(node, text, headerSubs);

/// Applies title substitutions to [text].
///
/// Port of `Substitutors#apply_title_subs` (an alias of `apply_subs`).
String applyTitleSubs(AbstractNode node, String text) => applySubs(node, text);

/// Applies reftext substitutions to [text].
///
/// Port of `Substitutors#apply_reftext_subs`.
String applyReftextSubs(AbstractNode node, String text) =>
    applySubs(node, text, reftextSubs);

/// Substitutes special characters (i.e., encodes XML) in [text].
///
/// The special characters `<`, `&` and `>` are replaced with `&lt;`,
/// `&amp;` and `&gt;`, respectively.
///
/// Port of `Substitutors#sub_specialchars`.
String subSpecialchars(String text) {
  if (text.contains('>') || text.contains('&') || text.contains('<')) {
    return InlineRun.replace(
      text,
      specialCharsRx,
      (match) => specialCharsTr[match.group(0)]!,
    );
  }
  return text;
}

/// Substitutes quoted text (emphasis, strong, monospaced, etc.) in [text].
///
/// Port of `Substitutors#sub_quotes`.
String subQuotes(AbstractNode node, String text) {
  final compat = _documentOf(node).compatMode;
  if (!quotedTextSniffRx[compat]!.hasMatch(text)) return text;
  var result = text;
  for (final sub in quoteSubs[compat]!) {
    if (!sub.mayMatch(result)) continue;
    result = InlineRun.replace(
      result,
      sub.pattern,
      (match) =>
          convertQuotedText(node, match as RegExpMatch, sub.type, sub.scope),
    );
  }
  return result;
}

/// Converts a quoted text region.
///
/// [match] is the match for the quoted text region, [type] the quoting type
/// and [scope] the quoting scope (`'constrained'` or `'unconstrained'`).
///
/// Port of `Substitutors#convert_quoted_text`.
String convertQuotedText(
  AbstractNode node,
  RegExpMatch match,
  String type,
  String scope,
) {
  final full = match.group(0)!;
  var resolvedType = type;
  String? unescapedAttrs;
  if (full.startsWith(rs)) {
    if (scope == 'constrained' && match.group(2) != null) {
      unescapedAttrs = '[${match.group(2)}]';
    } else {
      return full.substring(1);
    }
  }

  final block = _blockOf(node);
  if (scope == 'constrained') {
    if (unescapedAttrs != null) {
      final quoted = Inline(
        block,
        InlineContext.quoted,
        text: match.group(3),
        type: resolvedType,
      );
      return '$unescapedAttrs${InlineRun.emit(quoted)}';
    }
    final attrlist = match.group(2);
    String? id;
    Map<String, String>? attributes;
    if (attrlist != null) {
      attributes = parseQuotedTextAttributes(node, attrlist);
      id = attributes['id'];
      if (resolvedType == 'mark') resolvedType = 'unquoted';
    }
    final quoted = Inline(
      block,
      InlineContext.quoted,
      text: match.group(3),
      type: resolvedType,
      id: id,
      attributes: attributes,
    );
    return '${match.group(1)}${InlineRun.emit(quoted)}';
  } else {
    final attrlist = match.group(1);
    String? id;
    Map<String, String>? attributes;
    if (attrlist != null) {
      attributes = parseQuotedTextAttributes(node, attrlist);
      id = attributes['id'];
      if (resolvedType == 'mark') resolvedType = 'unquoted';
    }
    return InlineRun.emit(
      Inline(
        block,
        InlineContext.quoted,
        text: match.group(2),
        type: resolvedType,
        id: id,
        attributes: attributes,
      ),
    );
  }
}

/// Substitutes attribute references in [text].
///
/// If an attribute referenced in the line is missing or undefined, the line
/// may be dropped based on the `attribute-missing` or `attribute-undefined`
/// setting, respectively. [attributeMissing] overrides the missing-attribute
/// handling; [reportDroppedLine] logs a dropped line at info level.
///
/// Port of `Substitutors#sub_attributes`.
String subAttributes(
  AbstractNode node,
  String text, {
  AttributeMissing? attributeMissing,
  bool reportDroppedLine = true,
}) {
  final doc = _documentOf(node);
  final docAttrs = doc.attributes;
  var drop = false;
  var dropLine = false;
  var dropEmptyLine = false;
  String? attributeUndefined;
  AttributeMissing? attributeMissingResolved;
  AttributeMissing resolveMissing() => attributeMissingResolved ??=
      attributeMissing ??
      AttributeMissing.parse(
        docAttrs['attribute-missing'] ?? Compliance.attributeMissing,
      );
  final result = InlineRun.replace(text, attributeReferenceRx, (match) {
    // escaped attribute, return unescaped
    if (match.group(1) == rs || match.group(4) == rs) {
      return '{${match.group(2)}}';
    } else if (match.group(3) != null) {
      final parts = _splitLimit(match.group(2)!, ':', 3);
      final directive = parts[0];
      final args = parts.sublist(1);
      switch (directive) {
        case 'set':
          final value = _storeAttribute(
            doc,
            args.isNotEmpty ? args[0] : '',
            args.length > 1 ? args[1] : '',
          ).$2;
          // NOTE since this is an assignment, only drop-line applies here
          // (skip and drop imply the same result)
          if (value != null ||
              (attributeUndefined ??=
                      docAttrs['attribute-undefined'] ??
                      Compliance.attributeUndefined) !=
                  'drop-line') {
            drop = true;
            dropEmptyLine = true;
            return del;
          } else {
            drop = true;
            dropLine = true;
            return can;
          }
        case 'counter2':
          _counterWithArgs(doc, args);
          drop = true;
          dropEmptyLine = true;
          return del;
        default: // 'counter'
          return _counterWithArgs(doc, args);
      }
    } else if (docAttrs.containsKey(downcase(match.group(2)!))) {
      return docAttrs[downcase(match.group(2)!)]!;
    } else if (intrinsicAttributes.containsKey(downcase(match.group(2)!))) {
      return intrinsicAttributes[downcase(match.group(2)!)]!;
    } else {
      final key = downcase(match.group(2)!);
      switch (resolveMissing()) {
        case AttributeMissing.drop:
          drop = true;
          dropEmptyLine = true;
          return del;
        case AttributeMissing.dropLine:
          if (reportDroppedLine) {
            node.logger.info(
              'dropping line containing reference to missing attribute: $key',
            );
          }
          //elsif drop_line_severity == :warn
          //  logger.warn %(dropping line containing reference to missing
          //  attribute: #{key})
          drop = true;
          dropLine = true;
          return can;
        case AttributeMissing.warn:
          node.logger.warn('skipping reference to missing attribute: $key');
          return match.group(0)!;
        case AttributeMissing.skip:
          return match.group(0)!;
      }
    }
  });

  if (!drop) return result;
  // drop lines from text
  if (dropEmptyLine) {
    final lines = collapseRuns(result, del).split(lf);
    final kept = dropLine
        ? lines
              .where(
                (line) =>
                    line != del &&
                    line != can &&
                    !line.startsWith(can) &&
                    !line.contains(can),
              )
              .join(lf)
        : lines.where((line) => line != del).join(lf);
    return kept.replaceAll(del, '');
  } else if (result.contains(lf)) {
    return result
        .split(lf)
        .where(
          (line) => line != can && !line.startsWith(can) && !line.contains(can),
        )
        .join(lf);
  } else {
    return '';
  }
}

/// Runs the document counter with the `{counter:...}` [args].
String _counterWithArgs(Document doc, List<String> args) {
  if (args.length > 2) {
    throw ArgumentError(
      'wrong number of arguments for counter '
      '(given ${args.length}, expected 1..2)',
    );
  }
  return doc.counter(
    args.isNotEmpty ? args[0] : '',
    args.length > 1 ? args[1] : null,
  );
}

/// Stores an attribute assignment from a `{set:name:value}` reference.
///
/// Mirrors `Parser.store_attribute` with a document and no block
/// attributes. Returns the (name, value) pair; the value is `null` for an
/// unset.
(String, String?) _storeAttribute(Document doc, String name, String? value) {
  // TODO move processing of attribute value to utility method
  var attrName = name;
  var attrValue = value;
  if (attrName.endsWith('!')) {
    // a null value signals the attribute should be deleted (unset)
    attrName = dropLastChar(attrName);
    attrValue = null;
  } else if (attrName.startsWith('!')) {
    // a null value signals the attribute should be deleted (unset)
    attrName = attrName.substring(1);
    attrValue = null;
  }

  attrName = downcase(attrName.replaceAll(invalidAttributeNameCharsRx, ''));
  if (attrName == 'numbered') {
    attrName = 'sectnums';
  } else if (attrName == 'hardbreaks') {
    attrName = 'hardbreaks-option';
  } else if (attrName == 'showtitle') {
    _storeAttribute(doc, 'notitle', attrValue != null ? null : '');
  }

  if (attrValue != null) {
    var strValue = attrValue;
    if (attrName == 'leveloffset') {
      // support relative leveloffset values
      if (strValue.startsWith('+')) {
        strValue =
            (parseLeadingInt(doc.attr('leveloffset', '0')) +
                    parseLeadingInt(strValue.substring(1)))
                .toString();
      } else if (strValue.startsWith('-')) {
        strValue =
            (parseLeadingInt(doc.attr('leveloffset', '0')) -
                    parseLeadingInt(strValue.substring(1)))
                .toString();
      }
    }
    // QUESTION should we set value to locked value if set_attribute
    // returns false?
    return (attrName, doc.setAttribute(attrName, strValue) ?? strValue);
  } else {
    doc.deleteAttribute(attrName);
    return (attrName, attrValue);
  }
}

/// Substitutes replacement characters (e.g., copyright, trademark, etc.)
/// in [text].
///
/// Port of `Substitutors#sub_replacements`.
String subReplacements(String text) {
  if (!replaceableTextRx.hasMatch(text)) return text;
  var result = text;
  for (final replacement in replacements) {
    if (!result.contains(replacement.guard)) continue;
    result = InlineRun.replace(
      result,
      replacement.pattern,
      (match) => doReplacement(
        match as RegExpMatch,
        replacement.replacement,
        replacement.scope,
      ),
    );
  }
  return result;
}

/// Substitutes replacement text for the matched location.
///
/// [match] is the match, [replacement] the replacement text and [restore]
/// how surrounding captures are restored (`'none'`, `'leading'` or
/// `'bounding'`).
///
/// Port of `Substitutors#do_replacement`.
String doReplacement(RegExpMatch match, String replacement, String restore) {
  final captured = match.group(0)!;
  // A leading capture that starts the match may hold a backslash of its
  // own (the man page's closing font markup); the escape follows it.
  final group1 = restore == 'none' ? '' : match.group(1)!;
  final lead = captured.startsWith(group1) ? group1 : '';
  if (captured.indexOf(rs, lead.length) != -1) {
    // we have to use sub since we aren't sure it's the first char
    return '$lead${captured.substring(lead.length).replaceFirst(rs, '')}';
  }
  switch (restore) {
    case 'none':
      return replacement;
    case 'bounding':
      return '${match.group(1)}$replacement${match.group(2)}';
    default: // 'leading'
      return '${match.group(1)}$replacement';
  }
}

/// Whether [regexp] declares any named capture groups (`(?<name>...)`,
/// excluding the `(?<=` / `(?<!` lookbehinds).
///
/// The pattern source is inspected.
bool _hasNamedGroups(RegExp regexp) =>
    RegExp(r'\(\?<[A-Za-z_]').hasMatch(regexp.pattern);

/// Returns the `name`d group of [match], or `null` when the pattern does
/// not declare it.
String? _namedGroupOrNull(Match match, String name) {
  final regExpMatch = match as RegExpMatch;
  return regExpMatch.groupNames.contains(name)
      ? regExpMatch.namedGroup(name)
      : null;
}

/// Substitutes inline macros (e.g., links, images, etc.) in [text], which
/// may span multiple lines.
///
/// Port of `Substitutors#sub_macros`.
String subMacros(AbstractNode node, String text) {
  //return text if text.nil_or_empty?
  // some look ahead assertions to cut unnecessary regex calls
  final foundSquareBracket = text.contains('[');
  final foundColon = text.contains(':');
  final foundMacroish = foundSquareBracket && foundColon;
  final foundMacroishShort = foundMacroish && text.contains(':[');
  final doc = _documentOf(node);
  final docAttrs = doc.attributes;
  final compat = doc.compatMode;
  final block = _blockOf(node);
  var result = text;

  // TODO allow position of substitution to be controlled (before or after
  // other macros)
  // TODO this handling needs some cleanup
  // Port of `Substitutors#sub_macros` (lib/asciidoctor/substitutors.rb:308-349).
  final macroExtensions = doc.extensions;
  if (macroExtensions != null && macroExtensions.hasInlineMacros) {
    for (final extension in macroExtensions.inlineMacros) {
      final instance = extension.instance;
      final config = instance.config;
      final regexp = instance.regexp;
      final hasNamedGroups = _hasNamedGroups(regexp);
      result = InlineRun.replace(result, regexp, (match) {
        final fullMatch = match.group(0)!;
        // Honor the escape.
        if (fullMatch.startsWith(rs)) return fullMatch.substring(1);
        String? target;
        String? content;
        if (hasNamedGroups) {
          target = _namedGroupOrNull(match, 'target');
          content = _namedGroupOrNull(match, 'content');
        } else {
          target = match.groupCount >= 1 ? match.group(1) : null;
          content = match.groupCount >= 2 ? match.group(2) : null;
        }
        final attributes = <String, String>{...config.defaultAttrs};
        if (content != null) {
          if (content.isEmpty) {
            if (config.macroAttributes == MacroAttributes.text) {
              attributes['text'] = content;
            }
          } else {
            final normalized = normalizeText(
              content,
              normalizeWhitespace: true,
              unescapeClosingSquareBrackets: true,
            );
            // QUESTION should we store the unparsed attrlist in the
            // attrlist key?
            if (config.macroAttributes == MacroAttributes.parsed) {
              parseAttributes(
                node,
                normalized,
                posattrs: config.positionalAttrs,
                into: attributes,
              );
            } else {
              attributes['text'] = normalized;
            }
            content = normalized;
          }
          // NOTE for convenience, map content (unparsed attrlist) to
          // target when format is short.
          target ??= config.format == 'short' ? content : target;
        }
        // NOTE `target` is null only for custom patterns without a
        // target capture; the process method requires a target.
        final replacement = instance.process(block, target!, attributes);
        if (replacement == null) return '';
        final inlineSubsSpec = replacement.attributes.remove('subs');
        final inlineSubs = inlineSubsSpec != null
            ? expandSubs(node, inlineSubsSpec, 'custom inline macro')
            : null;
        final replacementText = replacement.text;
        if (inlineSubs != null && replacementText != null) {
          replacement.text = applySubs(node, replacementText, inlineSubs);
        }
        return InlineRun.emit(replacement);
      });
    }
  }

  if (docAttrs.containsKey('experimental')) {
    if (foundMacroishShort &&
        (result.contains('kbd:') || result.contains('btn:'))) {
      result = InlineRun.replace(result, inlineKbdBtnMacroRx, (match) {
        // honor the escape
        if (match.group(1) != null) {
          return match.group(0)!.substring(1);
        } else if (match.group(2) == 'kbd') {
          var keys = match.group(3)!.trimAscii();
          if (keys.contains(rSb)) {
            keys = keys.replaceAll(escRSb, rSb);
          }
          List<String> keyList;
          if (keys.length > 1) {
            final commaIdx = keys.indexOf(',', 1);
            final plusIdx = keys.indexOf('+', 1);
            final int? delimIdx;
            if (commaIdx != -1) {
              delimIdx = plusIdx != -1 && plusIdx < commaIdx
                  ? plusIdx
                  : commaIdx;
            } else {
              delimIdx = plusIdx != -1 ? plusIdx : null;
            }
            if (delimIdx != null) {
              final delim = keys[delimIdx];
              // NOTE handle special case where keys ends with delimiter
              // (e.g., Ctrl++ or Ctrl,,)
              if (keys.endsWith(delim)) {
                keyList = keys
                    .substring(0, keys.length - 1)
                    .split(delim)
                    .map((key) => key.trimAscii())
                    .toList();
                keyList[keyList.length - 1] += delim;
              } else {
                keyList = keys
                    .split(delim)
                    .map((key) => key.trimAscii())
                    .toList();
              }
            } else {
              keyList = [keys];
            }
          } else {
            keyList = [keys];
          }
          return InlineRun.emit(
            Inline(block, InlineContext.kbd, keys: keyList),
          );
        } else {
          // match.group(2) == 'btn'
          return InlineRun.emit(
            Inline(
              block,
              InlineContext.button,
              text: normalizeText(
                match.group(3)!,
                normalizeWhitespace: true,
                unescapeClosingSquareBrackets: true,
              ),
            ),
          );
        }
      });
    }

    if (foundMacroish && result.contains('menu:')) {
      result = InlineRun.replace(result, inlineMenuMacroRx, (match) {
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }

        final menu = match.group(1)!;
        final itemsRaw = match.group(2);
        final List<String> submenus;
        final String? menuitem;
        if (itemsRaw != null) {
          var items = itemsRaw;
          if (items.contains(rSb)) {
            items = items.replaceAll(escRSb, rSb);
          }
          final String? delim;
          if (items.contains('&gt;')) {
            delim = '&gt;';
          } else if (items.contains(',')) {
            delim = ',';
          } else {
            delim = null;
          }
          if (delim != null) {
            final parts = splitDropTrailingEmpty(
              items,
              delim,
            ).map((item) => item.trimAscii()).toList();
            menuitem = parts.removeLast();
            submenus = parts;
          } else {
            submenus = <String>[];
            menuitem = items.trimRightAscii();
          }
        } else {
          submenus = <String>[];
          menuitem = null;
        }

        return InlineRun.emit(
          Inline(
            block,
            InlineContext.menu,
            attributes: {'menu': menu, 'menuitem': ?menuitem},
            submenus: submenus,
          ),
        );
      });
    }

    if (result.contains('"') && result.contains('&gt;')) {
      result = InlineRun.replace(result, inlineMenuRx, (match) {
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }

        final parts = splitDropTrailingEmpty(
          match.group(1)!,
          '&gt;',
        ).map((item) => item.trimAscii()).toList();
        final menu = parts.removeAt(0);
        final menuitem = parts.removeLast();
        return InlineRun.emit(
          Inline(
            block,
            InlineContext.menu,
            attributes: {'menu': menu, 'menuitem': menuitem},
            submenus: parts,
          ),
        );
      });
    }
  }

  if (foundMacroish &&
      (result.contains('image:') || result.contains('icon:'))) {
    // image:filename.png[Alt Text]
    result = InlineRun.replace(result, inlineImageMacroRx, (match) {
      // honor the escape
      if (match.group(0)!.startsWith(rs)) {
        return match.group(0)!.substring(1);
      }
      final isIcon = match.group(0)!.startsWith('icon:');
      final type = isIcon ? 'icon' : 'image';
      final posattrs = isIcon
          ? const ['size']
          : const ['alt', 'width', 'height'];
      final target = match.group(1)!;
      final attrs = parseAttributes(
        node,
        match.group(2),
        posattrs: posattrs,
        unescapeInput: true,
      );
      String? id;
      if (!isIcon) {
        id = attrs['id'];
        doc.registerImage(target);
        if (docAttrs['imagesdir'] case final imagesdir?) {
          attrs.putIfAbsent('imagesdir', () => imagesdir);
        }
      }
      if (!attrs.containsKey('alt')) {
        final defaultAlt = Helpers.basename(
          target,
          dropExtension: true,
        ).replaceAll(RegExp('[_-]'), ' ');
        attrs['alt'] = defaultAlt;
        attrs['default-alt'] = defaultAlt;
      }
      return InlineRun.emit(
        Inline(
          block,
          InlineContext.image,
          type: type,
          target: target,
          id: id,
          attributes: attrs,
        ),
      );
    });
  }

  if ((result.contains('((') && result.contains('))')) ||
      (foundMacroishShort && result.contains('dexterm'))) {
    // (((Tigers,Big cats)))
    // indexterm:[Tigers,Big cats]
    // ((Tigers))
    // indexterm2:[Tigers]
    result = InlineRun.replace(result, inlineIndextermMacroRx, (match) {
      final macro = match.group(1);
      if (macro == 'indexterm') {
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }

        // indexterm:[Tigers,Big cats]
        final attrlist = normalizeText(
          match.group(2)!,
          normalizeWhitespace: true,
          unescapeClosingSquareBrackets: true,
        );
        Map<String, String> attrs;
        List<String> terms;
        List<String>? seeAlso;
        if (attrlist.contains('=')) {
          attrs = AttributeList(attrlist, _BlockSubsApplier(node)).parse();
          final primary = attrs['1'];
          if (primary != null) {
            terms = <String>[primary];
            final secondary = attrs['2'];
            if (secondary != null) {
              terms.add(secondary);
              final tertiary = attrs['3'];
              if (tertiary != null) terms.add(tertiary);
            }
            seeAlso = _seeAlsoList(attrs.remove('see-also'));
          } else {
            // Without a primary term, the whole attrlist is the term and
            // the terms are its characters, as in Asciidoctor.
            attrs = <String, String>{};
            terms = [
              for (final rune in attrlist.runes) String.fromCharCode(rune),
            ];
          }
        } else {
          attrs = <String, String>{};
          terms = splitSimpleCsv(attrlist);
        }
        return InlineRun.emit(
          Inline(
            block,
            InlineContext.indexterm,
            attributes: attrs,
            terms: terms,
            seeAlso: seeAlso,
          ),
        );
      } else if (macro == 'indexterm2') {
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }

        // indexterm2:[Tigers]
        var term = normalizeText(
          match.group(2)!,
          normalizeWhitespace: true,
          unescapeClosingSquareBrackets: true,
        );
        Map<String, String>? attrs;
        List<String>? seeAlso;
        if (term.contains('=')) {
          final parsed = AttributeList(term, _BlockSubsApplier(node)).parse();
          final first = parsed['1'];
          if (first != null) {
            term = first;
            attrs = parsed;
            seeAlso = _seeAlsoList(parsed.remove('see-also'));
          }
        }
        return InlineRun.emit(
          Inline(
            block,
            InlineContext.indexterm,
            text: term,
            attributes: attrs,
            type: 'visible',
            seeAlso: seeAlso,
          ),
        );
      } else {
        var enclText = match.group(3)!;
        var visible = false;
        String? before;
        String? after;
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          // escape concealed index term, but process nested flow index term
          if (enclText.startsWith('(') && enclText.endsWith(')')) {
            enclText = enclText.substring(1, enclText.length - 1);
            visible = true;
            before = '(';
            after = ')';
          } else {
            return match.group(0)!.substring(1);
          }
        } else {
          visible = true;
          if (enclText.startsWith('(')) {
            if (enclText.endsWith(')')) {
              enclText = enclText.substring(1, enclText.length - 1);
              visible = false;
            } else {
              enclText = enclText.substring(1);
              before = '(';
              after = '';
            }
          } else if (enclText.endsWith(')')) {
            enclText = dropLastChar(enclText);
            before = '';
            after = ')';
          }
        }
        final String subbedTerm;
        if (visible) {
          // ((Tigers))
          var term = normalizeText(enclText, normalizeWhitespace: true);
          Map<String, String>? termAttrs;
          List<String>? seeAlso;
          if (term.contains(';&')) {
            if (term.contains(' &gt;&gt; ')) {
              final idx = term.indexOf(' &gt;&gt; ');
              termAttrs = {'see': term.substring(idx + ' &gt;&gt; '.length)};
              term = term.substring(0, idx);
            } else if (term.contains(' &amp;&gt; ')) {
              final parts = splitDropTrailingEmpty(term, ' &amp;&gt; ');
              term = parts.removeAt(0);
              seeAlso = parts;
            }
          }
          subbedTerm = InlineRun.emit(
            Inline(
              block,
              InlineContext.indexterm,
              text: term,
              attributes: termAttrs,
              type: 'visible',
              seeAlso: seeAlso,
            ),
          );
        } else {
          // (((Tigers,Big cats)))
          var terms = normalizeText(enclText, normalizeWhitespace: true);
          final attrs = <String, String>{};
          List<String>? seeAlso;
          if (terms.contains(';&')) {
            if (terms.contains(' &gt;&gt; ')) {
              final idx = terms.indexOf(' &gt;&gt; ');
              attrs['see'] = terms.substring(idx + ' &gt;&gt; '.length);
              terms = terms.substring(0, idx);
            } else if (terms.contains(' &amp;&gt; ')) {
              final parts = splitDropTrailingEmpty(terms, ' &amp;&gt; ');
              terms = parts.removeAt(0);
              seeAlso = parts;
            }
          }
          subbedTerm = InlineRun.emit(
            Inline(
              block,
              InlineContext.indexterm,
              attributes: attrs,
              terms: splitSimpleCsv(terms),
              seeAlso: seeAlso,
            ),
          );
        }
        return before != null ? '$before$subbedTerm$after' : subbedTerm;
      }
    });
  }

  return _subMacrosLinks(
    node,
    block,
    doc,
    docAttrs,
    compat,
    result,
    foundSquareBracket,
    foundMacroish,
  );
}

/// Splits a `see-also` attribute value into its terms, or returns `null`
/// when [value] is `null`.
List<String>? _seeAlsoList(String? value) {
  if (value == null) return null;
  return value.contains(',')
      ? splitDropTrailingEmpty(value, ',').map(trimLeftAscii).toList()
      : <String>[value];
}

/// Continues [subMacros] with links, emails, anchors, xrefs and footnotes.
///
/// Split out only to keep function sizes manageable; the steps run in this
/// order. [foundSquareBracket] and
/// [foundMacroish] are the sniffs computed on the original text.
String _subMacrosLinks(
  AbstractNode node,
  AbstractBlock block,
  Document doc,
  Map<String, String> docAttrs,
  bool compat,
  String text,
  bool foundSquareBracket,
  bool foundMacroish,
) {
  final foundColon = text.contains(':');
  var result = text;

  if (foundColon && result.contains('://')) {
    // inline urls, target[text] (optionally prefixed with link: or
    // enclosed in <>)
    result = InlineRun.replace(result, inlineLinkRx, (match) {
      if (match.group(2) != null && match.group(5) == null) {
        final prefix = match.group(1)!;
        // honor the escapes
        if (prefix.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }
        final scheme = match.group(3)!;
        if (scheme.startsWith(rs)) {
          return '$prefix${match.group(0)!.substring(prefix.length + 1)}';
        }
        final rest = match.group(6);
        if (rest == null) return match.group(0)!;
        final target = scheme + rest;
        doc.registerLink(target);
        final linkText = docAttrs.containsKey('hide-uri-scheme')
            ? target.replaceFirst(uriSniffRx, '')
            : target;
        return InlineRun.emit(
          Inline(
            block,
            InlineContext.anchor,
            text: linkText,
            type: 'link',
            target: target,
            attributes: const {'role': 'bare'},
          ),
        );
      } else {
        final scheme = match.group(3)!;
        // honor the escape
        if (scheme.startsWith(rs)) {
          final prefix = match.group(1)!;
          return '$prefix${match.group(0)!.substring(prefix.length + 1)}';
        }
        var prefix = match.group(1)!;
        var target = scheme + (match.group(4) ?? match.group(7)!);
        var suffix = '';
        // NOTE if group 5 is set (the attrlist), we're looking at a formal
        // macro (e.g., https://example.org[])
        final attrlist = match.group(5);
        String? linkText;
        if (attrlist != null) {
          if (prefix == 'link:') prefix = '';
          linkText = attrlist.isEmpty ? null : attrlist;
        } else {
          switch (prefix) {
            // invalid macro syntax (link: prefix w/o trailing square
            // brackets or URL enclosed in quotes)
            // FIXME we probably shouldn't even get here when the link:
            // prefix is present; the regex is doing too much
            case 'link:':
            case '"':
            case "'":
              return match.group(0)!;
          }
          switch (match.group(8)) {
            // the ; that ends a character reference (`<port>` became
            // `&lt;port&gt;`) is part of the URL (#3128)
            case ';' when _endsWithCharRefName.hasMatch(target):
              break;
            case ';':
              target = target.substring(0, target.length - 1);
              if (target.endsWith(')')) {
                // move trailing ); out of URL
                target = target.substring(0, target.length - 1);
                suffix = ');';
              } else {
                // move trailing ; out of URL
                suffix = ';';
              }
              // NOTE handle case when modified target is a bare URI scheme
              // (e.g., http://)
              if (target == scheme) return match.group(0)!;
            case ':':
              target = target.substring(0, target.length - 1);
              if (target.endsWith(')')) {
                // move trailing ): out of URL
                target = target.substring(0, target.length - 1);
                suffix = '):';
              } else {
                // move trailing : out of URL
                suffix = ':';
              }
              // NOTE handle case when modified target is a bare URI scheme
              // (e.g., http://)
              if (target == scheme) return match.group(0)!;
          }
        }

        String? id;
        Map<String, String>? attrs;
        var bare = false;
        if (linkText != null) {
          String? newLinkText;
          if (linkText.contains(rSb)) {
            linkText = linkText.replaceAll(escRSb, rSb);
            newLinkText = linkText;
          }
          if (!compat && _holdsAttributes(linkText)) {
            // NOTE if an equals sign (=) is present, extract attributes
            // from link text
            final extracted = extractAttributesFromText(node, linkText, '');
            linkText = extracted.text!;
            newLinkText = linkText;
            attrs = extracted.attributes;
            id = attrs['id'];
          }

          if (linkText.endsWith('^')) {
            linkText = linkText.substring(0, linkText.length - 1);
            newLinkText = linkText;
            if (attrs != null) {
              attrs['window'] ??= '_blank';
            } else {
              attrs = {'window': '_blank'};
            }
          }

          if (newLinkText != null && newLinkText.isEmpty) {
            // NOTE the modified target will not be a bare URI scheme
            // (e.g., http://) in this case
            linkText = docAttrs.containsKey('hide-uri-scheme')
                ? target.replaceFirst(uriSniffRx, '')
                : target;
            bare = true;
          }
        } else {
          // NOTE the modified target will not be a bare URI scheme
          // (e.g., http://) in this case
          linkText = docAttrs.containsKey('hide-uri-scheme')
              ? target.replaceFirst(uriSniffRx, '')
              : target;
          bare = true;
        }

        if (bare) {
          if (attrs != null) {
            attrs['role'] = attrs.containsKey('role')
                ? 'bare ${attrs['role']}'
                : 'bare';
          } else {
            attrs = {'role': 'bare'};
          }
        }

        doc.registerLink(target);
        final anchor = Inline(
          block,
          InlineContext.anchor,
          text: linkText,
          type: 'link',
          target: target,
          id: id,
          attributes: attrs,
        );
        return '$prefix${InlineRun.emit(anchor)}$suffix';
      }
    });
  }

  if (foundMacroish && (result.contains('link:') || result.contains('ilto:'))) {
    // inline link macros, link:target[text]
    result = InlineRun.replace(result, inlineLinkMacroRx, (match) {
      // honor the escape
      if (match.group(0)!.startsWith(rs)) {
        return match.group(0)!.substring(1);
      }
      final mailto = match.group(1);
      final String mailtoText;
      var target = match.group(2)!;
      if (mailto != null) {
        mailtoText = match.group(2)!;
        target = 'mailto:$mailtoText';
      } else {
        mailtoText = '';
      }
      Map<String, String>? attrs;
      String? id;
      var linkText = match.group(3)!;
      if (linkText.isNotEmpty) {
        if (linkText.contains(rSb)) {
          linkText = linkText.replaceAll(escRSb, rSb);
        }
        if (mailto != null) {
          if (!compat && linkText.contains(',')) {
            // NOTE if a comma (,) is present, extract attributes from
            // link text
            final extracted = extractAttributesFromText(node, linkText, '');
            linkText = extracted.text!;
            attrs = extracted.attributes;
            id = attrs['id'];
            final subject = attrs['2'];
            if (subject != null) {
              target = '$target?subject=${Helpers.encodeUriComponent(subject)}';
              final body = attrs['3'];
              if (body != null) {
                target = '$target&amp;body=${Helpers.encodeUriComponent(body)}';
              }
            }
          }
        } else if (!compat && _holdsAttributes(linkText)) {
          // NOTE if an equals sign (=) is present, extract attributes
          // from link text
          final extracted = extractAttributesFromText(node, linkText, '');
          linkText = extracted.text!;
          attrs = extracted.attributes;
          id = attrs['id'];
        }

        if (linkText.endsWith('^')) {
          linkText = linkText.substring(0, linkText.length - 1);
          if (attrs != null) {
            attrs['window'] ??= '_blank';
          } else {
            attrs = {'window': '_blank'};
          }
        }
      }

      if (linkText.isEmpty) {
        // mailto is a special case, already processed
        if (mailto != null) {
          linkText = mailtoText;
        } else {
          if (docAttrs.containsKey('hide-uri-scheme')) {
            final stripped = target.replaceFirst(uriSniffRx, '');
            linkText = stripped.isEmpty ? target : stripped;
          } else {
            linkText = target;
          }
          if (attrs != null) {
            attrs['role'] = attrs.containsKey('role')
                ? 'bare ${attrs['role']}'
                : 'bare';
          } else {
            attrs = {'role': 'bare'};
          }
        }
      }

      // QUESTION should a mailto be registered as an e-mail address?
      doc.registerLink(target);
      return InlineRun.emit(
        Inline(
          block,
          InlineContext.anchor,
          text: linkText,
          type: 'link',
          target: target,
          id: id,
          attributes: attrs,
        ),
      );
    });
  }

  if (result.contains('@')) {
    result = InlineRun.replace(result, inlineEmailRx, (match) {
      // honor the escape
      if (match.group(1) != null) {
        return match.group(1) == rs
            ? match.group(0)!.substring(1)
            : match.group(0)!;
      }

      final address = match.group(0)!;
      final target = 'mailto:$address';
      // QUESTION should this be registered as an e-mail address?
      doc.registerLink(target);

      return InlineRun.emit(
        Inline(
          block,
          InlineContext.anchor,
          text: address,
          type: 'link',
          target: target,
        ),
      );
    });
  }

  if (foundSquareBracket &&
      node is AbstractBlock &&
      node.context == BlockContext.listItem &&
      node.parent?.style == 'bibliography') {
    result = InlineRun.replace(
      result,
      inlineBiblioAnchorRx,
      (match) => InlineRun.emit(
        Inline(
          block,
          InlineContext.anchor,
          text: match.group(2),
          type: 'bibref',
          id: match.group(1),
        ),
      ),
      first: true,
    );
  }

  if ((foundSquareBracket && result.contains('[[')) ||
      (foundMacroish && result.contains('or:'))) {
    result = InlineRun.replace(result, inlineAnchorRx, (match) {
      // honor the escape
      if (match.group(1) != null) {
        return match.group(0)!.substring(1);
      }

      // NOTE reftext is only relevant for DocBook output; used as value of
      // xreflabel attribute
      final String? id;
      String? reftext;
      if (match.group(2) != null) {
        id = match.group(2);
        reftext = match.group(3);
        if (reftext != null && reftext.contains(rSb)) {
          reftext = reftext.replaceAll(escRSb, rSb);
        }
      } else {
        id = match.group(4);
        reftext = match.group(5);
        if (reftext != null && reftext.contains(rSb)) {
          reftext = reftext.replaceAll(escRSb, rSb);
        }
      }
      return InlineRun.emit(
        Inline(block, InlineContext.anchor, text: reftext, type: 'ref', id: id),
      );
    });
  }

  //if (text.include? ';&l') || (found_macroish && (text.include? 'xref:'))
  if ((result.contains('&') && result.contains(';&l')) ||
      (foundMacroish && result.contains('xref:'))) {
    result = InlineRun.replace(
      result,
      inlineXrefMacroRx,
      (match) => _convertXrefMacro(
        node,
        block,
        doc,
        docAttrs,
        compat,
        match as RegExpMatch,
      ),
    );
  }

  if (foundMacroish && result.contains('tnote')) {
    result = InlineRun.replace(
      result,
      inlineFootnoteMacroRx,
      (match) =>
          _convertFootnoteMacro(node, block, doc, compat, match as RegExpMatch),
    );
  }

  return result;
}

/// Converts one xref macro match. Part of [subMacros].
String _convertXrefMacro(
  AbstractNode node,
  AbstractBlock block,
  Document doc,
  Map<String, String> docAttrs,
  bool compat,
  RegExpMatch match,
) {
  // honor the escape
  if (match.group(0)!.startsWith(rs)) {
    return match.group(0)!.substring(1);
  }

  var attrs = <String, String>{};
  var refid = match.group(1);
  String? linkText;
  var macro = false;
  if (refid != null) {
    if (refid.contains(',')) {
      final idx = refid.indexOf(',');
      linkText = trimLeftAscii(refid.substring(idx + 1));
      if (linkText.isEmpty) linkText = null;
      refid = refid.substring(0, idx);
    }
  } else {
    macro = true;
    refid = match.group(2)!;
    linkText = match.group(3);
    if (linkText != null) {
      if (linkText.contains(rSb)) {
        linkText = linkText.replaceAll(escRSb, rSb);
      }
      // NOTE if an equals sign (=) is present, extract attributes from
      // link text
      if (!compat && _holdsAttributes(linkText)) {
        final extracted = extractAttributesFromText(node, linkText);
        linkText = extracted.text;
        attrs = extracted.attributes;
      }
    }
  }

  String? path;
  String? fragment;
  String? target;
  String? src2src;
  if (compat) {
    fragment = refid;
  } else {
    final hashIdx = refid.indexOf('#');
    // NOTE when the hash is the first character, the character before it
    // wraps around to the last character (as in Asciidoctor).
    final charBeforeHash = hashIdx == -1
        ? null
        : hashIdx == 0
        ? refid[refid.length - 1]
        : refid[hashIdx - 1];
    if (hashIdx != -1 && charBeforeHash != '&') {
      if (hashIdx > 0) {
        final fragmentLen = refid.length - 1 - hashIdx;
        if (fragmentLen > 0) {
          path = refid.substring(0, hashIdx);
          fragment = refid.substring(hashIdx + 1, hashIdx + 1 + fragmentLen);
        } else {
          path = refid.substring(0, refid.length - 1);
        }
        if (macro) {
          if (path.endsWith('.adoc')) {
            src2src = path = path.substring(0, path.length - 5);
          } else if (!Helpers.hasExtname(path)) {
            src2src = path;
          }
        } else if (_endsWithAny(path, asciidocExtensions.keys)) {
          final dotIdx = path.lastIndexOf('.');
          src2src = path = path.substring(0, dotIdx);
        } else {
          src2src = path;
        }
      } else {
        target = refid;
        fragment = refid.substring(1);
      }
    } else if (macro) {
      if (refid.endsWith('.adoc')) {
        src2src = path = refid.substring(0, refid.length - 5);
      } else if (Helpers.hasExtname(refid)) {
        path = refid;
      } else {
        fragment = refid;
      }
    } else {
      // rubocop:disable Lint/DuplicateBranch
      fragment = refid;
    }
  }

  // handles: #id
  if (target != null) {
    refid = fragment;
    _logPossibleInvalidReference(node, doc, refid!);
  } else if (path != null) {
    // handles: path#, path#id, path.adoc#, path.adoc#id, or path.adoc (xref
    // macro only)
    // the referenced path is the current document, or its contents have
    // been included in the current document
    if (src2src != null &&
        (docAttrs['docname'] == path || doc.catalog.includes[path] == true)) {
      if (fragment != null) {
        refid = fragment;
        path = null;
        target = '#$fragment';
        _logPossibleInvalidReference(node, doc, refid);
      } else {
        refid = null;
        path = null;
        target = '#';
      }
    } else {
      refid = path;
      final prefix = docAttrs['relfileprefix'] ?? '';
      final suffix = src2src != null
          ? docAttrs['relfilesuffix'] ?? doc.outfilesuffix ?? ''
          : '';
      path = '$prefix$path$suffix';
      if (fragment != null) {
        refid = '$refid#$fragment';
        target = '$path#$fragment';
      } else {
        target = path;
      }
    }
    // handles: id (in compat mode or when natural xrefs are disabled)
  } else if (compat || !Compliance.naturalXrefs) {
    refid = fragment;
    target = '#$fragment';
    _logPossibleInvalidReference(node, doc, refid!);
    // handles: id
  } else if (doc.catalog.refs.containsKey(fragment)) {
    refid = fragment;
    target = '#$fragment';
    // handles: Node Title or Reference Text
    // do reverse lookup on fragment if not a known ID and resembles
    // reftext (contains a space or uppercase char)
  } else {
    final resolved = (fragment!.contains(' ') || downcase(fragment) != fragment)
        ? doc.resolveId(fragment)
        : null;
    if (resolved != null) {
      refid = resolved;
      fragment = resolved;
      target = '#$resolved';
    } else {
      refid = fragment;
      target = '#$fragment';
      node.logger.info('possible invalid reference: $refid');
    }
  }
  void put(String key, String? value) {
    if (value == null) {
      attrs.remove(key);
    } else {
      attrs[key] = value;
    }
  }

  put('path', path);
  put('fragment', fragment);
  put('refid', refid);
  return InlineRun.emit(
    Inline(
      block,
      InlineContext.anchor,
      text: linkText,
      type: 'xref',
      target: target,
      attributes: attrs,
    ),
  );
}

/// Converts one footnote macro match. Part of [subMacros].
String _convertFootnoteMacro(
  AbstractNode node,
  AbstractBlock block,
  Document doc,
  bool compat,
  RegExpMatch match,
) {
  // honor the escape
  if (match.group(0)!.startsWith(rs)) {
    return match.group(0)!.substring(1);
  }
  if (doc.deferFootnotes) return '';

  String? id;
  String? content;
  // footnoteref
  if (match.group(1) != null) {
    if (match.group(3) == null) return match.group(0)!;
    final parts = _splitLimit(match.group(3)!, ',', 2);
    id = parts[0];
    content = parts.length > 1 ? parts[1] : null;
    if (!compat) {
      node.logger.warn(
        'found deprecated footnoteref macro: ${match.group(0)}; '
        'use footnote macro with target instead',
      );
    }
    // footnote
  } else {
    id = match.group(2);
    content = match.group(3);
  }

  String? index;
  String? type;
  String? target;
  var finalId = id;
  var finalContent = content;
  if (id != null) {
    Footnote? footnote;
    for (final candidate in doc.footnotes) {
      if (candidate.id == id) {
        footnote = candidate;
        break;
      }
    }
    if (footnote != null) {
      index = footnote.index;
      finalContent = footnote.text;
      type = 'xref';
      target = id;
      finalId = null;
    } else if (content != null) {
      finalContent = restorePassthroughs(
        node,
        normalizeText(
          content,
          normalizeWhitespace: true,
          unescapeClosingSquareBrackets: true,
        ),
      );
      index = doc.counter('footnote-number');
      doc.registerFootnote(Footnote(index, id, finalContent));
      type = 'ref';
      target = null;
    } else {
      node.logger.warn('invalid footnote reference: $id');
      type = 'xref';
      target = id;
      finalContent = id;
      finalId = null;
    }
  } else if (content != null) {
    finalContent = restorePassthroughs(
      node,
      normalizeText(
        content,
        normalizeWhitespace: true,
        unescapeClosingSquareBrackets: true,
      ),
    );
    index = doc.counter('footnote-number');
    doc.registerFootnote(Footnote(index, id, finalContent));
    type = null;
    target = null;
  } else {
    return match.group(0)!;
  }
  return InlineRun.emit(
    Inline(
      block,
      InlineContext.footnote,
      text: finalContent,
      attributes: {'index': ?index},
      id: finalId,
      target: target,
      type: type,
    ),
  );
}

/// Substitutes post replacements (hard line breaks) in [text].
///
/// Port of `Substitutors#sub_post_replacements`.
String subPostReplacements(AbstractNode node, String text) {
  final docAttrs = _documentOf(node).attributes;
  if (node.attributes.containsKey('hardbreaks-option') ||
      docAttrs.containsKey('hardbreaks-option')) {
    final lines = text.split(lf);
    if (lines.length < 2) return text;
    final last = lines.removeLast();
    final converted = <String>[
      for (final line in lines)
        InlineRun.emit(
          Inline(
            _blockOf(node),
            InlineContext.lineBreak,
            text: line.endsWith(hardLineBreak)
                ? line.substring(0, line.length - 2)
                : line,
            type: 'line',
          ),
        ),
      last,
    ];
    return converted.join(lf);
  } else if (text.contains(plus) && text.contains(hardLineBreak)) {
    return InlineRun.replace(
      text,
      hardLineBreakRx,
      (match) => InlineRun.emit(
        Inline(
          _blockOf(node),
          InlineContext.lineBreak,
          text: match.group(1),
          type: 'line',
        ),
      ),
    );
  } else {
    return text;
  }
}

/// Applies verbatim substitutions on [source] (for use when highlighting
/// is disabled). When [processCallouts] is set, callout marks are
/// substituted as well.
///
/// Port of `Substitutors#sub_source`.
String subSource(
  AbstractNode node,
  String source, {
  required bool processCallouts,
}) => processCallouts
    ? subCallouts(node, subSpecialchars(source))
    : subSpecialchars(source);

/// Substitutes callout source references in [text].
///
/// Port of `Substitutors#sub_callouts`.
String subCallouts(AbstractNode node, String text) {
  final doc = _documentOf(node);
  final lineComment = node.attr('line-comment');
  final pattern = lineComment != null
      ? calloutSourceRxMap[lineComment]
      : calloutSourceRx;
  var autonum = 0;
  return InlineRun.replace(text, pattern, (match) {
    // honor the escape
    if (match.group(2) != null) {
      // use sub since it might be behind a line comment
      return match.group(0)!.replaceFirst(rs, '');
    }
    final numeral = match.group(4) == '.' ? '${++autonum}' : match.group(4)!;
    final guard = match.group(1);
    return InlineRun.emit(
      Inline(
        _blockOf(node),
        InlineContext.callout,
        text: numeral,
        id: doc.callouts.readNextId(),
        attributes: {'guard': ?guard},
        xmlCommentGuard: guard == null && match.group(3) == '--',
      ),
    );
  });
}

/// Highlights (i.e., colorizes) the [source] code using the document's
/// syntax highlighter, if activated. Otherwise returns [source] with
/// verbatim substitutions applied.
///
/// When [processCallouts] is set, callout marks are extracted before
/// highlighting and restored after, so they don't confuse the highlighter.
///
/// Port of `Substitutors#highlight_source`.
String highlightSource(
  AbstractNode node,
  String source, {
  required bool processCallouts,
}) {
  var code = source;
  final doc = _documentOf(node);
  final syntaxHl = doc.syntaxHighlighter;
  // NOTE the call to highlight? is a defensive check since, normally, we
  // wouldn't arrive here unless it returns true
  if (syntaxHl == null || !syntaxHl.canHighlight) {
    return subSource(node, code, processCallouts: processCallouts);
  }
  final docAttrs = doc.attributes;
  Map<int, List<PendingCallout>>? calloutMarks;
  if (processCallouts) {
    final extracted = extractCallouts(node, code);
    code = extracted.source;
    calloutMarks = extracted.calloutMarks;
  }
  // NOTE (coderay parity gap): the shared CssMode/LineNumbersMode mapping is
  // lenient (unknown values map to inline), which matches pygments, but
  // CodeRay itself rejects unknown :css / :line_numbers values with an
  // error. Passing the raw strings through to the CodeRay backend so it can
  // validate them is not implemented.
  LineNumbersMode? linenumsMode;
  int? startLineNumber;
  if (node.hasOption('linenums')) {
    linenumsMode = LineNumbersMode.fromAttribute(
      docAttrs['${syntaxHl.name}-linenums-mode'],
    );
    startLineNumber = parseLeadingInt(node.attr('start', '1'));
    if (startLineNumber < 1) startLineNumber = 1;
  }
  final highlightLines = node.hasAttr('highlight')
      ? resolveLinesToHighlight(code, node.attr('highlight'), startLineNumber)
      : const <int>[];
  final result = syntaxHl.highlight(
    node as AbstractBlock,
    code,
    node.attr('language'),
    // The framework only reads the null/emptiness of this map (to derive
    // `hasCallouts`); the marks themselves travel separately below.
    callouts: (calloutMarks == null || calloutMarks.isEmpty)
        ? null
        : <int, String>{for (final lineno in calloutMarks.keys) lineno: ''},
    cssMode: CssMode.fromAttribute(docAttrs['${syntaxHl.name}-css']),
    highlightLines: highlightLines,
    numberLines: linenumsMode,
    startLineNumber: startLineNumber,
    style: docAttrs['${syntaxHl.name}-style'],
  );
  var highlighted = result.html;
  if (_passthroughsOf(node).isNotEmpty) {
    highlighted = InlineRun.replace(
      highlighted,
      highlightedPassSlotRx,
      (match) => '$passStart${match[1]}$passEnd',
    );
  }
  if (calloutMarks == null || calloutMarks.isEmpty) return highlighted;
  return restoreCallouts(node, highlighted, calloutMarks, result.sourceOffset);
}

/// Resolves the line numbers in [source] to highlight from [spec].
///
/// For example `highlight="1-5, !2, 10"` or `highlight=1-5;!2,10`.
/// [start] is the line number of the first line. Returns the unique, sorted
/// line numbers.
///
/// Port of `Substitutors#resolve_lines_to_highlight`.
List<int> resolveLinesToHighlight(String source, String? spec, [int? start]) {
  if (spec == null) return <int>[];
  var lines = <int>[];
  var specStr = spec;
  if (specStr.contains(' ')) specStr = specStr.replaceAll(' ', '');
  final entries = specStr.contains(',')
      ? splitDropTrailingEmpty(specStr, ',')
      : splitDropTrailingEmpty(specStr, ';');
  for (var entry in entries) {
    var negate = false;
    if (entry.startsWith('!')) {
      entry = entry.substring(1);
      negate = true;
    }
    final String? delim;
    if (entry.contains('..')) {
      delim = '..';
    } else if (entry.contains('-')) {
      delim = '-';
    } else {
      delim = null;
    }
    if (delim != null) {
      final idx = entry.indexOf(delim);
      final from = entry.substring(0, idx);
      final toStr = entry.substring(idx + delim.length);
      final int to;
      if (toStr.isEmpty) {
        to = '\n'.allMatches(source).length + 1;
      } else {
        final parsed = parseLeadingInt(toStr);
        to = parsed < 0 ? '\n'.allMatches(source).length + 1 : parsed;
      }
      final range = <int>[for (var i = parseLeadingInt(from); i <= to; i++) i];
      if (negate) {
        lines = lines.where((line) => !range.contains(line)).toList();
      } else {
        for (final line in range) {
          if (!lines.contains(line)) lines.add(line);
        }
      }
    } else if (negate) {
      lines.remove(parseLeadingInt(entry));
    } else {
      final line = parseLeadingInt(entry);
      if (!lines.contains(line)) lines.add(line);
    }
  }
  // If the start attribute is defined, then the lines to highlight
  // specified by the provided spec should be relative to the start value.
  final shift = start != null ? start - 1 : 0;
  if (shift != 0) {
    lines = lines.map((line) => line - shift).toList();
  }
  lines.sort();
  return lines;
}

/// A callout mark extracted from source: its `guard` (line-comment prefix,
/// if any), whether an XML comment guards it, and its `numeral`.
typedef PendingCallout = ({
  String? guard,
  bool xmlCommentGuard,
  String numeral,
});

/// Extracts the callout numbers from [source] to prepare it for syntax
/// highlighting.
///
/// Returns the cleaned source and the callout marks indexed by line number
/// (`null` when no callouts were found).
///
/// Port of `Substitutors#extract_callouts`.
({String source, Map<int, List<PendingCallout>>? calloutMarks}) extractCallouts(
  AbstractNode node,
  String source,
) {
  Map<int, List<PendingCallout>>? calloutMarks = <int, List<PendingCallout>>{};
  var autonum = 0;
  var lineno = 0;
  int? lastLineno;
  final lineComment = node.attr('line-comment');
  final pattern = lineComment != null
      ? calloutExtractRxMap[lineComment]
      : calloutExtractRx;
  // extract callout marks, indexed by line number
  final cleaned = source
      .split(lf)
      .map((line) {
        lineno++;
        return InlineRun.replace(line, pattern, (match) {
          // honor the escape
          if (match.group(2) != null) {
            // use sub since it might be behind a line comment
            return match.group(0)!.replaceFirst(rs, '');
          }
          final guard = match.group(1);
          final numeral = match.group(4) == '.'
              ? '${++autonum}'
              : match.group(4)!;
          (calloutMarks![lineno] ??= []).add((
            guard: guard,
            xmlCommentGuard: guard == null && match.group(3) == '--',
            numeral: numeral,
          ));
          lastLineno = lineno;
          return '';
        });
      })
      .join(lf);
  var result = cleaned;
  if (lastLineno != null) {
    if (lastLineno == lineno) result = '$result$lf';
  } else {
    calloutMarks = null;
  }
  return (source: result, calloutMarks: calloutMarks);
}

/// Restores the callout numbers in [calloutMarks] to the highlighted
/// [source], skipping [sourceOffset] preamble characters when given.
///
/// Port of `Substitutors#restore_callouts`.
String restoreCallouts(
  AbstractNode node,
  String source,
  Map<int, List<PendingCallout>> calloutMarks, [
  int? sourceOffset,
]) {
  var preamble = '';
  var body = source;
  if (sourceOffset != null) {
    preamble = source.substring(0, sourceOffset);
    body = source.substring(sourceOffset);
  }
  final doc = _documentOf(node);
  final block = _blockOf(node);
  var lineno = 0;
  return preamble +
      body
          .split(lf)
          .map((line) {
            lineno++;
            final conums = calloutMarks.remove(lineno);
            if (conums == null) return line;
            String conum(PendingCallout mark) => InlineRun.emit(
              Inline(
                block,
                InlineContext.callout,
                text: mark.numeral,
                id: doc.callouts.readNextId(),
                attributes: {'guard': ?mark.guard},
                xmlCommentGuard: mark.xmlCommentGuard,
              ),
            );
            return '$line${conums.map(conum).join(' ')}';
          })
          .join(lf);
}

/// Extracts the passthrough text from [text] for reinsertion after
/// processing.
///
/// Returns [text] with passthrough regions substituted with placeholders.
///
/// Port of `Substitutors#extract_passthroughs`.
String extractPassthroughs(AbstractNode node, String text) {
  final doc = _documentOf(node);
  final compatMode = doc.compatMode;
  final passthrus = _passthroughsOf(node);
  var result = text;
  if (text.contains('++') || text.contains(r'$$') || text.contains('ss:')) {
    result = InlineRun.replace(result, inlinePassMacroRx, (match) {
      final boundary = match.group(4);
      if (boundary != null) {
        // $$, ++, or +++
        // skip ++ in compat mode, handled as normal quoted text
        if (compatMode && boundary == '++') {
          final attrlist = match.group(2);
          final head = attrlist != null
              ? '${match.group(1) ?? ''}[$attrlist]${match.group(3)}'
              : '${match.group(1) ?? ''}${match.group(3)}';
          return '$head++${extractPassthroughs(node, match.group(5)!)}++';
        }

        final attrlist = match.group(2);
        final escapeCount = (match.group(3) ?? '').length;
        Map<String, String>? attributes;
        var oldBehavior = false;
        String? preceding;
        if (attrlist != null) {
          if (escapeCount > 0) {
            // NOTE we don't look for nested unconstrained pass macros
            final escapes = rs * (escapeCount - 1);
            return '${match.group(1) ?? ''}[$attrlist]$escapes'
                '$boundary${match.group(5)}$boundary';
          } else if (match.group(1) == rs) {
            preceding = '[$attrlist]';
          } else if (boundary == '++') {
            if (attrlist == 'x-') {
              oldBehavior = true;
              attributes = <String, String>{};
            } else if (attrlist.endsWith(' x-')) {
              oldBehavior = true;
              attributes = parseQuotedTextAttributes(
                node,
                attrlist.substring(0, attrlist.length - 3),
              );
            } else {
              attributes = parseQuotedTextAttributes(node, attrlist);
            }
          } else {
            attributes = parseQuotedTextAttributes(node, attrlist);
          }
        } else if (escapeCount > 0) {
          // NOTE we don't look for nested unconstrained pass macros
          return '${rs * (escapeCount - 1)}$boundary${match.group(5)}$boundary';
        }
        final subs = boundary == '+++' ? <Sub>[] : List<Sub>.of(basicSubs);

        final passthruKey = passthrus.length;
        final text = match.group(5)!;
        if (attributes != null) {
          if (oldBehavior) {
            passthrus.add(
              Passthrough(
                text,
                subs: normalSubs,
                type: 'monospaced',
                attributes: attributes,
              ),
            );
          } else {
            passthrus.add(
              Passthrough(
                text,
                subs: subs,
                type: 'unquoted',
                attributes: attributes,
              ),
            );
          }
        } else {
          passthrus.add(Passthrough(text, subs: subs));
        }
        return '${preceding ?? ''}$passStart$passthruKey$passEnd';
      } else {
        // pass:[]
        // NOTE we don't look for nested pass:[] macros
        // honor the escape
        if (match.group(6) == rs) {
          return match.group(0)!.substring(1);
        }
        final subs = match.group(7);
        final passthruKey = passthrus.length;
        final text = normalizeText(
          match.group(8)!,
          unescapeClosingSquareBrackets: true,
        );
        passthrus.add(
          Passthrough(
            text,
            subs: subs != null ? resolvePassSubs(node, subs) : null,
          ),
        );
        return '$passStart$passthruKey$passEnd';
      }
    });
  }

  final passEntry = inlinePassRx[compatMode]!;
  if (result.contains(passEntry.delimiter) ||
      (passEntry.endTrim != null && result.contains(passEntry.endTrim!))) {
    result = InlineRun.replace(result, passEntry.pattern, (match) {
      var preceding = match.group(1)!;
      final attrlist = match.group(4) ?? match.group(3);
      final escaped = match.group(5) != null;
      final quotedText = match.group(6)!;
      final formatMark = match.group(7)!;
      final content = match.group(8)!;

      var oldBehavior = compatMode;
      var oldBehaviorForced = false;
      if (!compatMode &&
          attrlist != null &&
          (attrlist == 'x-' || attrlist.endsWith(' x-'))) {
        oldBehavior = true;
        oldBehaviorForced = true;
      }

      Map<String, String>? attributes;
      if (attrlist != null) {
        if (escaped) {
          // honor the escape of the formatting mark
          return '$preceding[$attrlist]${quotedText.substring(1)}';
        } else if (preceding == rs) {
          // honor the escape of the attributes
          if (oldBehaviorForced && formatMark == '`') {
            return '$preceding[$attrlist]$quotedText';
          }
          preceding = '[$attrlist]';
        } else if (oldBehaviorForced) {
          attributes = attrlist == 'x-'
              ? <String, String>{}
              : parseQuotedTextAttributes(
                  node,
                  attrlist.substring(0, attrlist.length - 3),
                );
        } else {
          attributes = parseQuotedTextAttributes(node, attrlist);
        }
      } else if (escaped) {
        // honor the escape of the formatting mark
        return '$preceding${quotedText.substring(1)}';
      } else if (compatMode && preceding == rs) {
        return quotedText;
      }

      final passthruKey = passthrus.length;
      if (compatMode) {
        passthrus.add(
          Passthrough(
            content,
            subs: basicSubs,
            attributes: attributes,
            type: 'monospaced',
          ),
        );
      } else if (attributes != null) {
        if (oldBehavior) {
          passthrus.add(
            Passthrough(
              content,
              subs: formatMark == '`' ? basicSubs : normalSubs,
              attributes: attributes,
              type: 'monospaced',
            ),
          );
        } else {
          passthrus.add(
            Passthrough(
              content,
              subs: basicSubs,
              attributes: attributes,
              type: 'unquoted',
            ),
          );
        }
      } else {
        passthrus.add(Passthrough(content, subs: basicSubs));
      }

      return '$preceding$passStart$passthruKey$passEnd';
    });
  }

  // NOTE we need to do the stem in a subsequent step to allow it to be
  // escaped by the former
  if (result.contains(':') &&
      (result.contains('stem:') || result.contains('math:'))) {
    result = InlineRun.replace(result, inlineStemMacroRx, (match) {
      // honor the escape
      if (match.group(0)!.startsWith(rs)) {
        return match.group(0)!.substring(1);
      }

      var type = match.group(1)!;
      if (type == 'stem') {
        type = stemTypeAliases[doc.attributes['stem']] ?? 'asciimath';
      }
      final subs = match.group(2);
      var content = normalizeText(
        match.group(3)!,
        unescapeClosingSquareBrackets: true,
      );
      // NOTE drop enclosing $ signs around latexmath for backwards
      // compatibility with AsciiDoc.py
      if (type == 'latexmath' &&
          content.startsWith(r'$') &&
          content.endsWith(r'$')) {
        content = content.substring(1, content.length - 1);
      }
      final resolvedSubs = subs != null
          ? resolvePassSubs(node, subs, 'stem macro')
          : (doc.basebackend('html') ? basicSubs : null);
      final passthruKey = passthrus.length;
      passthrus.add(Passthrough(content, subs: resolvedSubs, type: type));
      return '$passStart$passthruKey$passEnd';
    });
  }

  return result;
}

/// Restores the passthrough text by reinserting it into the placeholder
/// positions in [text].
///
/// Port of `Substitutors#restore_passthroughs`.
String restorePassthroughs(AbstractNode node, String text) {
  final passthrus = _passthroughsOf(node);
  return InlineRun.replace(text, passSlotRx, (match) {
    final slot = int.parse(match.group(1)!);
    final pass = slot < passthrus.length ? passthrus[slot] : null;
    if (pass != null) {
      var subbedText = applySubs(node, pass.text, pass.subs);
      final type = pass.type;
      if (type != null) {
        final attributes = pass.attributes;
        subbedText = InlineRun.emit(
          Inline(
            _blockOf(node),
            InlineContext.quoted,
            text: subbedText,
            type: type,
            id: attributes?['id'],
            attributes: attributes,
          ),
        );
      }
      return subbedText.contains(passStart)
          ? restorePassthroughs(node, subbedText)
          : subbedText;
    } else {
      node.logger.error('unresolved passthrough detected: $text');
      return '??pass??';
    }
  });
}

/// Resolves the comma-delimited [subs] list against the possible options.
///
/// [scope] says where the list is written; [defaults] seeds incremental
/// substitutions; [subject] names the subject in log messages. Returns
/// the resolved substitutions, or `null` if no subs are found. Names that
/// are not substitutions allowed in [scope] are dropped with a warning.
///
/// Port of `Substitutors#resolve_subs`.
List<Sub>? resolveSubs(
  AbstractNode node,
  String? subs, [
  SubsScope scope = SubsScope.block,
  List<Sub>? defaults,
  String? subject,
]) {
  if (subs == null || subs.isEmpty) return null;
  // QUESTION should we store candidates as a Set instead of an Array?
  List<String>? candidates;
  var source = subs;
  if (source.contains(' ')) source = source.replaceAll(' ', '');
  final modifiersPresent = subModifierSniffRx.hasMatch(source);
  for (var key in splitDropTrailingEmpty(source, ',')) {
    String? modifierOperation;
    if (modifiersPresent) {
      final first = key.isNotEmpty ? key[0] : '';
      if (first == '+') {
        modifierOperation = 'append';
        key = key.substring(1);
      } else if (first == '-') {
        modifierOperation = 'remove';
        key = key.substring(1);
      } else if (key.endsWith('+')) {
        modifierOperation = 'prepend';
        key = key.substring(0, key.length - 1);
      }
    }
    final List<String> resolvedKeys;
    // special case to disable callouts for inline subs
    if (scope == SubsScope.inline && (key == 'verbatim' || key == 'v')) {
      resolvedKeys = _names(basicSubs);
    } else if (subGroups[key] case final group?) {
      resolvedKeys = _names(group);
    } else if (scope == SubsScope.inline &&
        key.length == 1 &&
        subHints.containsKey(key)) {
      final resolvedKey = subHints[key]!;
      resolvedKeys = switch (subGroups[resolvedKey]) {
        final group? => _names(group),
        null => [resolvedKey],
      };
    } else {
      resolvedKeys = [key];
    }

    if (modifierOperation != null) {
      candidates ??= defaults != null ? _names(defaults) : <String>[];
      switch (modifierOperation) {
        case 'append':
          candidates.addAll(resolvedKeys);
        case 'prepend':
          candidates = [...resolvedKeys, ...candidates];
        case 'remove':
          candidates = candidates
              .where((candidate) => !resolvedKeys.contains(candidate))
              .toList();
      }
    } else {
      (candidates ??= <String>[]).addAll(resolvedKeys);
    }
  }
  final found = candidates;
  if (found == null) return null;
  // weed out invalid options and remove duplicates (order is preserved;
  // first occurrence wins)
  final resolved = <Sub>[];
  final invalid = <String>[];
  for (final candidate in found) {
    final sub = Sub.tryParse(candidate);
    if (sub == null || !scope.allows(sub)) {
      invalid.add(candidate);
    } else if (!resolved.contains(sub)) {
      resolved.add(sub);
    }
  }
  if (invalid.isNotEmpty) {
    node.logger.warn(
      'invalid substitution type${invalid.length > 1 ? 's' : ''}'
      '${subject != null ? ' for ' : ''}${subject ?? ''}: '
      "${invalid.join(', ')}",
    );
  }
  return resolved;
}

List<String> _names(List<Sub> subs) => [for (final sub in subs) sub.asciidoc];

/// Resolves [subs] for the block type.
///
/// Port of `Substitutors#resolve_block_subs`.
List<Sub>? resolveBlockSubs(
  AbstractNode node,
  String? subs,
  List<Sub>? defaults,
  String? subject,
) => resolveSubs(node, subs, SubsScope.block, defaults, subject);

/// Resolves [subs] for the inline type (passthrough macro subject).
///
/// Port of `Substitutors#resolve_pass_subs`.
List<Sub>? resolvePassSubs(
  AbstractNode node,
  String? subs, [
  String subject = 'passthrough macro',
]) => resolveSubs(node, subs, SubsScope.inline, null, subject);

/// Expands all groups in the comma-delimited [subs] and returns the
/// result, or `null` if no subs are resolved (or [subs] is `none`).
///
/// [subject] names the subject in log messages.
///
/// Port of `Substitutors#expand_subs`.
List<Sub>? expandSubs(AbstractNode node, String subs, [String? subject]) {
  if (subs == 'none') return null;
  return resolveSubs(node, subs, SubsScope.inline, null, subject);
}

/// Commits the requested substitutions to [node].
///
/// Looks for an attribute named `subs`. If present, resolves substitutions
/// from its value and assigns them to [node]; otherwise uses [Block]'s
/// default subs, if specified, or selects defaults based on the content
/// model. Returns the assigned subs when the content model needs none.
///
/// Port of `Substitutors#commit_subs`.
List<Sub>? commitSubs(AbstractBlock node) {
  final defaultSubs = node is Block ? node.defaultSubs : null;
  late List<Sub> effective;
  if (defaultSubs == null) {
    switch (node.contentModel) {
      case ContentModel.simple:
        effective = normalSubs;
      case ContentModel.verbatim:
        effective = node.context == BlockContext.verse
            ? normalSubs
            : verbatimSubs;
      case ContentModel.raw:
        // TODO make pass subs a compliance setting; AsciiDoc.py performs
        // :attributes and :macros on a pass block
        effective = node.context == BlockContext.stem ? basicSubs : noSubs;
      case ContentModel.compound || ContentModel.empty || ContentModel.skip:
        return node.subs;
    }
  } else {
    effective = List<Sub>.of(defaultSubs);
  }

  final customSubs = node.attributes['subs'];
  if (customSubs != null) {
    node.subs =
        resolveBlockSubs(node, customSubs, effective, node.context.asciidoc) ??
        [];
  } else {
    node.subs = List<Sub>.of(effective);
  }

  // QUESTION delegate this logic to a method?
  final doc = node.document;
  final syntaxHl = doc is Document ? doc.syntaxHighlighter : null;
  if (node.context == BlockContext.listing &&
      node.style == 'source' &&
      syntaxHl != null &&
      syntaxHl.canHighlight) {
    final idx = node.subs.indexOf(Sub.specialcharacters);
    if (idx != -1) node.subs[idx] = Sub.highlight;
  }

  return null;
}

/// Parses attributes in name or name=value format from a comma-separated
/// [attrlist] string.
///
/// [posattrs] names the positional attributes. [into] parses into an
/// existing map; [subInput] substitutes attributes before parsing;
/// [subResult] applies substitutions to single-quoted values; [unescapeInput]
/// unescapes square brackets before parsing. Returns an empty map if
/// [attrlist] is null or empty.
///
/// Port of `Substitutors#parse_attributes`.
Map<String, String> parseAttributes(
  AbstractNode node,
  String? attrlist, {
  List<String?> posattrs = const [],
  Map<String, String>? into,
  bool subInput = false,
  bool subResult = false,
  bool unescapeInput = false,
}) {
  if (attrlist == null || attrlist.isEmpty) return into ?? <String, String>{};
  var source = attrlist;
  if (unescapeInput) {
    source = normalizeText(
      source,
      normalizeWhitespace: true,
      unescapeClosingSquareBrackets: true,
    );
  }
  if (subInput && source.contains(attrRefHead)) {
    source = subAttributes(_documentOf(node), source);
  }
  // substitutions are only performed on attribute values if block is not
  // null
  final block = subResult ? _BlockSubsApplier(node) : null;
  final parsed = AttributeList(source, block).parse(posattrs);
  if (into != null) {
    into.addAll(parsed);
    return into;
  }
  return Map<String, String>.of(parsed);
}

/// Extracts attributes mixed with macro text.
///
/// If no attributes are detected aside from the first positional attribute,
/// and it matches [text], the original text is returned. [defaultText] is
/// returned as the text when no positional attribute is found.
///
/// Port of `Substitutors#extract_attributes_from_text`.
({String? text, Map<String, String> attributes}) extractAttributesFromText(
  AbstractNode node,
  String text, [
  String? defaultText,
]) {
  final attrlist = text.contains(lf) ? text.replaceAll(lf, ' ') : text;
  final attrs = Map<String, String>.of(
    AttributeList(attrlist, _BlockSubsApplier(node)).parse(),
  );
  final resolvedText = attrs['1'];
  if (resolvedText != null) {
    // NOTE if resolved text remains unchanged, clear attributes and
    // return unparsed text
    if (resolvedText == attrlist) {
      attrs.clear();
      return (text: text, attributes: attrs);
    }
    return (text: resolvedText, attributes: attrs);
  }
  return (text: defaultText, attributes: attrs);
}

/// Substitutes [value] into the `%s` placeholder of [format].
///
/// Port of `Substitutors#sub_placeholder` (an alias of `sprintf`; every
/// call site formats a single `%s` value).
String subPlaceholder(String format, String value) {
  const token = '\u0000';
  final escaped = format.replaceAll('%%', token);
  final idx = escaped.indexOf('%s');
  final substituted = idx == -1
      ? escaped
      : escaped.replaceRange(idx, idx + 2, value);
  return substituted.replaceAll(token, '%');
}

/// Parses the attributes defined on quoted (formatted) text.
///
/// [str] is space-separated roles or the id/role shorthand syntax (e.g.,
/// `#idname.role`). Returns the role and id attributes.
///
/// Port of `Substitutors#parse_quoted_text_attributes`.
Map<String, String> parseQuotedTextAttributes(AbstractNode node, String str) {
  // NOTE attributes are typically resolved after quoted text, so
  // substitute eagerly
  var text = str.contains(attrRefHead) ? subAttributes(node, str) : str;
  // for compliance, only consider first positional attribute (very
  // unlikely)
  if (text.contains(',')) text = text.substring(0, text.indexOf(','));
  text = text.trimAscii();
  if (text.isEmpty) {
    return <String, String>{};
  } else if ((text.startsWith('.') || text.startsWith('#')) &&
      Compliance.shorthandPropertySyntax) {
    final hashIdx = text.indexOf('#');
    final before = hashIdx == -1 ? text : text.substring(0, hashIdx);
    final after = hashIdx == -1 ? '' : text.substring(hashIdx + 1);
    final attrs = <String, String>{};
    if (after.isEmpty) {
      if (before.length > 1) {
        attrs['role'] = trimLeftAscii(before.replaceAll('.', ' '));
      }
    } else {
      final dotIdx = after.indexOf('.');
      final id = dotIdx == -1 ? after : after.substring(0, dotIdx);
      final roles = dotIdx == -1 ? '' : after.substring(dotIdx + 1);
      if (id.isNotEmpty) attrs['id'] = id;
      if (roles.isEmpty) {
        if (before.length > 1) {
          attrs['role'] = trimLeftAscii(before.replaceAll('.', ' '));
        }
      } else if (before.length > 1) {
        attrs['role'] = trimLeftAscii('$before.$roles'.replaceAll('.', ' '));
      } else {
        attrs['role'] = roles.replaceAll('.', ' ');
      }
    }
    return attrs;
  } else {
    return {'role': text};
  }
}

/// Normalizes [text] to prepare it for parsing.
///
/// When [normalizeWhitespace] is set, surrounding whitespace is stripped
/// and newlines are folded. When [unescapeClosingSquareBrackets] is set,
/// escaped closing square brackets are unescaped.
///
/// Port of `Substitutors#normalize_text`.
String normalizeText(
  String text, {
  bool normalizeWhitespace = false,
  bool unescapeClosingSquareBrackets = false,
}) {
  var result = text;
  if (result.isNotEmpty) {
    if (normalizeWhitespace) {
      result = result.trimAscii().replaceAll(lf, ' ');
    }
    if (unescapeClosingSquareBrackets && result.contains(rSb)) {
      result = result.replaceAll(escRSb, rSb);
    }
  }
  return result;
}

/// Splits CSV [str], ignoring commas inside double-quoted values.
///
/// Port of `Substitutors#split_simple_csv`.
List<String> splitSimpleCsv(String str) {
  if (str.isEmpty) {
    return <String>[];
  } else if (str.contains('"')) {
    final values = <String>[];
    var accum = StringBuffer();
    var quoteOpen = false;
    for (final c in str.split('')) {
      if (c == ',') {
        if (quoteOpen) {
          accum.write(c);
        } else {
          values.add(accum.toString().trimAscii());
          accum = StringBuffer();
        }
      } else if (c == '"') {
        quoteOpen = !quoteOpen;
      } else {
        accum.write(c);
      }
    }
    values.add(accum.toString().trimAscii());
    return values;
  } else {
    return splitDropTrailingEmpty(
      str,
      ',',
    ).map((item) => item.trimAscii()).toList();
  }
}

/// Matches a URL that ends with a character reference (`&gt;`).
final RegExp _endsWithCharRefName = RegExp(r'&(?:[a-z]+|#\d+);$');

/// Matches the markup of an element the substitutions already converted.
final RegExp _convertedMarkupRx = RegExp('<[^>]*>');

/// Whether the text of a link or cross reference holds attributes: it has
/// an equals sign outside the markup of the elements converted in it
/// already (an icon's `<img src="data:...">` is not an attribute list:
/// #4075).
bool _holdsAttributes(String text) =>
    text.contains('=') &&
    (!text.contains('<') ||
        text.replaceAll(_convertedMarkupRx, '').contains('='));
