/// Substitutions applied to lines of AsciiDoc text.
///
/// Port of `lib/asciidoctor/substitutors.rb`.
///
/// Ruby's `Substitutors` is a mixin (`self` is the block or document being
/// substituted). The port expresses it as top-level functions that take the
/// node explicitly as the first parameter (the explicit-param seam style used
/// by `reader.dart` and `highlight/`):
///
/// * Functions whose Ruby method uses `self` take an [AbstractNode] first
///   (e.g. [applySubs], [subQuotes], [subMacros]); the document is derived
///   from the node exactly as Ruby reads `@document`.
/// * Pure functions take no node (e.g. [subSpecialchars], [subReplacements],
///   [normalizeText], [splitSimpleCsv]).
/// * Ruby symbols become strings (`:quotes` -> `'quotes'`, `:highlight` ->
///   `'highlight'`); substitution-type constants keep their Ruby names in
///   camelCase ([normalSubs], [basicSubs], ...).
///
/// Main-module constants consumed here ([intrinsicAttributes], [quoteSubs],
/// [replacements], [hardLineBreak], [stemTypeAliases], [asciidocExtensions],
/// the compliance flags) live in `constants.dart`. All regular expressions
/// reused from `rx.dart` are imported, never redefined.
///
/// TEMP-SEAMs (missing collaborator APIs worked around privately; each is
/// marked at the use site and listed for the merger):
///
/// * Node/document API surface: every function requires a real [Document]
///   behind the node ([_documentOf] throws a [StateError] otherwise) because
///   [NodeDocument] does not expose `register`, `resolveId`, `footnotes`,
///   `outfilesuffix`, attribute locking, extensions or the syntax
///   highlighter. The sibling merger replaces these casts with interface
///   methods when they land.
/// * Passthrough locking (`@passthroughs_locked`) has no home on
///   [AbstractNode]; it is kept in a private [Expando].
/// * `{set:...}` attribute assignments replicate `Parser.store_attribute`
///   ([_storeAttribute]) and the value-substitution half of
///   `Document#set_attribute` (which routes through `Document`'s private
///   substitutor stubs that this wave cannot fill from here).
/// * Custom inline macros consult `Document.extensions` (ported); syntax
///   highlighting (syntax-highlighter wave) is a loud seam: a non-null
///   `Document.syntaxHighlighter` throws [UnimplementedError] in the
///   highlight path.
/// * [NodeDocument]/[NodeLogger] expose no severity gate, so the Ruby
///   `logger.info?` guards are not replicated ([_logPossibleInvalidReference]
///   always logs on a missed reference). The default logger drops info
///   messages, matching Ruby's default level.
/// * [AttributeList] results carry integer positional keys in Ruby; Dart
///   [Inline] attributes only accept strings, so [_stringMap] drops the
///   integer keys when constructing inline nodes (converters never read
///   them).
library;

import 'abstract_block.dart';
import 'abstract_node.dart';
import 'attribute_list.dart';
import 'block.dart';
import 'constants.dart';
import 'core_ext.dart';
import 'document.dart';
import 'extensions.dart';
import 'helpers.dart';
import 'highlight/highlight.dart';
import 'highlight/syntax_highlighter.dart';
import 'inline.dart';
import 'rx.dart';

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
const List<String> basicSubs = <String>['specialcharacters'];

/// Substitutions for header metadata and attribute assignments.
/// Port of `HEADER_SUBS`.
const List<String> headerSubs = <String>['specialcharacters', 'attributes'];

/// No substitutions. Port of `NO_SUBS`.
const List<String> noSubs = <String>[];

/// The default paragraph substitutions. Port of `NORMAL_SUBS`.
const List<String> normalSubs = <String>[
  'specialcharacters',
  'quotes',
  'attributes',
  'replacements',
  'macros',
  'post_replacements',
];

/// Substitutions for reference text. Port of `REFTEXT_SUBS`.
const List<String> reftextSubs = <String>[
  'specialcharacters',
  'quotes',
  'replacements',
];

/// Substitutions for verbatim blocks. Port of `VERBATIM_SUBS`.
const List<String> verbatimSubs = <String>['specialcharacters', 'callouts'];

/// Named substitution groups. Port of `SUB_GROUPS`.
const Map<String, List<String>> subGroups = <String, List<String>>{
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

/// Valid substitution names per context. Port of `SUB_OPTIONS`.
const Map<String, List<String>> subOptions = <String, List<String>>{
  'block': <String>[
    'none',
    'normal',
    'verbatim',
    'specialchars',
    'specialcharacters',
    'quotes',
    'attributes',
    'replacements',
    'macros',
    'post_replacements',
    'callouts',
  ],
  'inline': <String>[
    'none',
    'normal',
    'verbatim',
    'specialchars',
    'specialcharacters',
    'quotes',
    'attributes',
    'replacements',
    'macros',
    'post_replacements',
  ],
};

/// Cancel marker for a dropped line. Port of `CAN` (`\u0018`).
const String can = '\u0018';

/// Delete marker for a dropped empty line. Port of `DEL` (`\u007f`).
const String del = '\u007f';

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
const String rs = '\\';

/// A closing square bracket. Port of `R_SB`.
const String rSb = ']';

/// An escaped closing square bracket. Port of `ESC_R_SB`.
const String escRSb = '\\]';

/// A plus sign. Port of `PLUS`.
const String plus = '+';

/// Tracks the passthrough lock per node.
///
/// TEMP-SEAM: Ruby keeps this as `@passthroughs_locked` on the node; there
/// is no such field on [AbstractNode], so the lock lives here. Placeholders
/// can move around, so only the outermost substitution call clears them.
final Expando<bool> _passthroughsLocked = Expando<bool>('passthroughsLocked');

/// Returns the [Document] behind [node].
///
/// TEMP-SEAM: [NodeDocument] does not expose the members substitutors need
/// (`register`, `resolveId`, `footnotes`, `outfilesuffix`, attribute
/// locking, extensions, the syntax highlighter), so every function requires
/// a real document. Throws a [StateError] for foreign node implementations.
Document _documentOf(AbstractNode node) {
  final Object? doc = node is Document ? node : node.document;
  if (doc is! Document) {
    throw StateError(
      'Substitutors require the node to belong to a Document '
      '(got ${doc.runtimeType}).',
    );
  }
  return doc;
}

/// Returns [node] as a block, for constructing [Inline] children.
///
/// TEMP-SEAM: substitutors always run on block-level nodes in Ruby (the
/// mixin is included in section/block/document classes); a non-block node
/// falls back to its parent.
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

/// Renders [value] as Ruby string interpolation would (`null` becomes the
/// empty string, unlike Dart's `'null'`).
String _str(Object? value) => value?.toString() ?? '';

/// Drops the non-string (positional integer) keys from [attrs].
///
/// TEMP-SEAM: Ruby attribute lists carry 1-based integer keys that travel
/// into [Inline] attributes; Dart inline attributes are
/// `Map<String, Object?>` and converters never read the integer keys.
Map<String, Object?> _stringMap(Map<Object, Object?> attrs) {
  final result = <String, Object?>{};
  for (final entry in attrs.entries) {
    final key = entry.key;
    if (key is String) result[key] = entry.value;
  }
  return result;
}

/// Whether [value] ends with any of [suffixes].
bool _endsWithAny(String value, Iterable<String> suffixes) {
  for (final suffix in suffixes) {
    if (value.endsWith(suffix)) return true;
  }
  return false;
}

/// Splits [source] on [separator] into at most [limit] parts, keeping
/// trailing empty fields, like Ruby's `String#split` with a limit.
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
/// TEMP-SEAM: Ruby guards this with `logger.info?`, but [NodeLogger] exposes
/// no severity gate, so the message is always emitted on a miss. The default
/// logger drops info messages, matching Ruby's default level.
void _logPossibleInvalidReference(
  AbstractNode node,
  Document doc,
  String refid,
) {
  final refs = doc.catalog['refs'];
  if (!isTruthy(refs is Map<String, Object?> ? refs[refid] : null)) {
    node.logger.info('possible invalid reference: $refid');
  }
}

/// Applies [SubsApplier] substitutions on behalf of [node].
///
/// [AttributeList] calls this for single-quoted values, mirroring Ruby
/// passing the block itself (`AttributeList.new attrlist, self`).
final class _BlockSubsApplier implements SubsApplier {
  /// Creates an applier delegating to [node].
  _BlockSubsApplier(this._node);

  final AbstractNode _node;

  @override
  String applySubs(String value) => _applySubsString(_node, value);
}

/// Applies normal substitutions to [value] on behalf of [node].
String _applySubsString(AbstractNode node, String value) =>
    applySubs(node, value, normalSubs) as String;

/// Applies the specified substitutions to the text.
///
/// [text] is the [String] or line [List] to process; it must not be `null`.
/// [subs] are the substitutions to perform (defaults to [normalSubs]); a
/// `null` [subs] returns [text] unchanged. Returns a [String] or a
/// `List<String>` to match the type of [text].
///
/// Port of `Substitutors#apply_subs`.
Object? applySubs(
  AbstractNode node,
  Object? text, [
  List<String>? subs = normalSubs,
]) {
  final List<String> effectiveSubs = subs ?? normalSubs;
  final bool isMultiline;
  String subject;
  if (text is List<Object?>) {
    if (text.isEmpty) return text;
    isMultiline = true;
    subject = (text.length > 1 && isTruthy(text[1]))
        ? text.join(lf)
        : text[0] as String;
  } else if (text is String) {
    if (text.isEmpty) return text;
    isMultiline = false;
    subject = text;
  } else {
    throw StateError('applySubs: text must be a String or a List');
  }
  // NOTE `subs == null` (rather than the defaulted list) returns [text]
  // unchanged, mirroring `return text if text.empty? || !subs`.
  if (subs == null) return text;

  List<Map<String, Object?>>? passthrus;
  var clearPassthrus = false;
  if (effectiveSubs.contains('macros')) {
    subject = extractPassthroughs(node, subject);
    if (node.passthroughs.isNotEmpty) {
      passthrus = node.passthroughs;
      // NOTE placeholders can move around, so we can only clear in the
      // outermost substitution call
      if (!isTruthy(_passthroughsLocked[node])) {
        _passthroughsLocked[node] = true;
        clearPassthrus = true;
      }
    }
  }

  for (final type in effectiveSubs) {
    switch (type) {
      case 'specialcharacters':
        subject = subSpecialchars(subject);
      case 'quotes':
        subject = subQuotes(node, subject);
      case 'attributes':
        if (subject.contains(attrRefHead)) {
          subject = subAttributes(node, subject);
        }
      case 'replacements':
        subject = subReplacements(subject);
      case 'macros':
        subject = subMacros(node, subject);
      case 'highlight':
        subject = highlightSource(
          node,
          subject,
          effectiveSubs.contains('callouts'),
        );
      case 'callouts':
        if (!effectiveSubs.contains('highlight')) {
          subject = subCallouts(node, subject);
        }
      case 'post_replacements':
        subject = subPostReplacements(node, subject);
      default:
        node.logger.warn('unknown substitution type $type');
    }
  }

  if (passthrus != null) {
    subject = restorePassthroughs(node, subject);
    if (clearPassthrus) {
      passthrus.clear();
      _passthroughsLocked[node] = false;
    }
  }

  return isMultiline ? subject.split(lf) : subject;
}

/// Applies normal substitutions to [text].
///
/// Port of `Substitutors#apply_normal_subs`.
Object? applyNormalSubs(AbstractNode node, Object? text) =>
    applySubs(node, text, normalSubs);

/// Applies header substitutions (for header metadata and attribute
/// assignments) to [text].
///
/// Port of `Substitutors#apply_header_subs`.
Object? applyHeaderSubs(AbstractNode node, Object? text) =>
    applySubs(node, text, headerSubs);

/// Applies title substitutions to [text].
///
/// Port of `Substitutors#apply_title_subs` (an alias of `apply_subs`).
Object? applyTitleSubs(
  AbstractNode node,
  Object? text, [
  List<String>? subs = normalSubs,
]) => applySubs(node, text, subs);

/// Applies reftext substitutions to [text].
///
/// Port of `Substitutors#apply_reftext_subs`.
Object? applyReftextSubs(AbstractNode node, Object? text) =>
    applySubs(node, text, reftextSubs);

/// Substitutes special characters (i.e., encodes XML) in [text].
///
/// The special characters `<`, `&` and `>` are replaced with `&lt;`,
/// `&amp;` and `&gt;`, respectively.
///
/// Port of `Substitutors#sub_specialchars`.
String subSpecialchars(String text) {
  if (text.contains('>') || text.contains('&') || text.contains('<')) {
    return text.replaceAllMapped(
      specialCharsRx,
      (match) => specialCharsTr[match.group(0)]!,
    );
  }
  return text;
}

/// Substitutes special characters (i.e., encodes XML) in [text].
///
/// Port of `Substitutors#sub_specialcharacters` (an alias of
/// `sub_specialchars`).
String subSpecialcharacters(String text) => subSpecialchars(text);

/// Substitutes quoted text (emphasis, strong, monospaced, etc.) in [text].
///
/// Port of `Substitutors#sub_quotes`.
String subQuotes(AbstractNode node, String text) {
  final compat = _documentOf(node).compatMode;
  if (!quotedTextSniffRx[compat]!.hasMatch(text)) return text;
  var result = text;
  for (final sub in quoteSubs[compat]!) {
    result = result.replaceAllMapped(
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
      return '$unescapedAttrs${_str(Inline(block, 'quoted', text: match.group(3), type: resolvedType).convert())}';
    }
    final attrlist = match.group(2);
    String? id;
    Map<String, Object?>? attributes;
    if (attrlist != null) {
      attributes = parseQuotedTextAttributes(node, attrlist);
      id = attributes['id'] as String?;
      if (resolvedType == 'mark') resolvedType = 'unquoted';
    }
    return '${match.group(1)}${_str(Inline(block, 'quoted', text: match.group(3), type: resolvedType, id: id, attributes: attributes).convert())}';
  } else {
    final attrlist = match.group(1);
    String? id;
    Map<String, Object?>? attributes;
    if (attrlist != null) {
      attributes = parseQuotedTextAttributes(node, attrlist);
      id = attributes['id'] as String?;
      if (resolvedType == 'mark') resolvedType = 'unquoted';
    }
    return _str(
      Inline(
        block,
        'quoted',
        text: match.group(2),
        type: resolvedType,
        id: id,
        attributes: attributes,
      ).convert(),
    );
  }
}

/// Substitutes attribute references in [text].
///
/// If an attribute referenced in the line is missing or undefined, the line
/// may be dropped based on the `attribute-missing` or `attribute-undefined`
/// setting, respectively. [attributeMissing] overrides the missing-attribute
/// handling; [dropLineSeverity] selects the log severity for a dropped line
/// (`'info'` or `'ignore'`).
///
/// Port of `Substitutors#sub_attributes`.
String subAttributes(
  AbstractNode node,
  String text, {
  String? attributeMissing,
  String dropLineSeverity = 'info',
}) {
  final doc = _documentOf(node);
  final docAttrs = doc.attributes;
  var drop = false;
  var dropLine = false;
  String? dropLineSeverityResolved;
  var dropEmptyLine = false;
  String? attributeUndefined;
  String? attributeMissingResolved;
  String resolveMissing() => attributeMissingResolved ??= _firstTruthy(
    attributeMissing,
    docAttrs['attribute-missing'],
    Compliance.attributeMissing,
  );
  final result = text.replaceAllMapped(attributeReferenceRx, (match) {
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
          if (isTruthy(value) ||
              (attributeUndefined ??= _firstTruthy(
                    docAttrs['attribute-undefined'],
                    null,
                    Compliance.attributeUndefined,
                  )) !=
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
          return _str(_counterWithArgs(doc, args));
      }
    } else if (docAttrs.containsKey(match.group(2)!.toLowerCase())) {
      return _str(docAttrs[match.group(2)!.toLowerCase()]);
    } else if (intrinsicAttributes.containsKey(match.group(2)!.toLowerCase())) {
      return intrinsicAttributes[match.group(2)!.toLowerCase()]!;
    } else {
      final key = match.group(2)!.toLowerCase();
      switch (resolveMissing()) {
        case 'drop':
          drop = true;
          dropEmptyLine = true;
          return del;
        case 'drop-line':
          final severity = dropLineSeverityResolved ??= dropLineSeverity;
          if (severity == 'info') {
            node.logger.info(
              'dropping line containing reference to missing attribute: $key',
            );
          }
          //elsif drop_line_severity == :warn
          //  logger.warn %(dropping line containing reference to missing attribute: #{key})
          drop = true;
          dropLine = true;
          return can;
        case 'warn':
          node.logger.warn('skipping reference to missing attribute: $key');
          return match.group(0)!;
        default: // 'skip'
          return match.group(0)!;
      }
    }
  });

  if (!drop) return result;
  // drop lines from text
  if (dropEmptyLine) {
    final lines = squeezeChar(result, del).split(lf);
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

/// Returns the first truthy option as a string, else [fallback.
///
/// Mirrors Ruby's `a || b || default` chains for attribute settings, where
/// only `null` and `false` are falsy.
String _firstTruthy(Object? first, Object? second, String fallback) {
  if (isTruthy(first)) return first.toString();
  if (isTruthy(second)) return second.toString();
  return fallback;
}

/// Runs the document counter with the `{counter:...}` [args].
Object? _counterWithArgs(Document doc, List<String> args) {
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
/// TEMP-SEAM: mirrors `Parser.store_attribute` plus the value-substitution
/// half of `Document#set_attribute`. The latter routes through `Document`'s
/// private substitutor stubs (which cannot be filled from this library), so
/// header substitutions are applied here and the value is assigned directly;
/// backend/doctype remapping and the value-size limit are not replicated.
/// Returns the (name, value) pair like the Ruby method.
(String, Object?) _storeAttribute(Document doc, String name, Object? value) {
  // TODO move processing of attribute value to utility method
  var attrName = name;
  Object? attrValue = value;
  if (attrName.endsWith('!')) {
    // a null value signals the attribute should be deleted (unset)
    attrName = chopLast(attrName);
    attrValue = null;
  } else if (attrName.startsWith('!')) {
    // a null value signals the attribute should be deleted (unset)
    attrName = attrName.substring(1);
    attrValue = null;
  }

  attrName = attrName.replaceAll(invalidAttributeNameCharsRx, '').toLowerCase();
  if (attrName == 'numbered') {
    attrName = 'sectnums';
  } else if (attrName == 'hardbreaks') {
    attrName = 'hardbreaks-option';
  } else if (attrName == 'showtitle') {
    _storeAttribute(doc, 'notitle', isTruthy(attrValue) ? null : '');
  }

  if (isTruthy(attrValue)) {
    var strValue = attrValue.toString();
    if (attrName == 'leveloffset') {
      // support relative leveloffset values
      if (strValue.startsWith('+')) {
        strValue =
            (rubyToInteger(doc.attr('leveloffset', 0)) +
                    rubyToInteger(strValue.substring(1)))
                .toString();
      } else if (strValue.startsWith('-')) {
        strValue =
            (rubyToInteger(doc.attr('leveloffset', 0)) -
                    rubyToInteger(strValue.substring(1)))
                .toString();
      }
    }
    // QUESTION should we set value to locked value if set_attribute
    // returns false?
    if (!doc.attributeLocked(attrName)) {
      final resolved = strValue.isEmpty
          ? strValue
          : applyHeaderSubs(doc, strValue) as String;
      doc.attributes[attrName] = resolved;
      return (attrName, resolved);
    }
    return (attrName, strValue);
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
    result = result.replaceAllMapped(
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
  if (captured.contains(rs)) {
    // we have to use sub since we aren't sure it's the first char
    return captured.replaceFirst(rs, '');
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
/// Dart exposes no group-name list (unlike Ruby's `MatchData#names`), so
/// the pattern source is inspected instead.
bool _hasNamedGroups(RegExp regexp) =>
    RegExp(r'\(\?<[A-Za-z_]').hasMatch(regexp.pattern);

/// Returns the `name`d group of [match], or `null` when the pattern does
/// not declare it (port of `$~[name] rescue nil`).
String? _namedGroupOrNull(Match match, String name) {
  try {
    return (match as RegExpMatch).namedGroup(name);
  } on ArgumentError {
    return null;
  }
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
  final Registry? macroExtensions = doc.extensions;
  if (macroExtensions != null && macroExtensions.hasInlineMacros) {
    for (final extension in macroExtensions.inlineMacros) {
      final instance = extension.instance as InlineMacroProcessor;
      final extConfig = extension.config;
      final regexp = instance.regexp;
      final hasNamedGroups = _hasNamedGroups(regexp);
      result = result.replaceAllMapped(regexp, (match) {
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
        final defaultAttrs = extConfig['default_attrs'];
        final attributes = <Object, Object?>{
          if (defaultAttrs is Map) ...defaultAttrs.cast<Object, Object?>(),
        };
        if (content != null) {
          if (content.isEmpty) {
            if (extConfig['content_model'] != 'attributes') {
              attributes['text'] = content;
            }
          } else {
            final normalized = normalizeText(content, true, true);
            // QUESTION should we store the unparsed attrlist in the
            // attrlist key?
            if (extConfig['content_model'] == 'attributes') {
              final posattrs =
                  extConfig['positional_attrs'] ?? extConfig['pos_attrs'];
              parseAttributes(
                node,
                normalized,
                posattrs: posattrs is List
                    ? posattrs.map((e) => e?.toString()).toList()
                    : const <String?>[],
                into: attributes,
              );
            } else {
              attributes['text'] = normalized;
            }
            content = normalized;
          }
          // NOTE for convenience, map content (unparsed attrlist) to
          // target when format is short.
          target ??= extConfig['format'] == 'short' ? content : target;
        }
        // NOTE `target` is null only for custom patterns without a
        // target capture; like the rest of this port, the process method
        // requires a non-null target (see `MacroProcessor.process`).
        final replacement =
            (extension.processMethod
                as Object? Function(
                  AbstractBlock,
                  String,
                  Map<Object, Object?>,
                ))(block, target!, attributes);
        if (replacement is Inline) {
          final inlineSubsRaw = replacement.attributes.remove('subs');
          final inlineSubs = isTruthy(inlineSubsRaw)
              ? expandSubs(node, inlineSubsRaw, 'custom inline macro')
              : null;
          if (inlineSubs != null) {
            replacement.text =
                applySubs(node, replacement.text, inlineSubs) as String?;
          }
          return _str(replacement.convert());
        } else if (replacement != null) {
          node.logger.info(
            'expected substitution value for custom inline macro to be of '
            'type Inline; got ${replacement.runtimeType}: $fullMatch',
          );
          return replacement.toString();
        } else {
          return '';
        }
      });
    }
  }

  if (docAttrs.containsKey('experimental')) {
    if (foundMacroishShort &&
        (result.contains('kbd:') || result.contains('btn:'))) {
      result = result.replaceAllMapped(inlineKbdBtnMacroRx, (match) {
        // honor the escape
        if (match.group(1) != null) {
          return match.group(0)!.substring(1);
        } else if (match.group(2) == 'kbd') {
          var keys = match.group(3)!.trim();
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
                    .map((key) => key.trim())
                    .toList();
                keyList[keyList.length - 1] += delim;
              } else {
                keyList = keys.split(delim).map((key) => key.trim()).toList();
              }
            } else {
              keyList = [keys];
            }
          } else {
            keyList = [keys];
          }
          return _str(
            Inline(block, 'kbd', attributes: {'keys': keyList}).convert(),
          );
        } else {
          // match.group(2) == 'btn'
          return _str(
            Inline(
              block,
              'button',
              text: normalizeText(match.group(3)!, true, true),
            ).convert(),
          );
        }
      });
    }

    if (foundMacroish && result.contains('menu:')) {
      result = result.replaceAllMapped(inlineMenuMacroRx, (match) {
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
            final parts = rubySplit(
              items,
              delim,
            ).map((item) => item.trim()).toList();
            menuitem = parts.removeLast();
            submenus = parts;
          } else {
            submenus = <String>[];
            menuitem = items.rstrip();
          }
        } else {
          submenus = <String>[];
          menuitem = null;
        }

        return _str(
          Inline(
            block,
            'menu',
            attributes: {
              'menu': menu,
              'submenus': submenus,
              'menuitem': menuitem,
            },
          ).convert(),
        );
      });
    }

    if (result.contains('"') && result.contains('&gt;')) {
      result = result.replaceAllMapped(inlineMenuRx, (match) {
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }

        final parts = rubySplit(
          match.group(1)!,
          '&gt;',
        ).map((item) => item.trim()).toList();
        final menu = parts.removeAt(0);
        final menuitem = parts.removeLast();
        return _str(
          Inline(
            block,
            'menu',
            attributes: {'menu': menu, 'submenus': parts, 'menuitem': menuitem},
          ).convert(),
        );
      });
    }
  }

  if (foundMacroish &&
      (result.contains('image:') || result.contains('icon:'))) {
    // image:filename.png[Alt Text]
    result = result.replaceAllMapped(inlineImageMacroRx, (match) {
      // honor the escape
      if (match.group(0)!.startsWith(rs)) {
        return match.group(0)!.substring(1);
      }
      final bool isIcon = match.group(0)!.startsWith('icon:');
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
        id = attrs['id'] as String?;
        doc.register('images', target);
        if (!isTruthy(attrs['imagesdir'])) {
          attrs['imagesdir'] = docAttrs['imagesdir'];
        }
      }
      if (!isTruthy(attrs['alt'])) {
        final defaultAlt = Helpers.basename(
          target,
          true,
        ).replaceAll(RegExp('[_-]'), ' ');
        attrs['alt'] = defaultAlt;
        attrs['default-alt'] = defaultAlt;
      }
      return _str(
        Inline(
          block,
          'image',
          type: type,
          target: target,
          id: id,
          attributes: _stringMap(attrs),
        ).convert(),
      );
    });
  }

  if ((result.contains('((') && result.contains('))')) ||
      (foundMacroishShort && result.contains('dexterm'))) {
    // (((Tigers,Big cats)))
    // indexterm:[Tigers,Big cats]
    // ((Tigers))
    // indexterm2:[Tigers]
    result = result.replaceAllMapped(inlineIndextermMacroRx, (match) {
      final macro = match.group(1);
      if (macro == 'indexterm') {
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }

        // indexterm:[Tigers,Big cats]
        final attrlist = normalizeText(match.group(2)!, true, true);
        final Map<Object, Object?> attrs;
        if (attrlist.contains('=')) {
          final parsed = AttributeList(
            attrlist,
            _BlockSubsApplier(node),
          ).parse();
          if (parsed[1] != null) {
            final primary = parsed[1]!;
            final terms = <String>[primary];
            final secondary = parsed[2];
            if (secondary != null) {
              terms.add(secondary);
              final tertiary = parsed[3];
              if (tertiary != null) {
                terms.add(tertiary);
              }
            }
            final wide = Map<Object, Object?>.of(parsed);
            wide['terms'] = terms;
            final seeAlso = wide['see-also'];
            if (isTruthy(seeAlso)) {
              final seeAlsoStr = seeAlso.toString();
              wide['see-also'] = seeAlsoStr.contains(',')
                  ? rubySplit(seeAlsoStr, ',').map(lstrip).toList()
                  : [seeAlsoStr];
            }
            attrs = wide;
          } else {
            attrs = {'terms': attrlist};
          }
        } else {
          attrs = {'terms': splitSimpleCsv(attrlist)};
        }
        return _str(
          Inline(block, 'indexterm', attributes: _stringMap(attrs)).convert(),
        );
      } else if (macro == 'indexterm2') {
        // honor the escape
        if (match.group(0)!.startsWith(rs)) {
          return match.group(0)!.substring(1);
        }

        // indexterm2:[Tigers]
        var term = normalizeText(match.group(2)!, true, true);
        Map<Object, Object?>? attrs;
        if (term.contains('=')) {
          final parsed = AttributeList(term, _BlockSubsApplier(node)).parse();
          final first = parsed[1];
          if (isTruthy(first)) {
            term = first!;
            attrs = Map<Object, Object?>.of(parsed);
            final seeAlso = attrs['see-also'];
            if (isTruthy(seeAlso)) {
              final seeAlsoStr = seeAlso.toString();
              attrs['see-also'] = seeAlsoStr.contains(',')
                  ? rubySplit(seeAlsoStr, ',').map(lstrip).toList()
                  : [seeAlsoStr];
            }
          } else {
            attrs = null;
          }
        }
        return _str(
          Inline(
            block,
            'indexterm',
            text: term,
            attributes: attrs == null ? null : _stringMap(attrs),
            type: 'visible',
          ).convert(),
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
            enclText = chopLast(enclText);
            before = '';
            after = ')';
          }
        }
        final String subbedTerm;
        if (visible) {
          // ((Tigers))
          var term = normalizeText(enclText, true);
          Map<String, Object?>? termAttrs;
          if (term.contains(';&')) {
            if (term.contains(' &gt;&gt; ')) {
              final idx = term.indexOf(' &gt;&gt; ');
              termAttrs = {'see': term.substring(idx + ' &gt;&gt; '.length)};
              term = term.substring(0, idx);
            } else if (term.contains(' &amp;&gt; ')) {
              final parts = rubySplit(term, ' &amp;&gt; ');
              term = parts.removeAt(0);
              termAttrs = {'see-also': parts};
            }
          }
          subbedTerm = _str(
            Inline(
              block,
              'indexterm',
              text: term,
              attributes: termAttrs,
              type: 'visible',
            ).convert(),
          );
        } else {
          // (((Tigers,Big cats)))
          var terms = normalizeText(enclText, true);
          final attrs = <String, Object?>{};
          if (terms.contains(';&')) {
            if (terms.contains(' &gt;&gt; ')) {
              final idx = terms.indexOf(' &gt;&gt; ');
              attrs['see'] = terms.substring(idx + ' &gt;&gt; '.length);
              terms = terms.substring(0, idx);
            } else if (terms.contains(' &amp;&gt; ')) {
              final parts = rubySplit(terms, ' &amp;&gt; ');
              terms = parts.removeAt(0);
              attrs['see-also'] = parts;
            }
          }
          attrs['terms'] = splitSimpleCsv(terms);
          subbedTerm = _str(
            Inline(block, 'indexterm', attributes: attrs).convert(),
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

/// Continues [subMacros] with links, emails, anchors, xrefs and footnotes.
///
/// Split out only to keep function sizes manageable; the Ruby method runs
/// these steps inline, in this order. [foundSquareBracket] and
/// [foundMacroish] are the sniffs computed on the original text.
String _subMacrosLinks(
  AbstractNode node,
  AbstractBlock block,
  Document doc,
  Map<String, Object?> docAttrs,
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
    result = result.replaceAllMapped(inlineLinkRx, (match) {
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
        doc.register('links', target);
        final linkText = docAttrs.containsKey('hide-uri-scheme')
            ? target.replaceFirst(uriSniffRx, '')
            : target;
        return _str(
          Inline(
            block,
            'anchor',
            text: linkText,
            type: 'link',
            target: target,
            attributes: const {'role': 'bare'},
          ).convert(),
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
        Map<Object, Object?>? attrs;
        var bare = false;
        if (linkText != null) {
          String? newLinkText;
          if (linkText.contains(rSb)) {
            linkText = linkText.replaceAll(escRSb, rSb);
            newLinkText = linkText;
          }
          if (!compat && linkText.contains('=')) {
            // NOTE if an equals sign (=) is present, extract attributes
            // from link text
            final extracted = extractAttributesFromText(node, linkText, '');
            linkText = extracted.text!;
            newLinkText = linkText;
            attrs = extracted.attributes;
            id = attrs['id'] as String?;
          }

          if (linkText.endsWith('^')) {
            linkText = linkText.substring(0, linkText.length - 1);
            newLinkText = linkText;
            if (attrs != null) {
              if (!isTruthy(attrs['window'])) attrs['window'] = '_blank';
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

        doc.register('links', target);
        return '$prefix${_str(Inline(block, 'anchor', text: linkText, type: 'link', target: target, id: id, attributes: attrs == null ? null : _stringMap(attrs)).convert())}$suffix';
      }
    });
  }

  if (foundMacroish && (result.contains('link:') || result.contains('ilto:'))) {
    // inline link macros, link:target[text]
    result = result.replaceAllMapped(inlineLinkMacroRx, (match) {
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
      Map<Object, Object?>? attrs;
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
            id = attrs['id'] as String?;
            if (attrs.containsKey(2)) {
              if (attrs.containsKey(3)) {
                target =
                    '$target?subject=${Helpers.encodeUriComponent(attrs[2] as String)}'
                    '&amp;body=${Helpers.encodeUriComponent(attrs[3] as String)}';
              } else {
                target =
                    '$target?subject=${Helpers.encodeUriComponent(attrs[2] as String)}';
              }
            }
          }
        } else if (!compat && linkText.contains('=')) {
          // NOTE if an equals sign (=) is present, extract attributes
          // from link text
          final extracted = extractAttributesFromText(node, linkText, '');
          linkText = extracted.text!;
          attrs = extracted.attributes;
          id = attrs['id'] as String?;
        }

        if (linkText.endsWith('^')) {
          linkText = linkText.substring(0, linkText.length - 1);
          if (attrs != null) {
            if (!isTruthy(attrs['window'])) attrs['window'] = '_blank';
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
      doc.register('links', target);
      return _str(
        Inline(
          block,
          'anchor',
          text: linkText,
          type: 'link',
          target: target,
          id: id,
          attributes: attrs == null ? null : _stringMap(attrs),
        ).convert(),
      );
    });
  }

  if (result.contains('@')) {
    result = result.replaceAllMapped(inlineEmailRx, (match) {
      // honor the escape
      if (match.group(1) != null) {
        return match.group(1) == rs
            ? match.group(0)!.substring(1)
            : match.group(0)!;
      }

      final address = match.group(0)!;
      final target = 'mailto:$address';
      // QUESTION should this be registered as an e-mail address?
      doc.register('links', target);

      return _str(
        Inline(
          block,
          'anchor',
          text: address,
          type: 'link',
          target: target,
        ).convert(),
      );
    });
  }

  if (foundSquareBracket &&
      node.context == 'list_item' &&
      node.parent?.style == 'bibliography') {
    result = result.replaceFirstMapped(
      inlineBiblioAnchorRx,
      (match) => _str(
        Inline(
          block,
          'anchor',
          text: match.group(2),
          type: 'bibref',
          id: match.group(1),
        ).convert(),
      ),
    );
  }

  if ((foundSquareBracket && result.contains('[[')) ||
      (foundMacroish && result.contains('or:'))) {
    result = result.replaceAllMapped(inlineAnchorRx, (match) {
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
      } else {
        id = match.group(4);
        reftext = match.group(5);
        if (reftext != null && reftext.contains(rSb)) {
          reftext = reftext.replaceAll(escRSb, rSb);
        }
      }
      return _str(
        Inline(block, 'anchor', text: reftext, type: 'ref', id: id).convert(),
      );
    });
  }

  //if (text.include? ';&l') || (found_macroish && (text.include? 'xref:'))
  if ((result.contains('&') && result.contains(';&l')) ||
      (foundMacroish && result.contains('xref:'))) {
    result = result.replaceAllMapped(
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
    result = result.replaceAllMapped(
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
  Map<String, Object?> docAttrs,
  bool compat,
  RegExpMatch match,
) {
  // honor the escape
  if (match.group(0)!.startsWith(rs)) {
    return match.group(0)!.substring(1);
  }

  var attrs = <String, Object?>{};
  String? refid = match.group(1);
  String? linkText;
  var macro = false;
  if (refid != null) {
    if (refid.contains(',')) {
      final idx = refid.indexOf(',');
      linkText = lstrip(refid.substring(idx + 1));
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
      if (!compat && linkText.contains('=')) {
        final extracted = extractAttributesFromText(node, linkText);
        linkText = extracted.text;
        attrs = _stringMap(extracted.attributes);
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
    // NOTE Ruby reads refid[hash_idx - 1], which wraps to the last
    // character when hash_idx is 0.
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
    final includes = doc.catalog['includes'];
    if (src2src != null &&
        (docAttrs['docname'] == path ||
            (includes is Map && isTruthy(includes[path])))) {
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
      final prefix = isTruthy(docAttrs['relfileprefix'])
          ? docAttrs['relfileprefix'].toString()
          : '';
      final suffix = src2src != null
          ? (docAttrs.containsKey('relfilesuffix')
                ? _str(docAttrs['relfilesuffix'])
                : _str(doc.outfilesuffix))
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
  } else if (isTruthy(
    (doc.catalog['refs'] as Map<String, Object?>)[fragment],
  )) {
    refid = fragment;
    target = '#$fragment';
    // handles: Node Title or Reference Text
    // do reverse lookup on fragment if not a known ID and resembles
    // reftext (contains a space or uppercase char)
  } else {
    final resolved =
        (fragment!.contains(' ') || fragment.toLowerCase() != fragment)
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
  attrs['path'] = path;
  attrs['fragment'] = fragment;
  attrs['refid'] = refid;
  return _str(
    Inline(
      block,
      'anchor',
      text: linkText,
      type: 'xref',
      target: target,
      attributes: attrs,
    ).convert(),
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

  Object? index;
  String? type;
  String? target;
  String? finalId = id;
  String? finalContent = content;
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
      finalContent = footnote.text.toString();
      type = 'xref';
      target = id;
      finalId = null;
    } else if (content != null) {
      finalContent = restorePassthroughs(
        node,
        normalizeText(content, true, true),
      );
      index = doc.counter('footnote-number');
      doc.register('footnotes', Footnote(index, id, finalContent));
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
      normalizeText(content, true, true),
    );
    index = doc.counter('footnote-number');
    doc.register('footnotes', Footnote(index, id, finalContent));
    type = null;
    target = null;
  } else {
    return match.group(0)!;
  }
  return _str(
    Inline(
      block,
      'footnote',
      text: finalContent,
      attributes: {'index': index},
      id: finalId,
      target: target,
      type: type,
    ).convert(),
  );
}

/// Substitutes post replacements (hard line breaks) in [text].
///
/// Port of `Substitutors#sub_post_replacements`.
String subPostReplacements(AbstractNode node, String text) {
  //if attr? 'hardbreaks-option', nil, true
  final docAttrs = _documentOf(node).attributes;
  if (isTruthy(node.attributes['hardbreaks-option']) ||
      isTruthy(docAttrs['hardbreaks-option'])) {
    final lines = text.split(lf);
    if (lines.length < 2) return text;
    final last = lines.removeLast();
    final converted = <String>[
      for (final line in lines)
        _str(
          Inline(
            _blockOf(node),
            'break',
            text: line.endsWith(hardLineBreak)
                ? line.substring(0, line.length - 2)
                : line,
            type: 'line',
          ).convert(),
        ),
      last,
    ];
    return converted.join(lf);
  } else if (text.contains(plus) && text.contains(hardLineBreak)) {
    return text.replaceAllMapped(
      hardLineBreakRx,
      (match) => _str(
        Inline(
          _blockOf(node),
          'break',
          text: match.group(1),
          type: 'line',
        ).convert(),
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
String subSource(AbstractNode node, String source, bool processCallouts) =>
    processCallouts
    ? subCallouts(node, subSpecialchars(source))
    : subSpecialchars(source);

/// Substitutes callout source references in [text].
///
/// Port of `Substitutors#sub_callouts`.
String subCallouts(AbstractNode node, String text) {
  final doc = _documentOf(node);
  final pattern = node.hasAttr('line-comment')
      ? calloutSourceRxMap[node.attr('line-comment').toString()]
      : calloutSourceRx;
  var autonum = 0;
  return text.replaceAllMapped(pattern, (match) {
    // honor the escape
    if (match.group(2) != null) {
      // use sub since it might be behind a line comment
      return match.group(0)!.replaceFirst(rs, '');
    }
    final numeral = match.group(4) == '.' ? '${++autonum}' : match.group(4)!;
    Object? guard = match.group(1);
    guard ??= match.group(3) == '--' ? const ['<!--', '-->'] : null;
    return _str(
      Inline(
        _blockOf(node),
        'callout',
        text: numeral,
        id: doc.callouts.readNextId(),
        attributes: {'guard': guard},
      ).convert(),
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
String highlightSource(AbstractNode node, String source, bool processCallouts) {
  final doc = _documentOf(node);
  final syntaxHl = doc.syntaxHighlighter;
  // NOTE the call to highlight? is a defensive check since, normally, we
  // wouldn't arrive here unless it returns true
  if (syntaxHl is! SyntaxHighlighterBase || !syntaxHl.canHighlight) {
    return subSource(node, source, processCallouts);
  }
  final docAttrs = doc.attributes;
  Map<int, List<PendingCallout>>? calloutMarks;
  if (processCallouts) {
    final extracted = extractCallouts(node, source);
    source = extracted.source;
    calloutMarks = extracted.calloutMarks;
  }
  // NOTE (coderay parity gap): the shared CssMode/LineNumbersMode mapping is
  // lenient (unknown values map to inline), which matches pygments, but
  // CodeRay itself rejects unknown :css / :line_numbers values with an
  // error. Plumbing the raw strings through the typed adapter seam so the
  // CodeRay backend can validate them is framework-wave work.
  LineNumbersMode? linenumsMode;
  int? startLineNumber;
  if (node.hasOption('linenums')) {
    linenumsMode = LineNumbersMode.fromAttribute(
      docAttrs['${syntaxHl.name}-linenums-mode']?.toString(),
      linenums: true,
    );
    startLineNumber = rubyToInteger(node.attr('start', 1));
    if (startLineNumber < 1) startLineNumber = 1;
  }
  final highlightLines = node.hasAttr('highlight')
      ? resolveLinesToHighlight(source, node.attr('highlight'), startLineNumber)
      : const <int>[];
  final result = syntaxHl.highlight(
    node as AbstractBlock,
    source,
    node.attr('language')?.toString(),
    // The framework only reads the null/emptiness of this map (to derive
    // `hasCallouts`); the marks themselves travel separately below.
    callouts: (calloutMarks == null || calloutMarks.isEmpty)
        ? null
        : <int, String>{for (final lineno in calloutMarks.keys) lineno: ''},
    cssMode: CssMode.fromAttribute(
      docAttrs['${syntaxHl.name}-css']?.toString(),
    ),
    highlightLines: highlightLines,
    numberLines: linenumsMode,
    startLineNumber: startLineNumber,
    style: docAttrs['${syntaxHl.name}-style']?.toString(),
  );
  var highlighted = result.html;
  if (node.passthroughs.isNotEmpty) {
    highlighted = highlighted.replaceAllMapped(
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
List<int> resolveLinesToHighlight(String source, Object? spec, [int? start]) {
  if (spec == null) return <int>[];
  var lines = <int>[];
  var specStr = spec.toString();
  if (specStr.contains(' ')) specStr = specStr.replaceAll(' ', '');
  final entries = specStr.contains(',')
      ? rubySplit(specStr, ',')
      : rubySplit(specStr, ';');
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
        final parsed = rubyToInteger(toStr);
        to = parsed < 0 ? '\n'.allMatches(source).length + 1 : parsed;
      }
      final range = <int>[for (var i = rubyToInteger(from); i <= to; i++) i];
      if (negate) {
        lines = lines.where((line) => !range.contains(line)).toList();
      } else {
        for (final line in range) {
          if (!lines.contains(line)) lines.add(line);
        }
      }
    } else if (negate) {
      lines.remove(rubyToInteger(entry));
    } else {
      final line = rubyToInteger(entry);
      if (!lines.contains(line)) lines.add(line);
    }
  }
  // If the start attribute is defined, then the lines to highlight
  // specified by the provided spec should be relative to the start value.
  final shift = isTruthy(start) ? start! - 1 : 0;
  if (shift != 0) {
    lines = lines.map((line) => line - shift).toList();
  }
  lines.sort();
  return lines;
}

/// A callout mark extracted from source: its [guard] (line-comment prefix
/// or the `<!--`/`-->` pair) and its [numeral].
typedef PendingCallout = ({Object? guard, String numeral});

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
  final pattern = node.hasAttr('line-comment')
      ? calloutExtractRxMap[node.attr('line-comment').toString()]
      : calloutExtractRx;
  // extract callout marks, indexed by line number
  final cleaned = source
      .split(lf)
      .map((line) {
        lineno++;
        return line.replaceAllMapped(pattern, (match) {
          // honor the escape
          if (match.group(2) != null) {
            // use sub since it might be behind a line comment
            return match.group(0)!.replaceFirst(rs, '');
          }
          Object? guard = match.group(1);
          guard ??= match.group(3) == '--' ? const ['<!--', '-->'] : null;
          final numeral = match.group(4) == '.'
              ? '${++autonum}'
              : match.group(4)!;
          (calloutMarks![lineno] ??= []).add((guard: guard, numeral: numeral));
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
            if (conums.length == 1) {
              final mark = conums[0];
              return '$line${_str(Inline(block, 'callout', text: mark.numeral, id: doc.callouts.readNextId(), attributes: {'guard': mark.guard}).convert())}';
            } else {
              return '$line${conums.map((mark) => _str(Inline(block, 'callout', text: mark.numeral, id: doc.callouts.readNextId(), attributes: {'guard': mark.guard}).convert())).join(' ')}';
            }
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
  final passthrus = node.passthroughs;
  var result = text;
  if (text.contains('++') || text.contains(r'$$') || text.contains('ss:')) {
    result = result.replaceAllMapped(inlinePassMacroRx, (match) {
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
        Map<String, Object?>? attributes;
        var oldBehavior = false;
        String? preceding;
        if (attrlist != null) {
          if (escapeCount > 0) {
            // NOTE we don't look for nested unconstrained pass macros
            return '${match.group(1) ?? ''}[$attrlist]${rs * (escapeCount - 1)}$boundary${match.group(5)}$boundary';
          } else if (match.group(1) == rs) {
            preceding = '[$attrlist]';
          } else if (boundary == '++') {
            if (attrlist == 'x-') {
              oldBehavior = true;
              attributes = <String, Object?>{};
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
        final subs = boundary == '+++'
            ? <String>[]
            : List<String>.of(basicSubs);

        final passthruKey = passthrus.length;
        if (attributes != null) {
          if (oldBehavior) {
            passthrus.add({
              'text': match.group(5),
              'subs': normalSubs,
              'type': 'monospaced',
              'attributes': attributes,
            });
          } else {
            passthrus.add({
              'text': match.group(5),
              'subs': subs,
              'type': 'unquoted',
              'attributes': attributes,
            });
          }
        } else {
          passthrus.add({'text': match.group(5), 'subs': subs});
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
        if (subs != null) {
          passthrus.add({
            'text': normalizeText(match.group(8)!, null, true),
            'subs': resolvePassSubs(node, subs),
          });
        } else {
          passthrus.add({'text': normalizeText(match.group(8)!, null, true)});
        }
        return '$passStart$passthruKey$passEnd';
      }
    });
  }

  final passEntry = inlinePassRx[compatMode]!;
  if (result.contains(passEntry.delimiter) ||
      (passEntry.endTrim != null && result.contains(passEntry.endTrim!))) {
    result = result.replaceAllMapped(passEntry.pattern, (match) {
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

      Map<String, Object?>? attributes;
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
              ? <String, Object?>{}
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
        passthrus.add({
          'text': content,
          'subs': basicSubs,
          'attributes': attributes,
          'type': 'monospaced',
        });
      } else if (attributes != null) {
        if (oldBehavior) {
          passthrus.add({
            'text': content,
            'subs': formatMark == '`' ? basicSubs : normalSubs,
            'attributes': attributes,
            'type': 'monospaced',
          });
        } else {
          passthrus.add({
            'text': content,
            'subs': basicSubs,
            'attributes': attributes,
            'type': 'unquoted',
          });
        }
      } else {
        passthrus.add({'text': content, 'subs': basicSubs});
      }

      return '$preceding$passStart$passthruKey$passEnd';
    });
  }

  // NOTE we need to do the stem in a subsequent step to allow it to be
  // escaped by the former
  if (result.contains(':') &&
      (result.contains('stem:') || result.contains('math:'))) {
    result = result.replaceAllMapped(inlineStemMacroRx, (match) {
      // honor the escape
      if (match.group(0)!.startsWith(rs)) {
        return match.group(0)!.substring(1);
      }

      var type = match.group(1)!;
      if (type == 'stem') {
        type = stemTypeAliases[doc.attributes['stem']] ?? 'asciimath';
      }
      final subs = match.group(2);
      var content = normalizeText(match.group(3)!, null, true);
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
      passthrus.add({'text': content, 'subs': resolvedSubs, 'type': type});
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
  final passthrus = node.passthroughs;
  return text.replaceAllMapped(passSlotRx, (match) {
    final slot = int.parse(match.group(1)!);
    final pass = slot < passthrus.length ? passthrus[slot] : null;
    if (pass != null) {
      var subbedText = applySubs(
        node,
        pass['text'] as String,
        pass['subs'] as List<String>?,
      ) as String;
      final type = pass['type'] as String?;
      if (type != null) {
        final attributes = pass['attributes'] as Map<String, Object?>?;
        final id = attributes?['id'] as String?;
        subbedText = _str(
          Inline(
            _blockOf(node),
            'quoted',
            text: subbedText,
            type: type,
            id: id,
            attributes: attributes,
          ).convert(),
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
/// [type] selects the context (`'block'` or `'inline'`); [defaults] seeds
/// incremental substitutions; [subject] names the subject in log messages.
/// Returns the resolved substitutions, or `null` if no subs are found.
///
/// Port of `Substitutors#resolve_subs`.
List<String>? resolveSubs(
  AbstractNode node,
  String? subs, [
  String type = 'block',
  List<String>? defaults,
  String? subject,
]) {
  if (subs == null || subs.isEmpty) return null;
  // QUESTION should we store candidates as a Set instead of an Array?
  List<String>? candidates;
  var source = subs;
  if (source.contains(' ')) source = source.replaceAll(' ', '');
  final modifiersPresent = subModifierSniffRx.hasMatch(source);
  for (var key in rubySplit(source, ',')) {
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
    if (type == 'inline' && (key == 'verbatim' || key == 'v')) {
      resolvedKeys = basicSubs;
    } else if (subGroups.containsKey(key)) {
      resolvedKeys = subGroups[key]!;
    } else if (type == 'inline' &&
        key.length == 1 &&
        subHints.containsKey(key)) {
      final resolvedKey = subHints[key]!;
      resolvedKeys = subGroups[resolvedKey] ?? [resolvedKey];
    } else {
      resolvedKeys = [key];
    }

    if (modifierOperation != null) {
      candidates ??= defaults != null ? List<String>.of(defaults) : <String>[];
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
  final options = subOptions[type]!;
  final resolved = <String>[];
  for (final candidate in found) {
    if (options.contains(candidate) && !resolved.contains(candidate)) {
      resolved.add(candidate);
    }
  }
  final invalid = found
      .where((candidate) => !resolved.contains(candidate))
      .toList();
  if (invalid.isNotEmpty) {
    node.logger.warn(
      'invalid substitution type${invalid.length > 1 ? 's' : ''}'
      '${subject != null ? ' for ' : ''}${subject ?? ''}: '
      "${invalid.join(', ')}",
    );
  }
  return resolved;
}

/// Resolves [subs] for the block type.
///
/// Port of `Substitutors#resolve_block_subs`.
List<String>? resolveBlockSubs(
  AbstractNode node,
  String? subs,
  List<String>? defaults,
  String? subject,
) => resolveSubs(node, subs, 'block', defaults, subject);

/// Resolves [subs] for the inline type (passthrough macro subject).
///
/// Port of `Substitutors#resolve_pass_subs`.
List<String>? resolvePassSubs(
  AbstractNode node,
  String? subs, [
  String subject = 'passthrough macro',
]) => resolveSubs(node, subs, 'inline', null, subject);

/// Expands all groups in [subs] and returns the result, or `null` if no
/// subs are resolved.
///
/// [subs] is a single name, a list of names, or a comma-delimited string;
/// [subject] names the subject in log messages.
///
/// Port of `Substitutors#expand_subs`.
List<String>? expandSubs(AbstractNode node, Object? subs, [String? subject]) {
  if (subs is String) {
    // Port of `Substitutors#expand_subs` (lib/asciidoctor/substitutors.rb:
    // 1257-1276): strings resolve through `resolve_subs` (which splits
    // comma-delimited lists and expands groups); only the symbol-like
    // `'none'` short-circuits to `null`.
    if (subs == 'none') return null;
    return resolveSubs(node, subs, 'inline', null, subject);
  } else if (subs is List<Object?>) {
    final expandedSubs = <String>[];
    for (final key in subs) {
      if (key == 'none') continue;
      final subGroup = subGroups[key];
      if (subGroup != null) {
        expandedSubs.addAll(subGroup);
      } else {
        expandedSubs.add(key as String);
      }
    }
    return expandedSubs.isEmpty ? null : expandedSubs;
  } else {
    return resolveSubs(node, subs as String?, 'inline', null, subject);
  }
}

/// Commits the requested substitutions to [node].
///
/// Looks for an attribute named `subs`. If present, resolves substitutions
/// from its value and assigns them to [node]; otherwise uses [Block]'s
/// default subs, if specified, or selects defaults based on the content
/// model. Returns the assigned subs when the content model needs none.
///
/// Port of `Substitutors#commit_subs`.
List<String>? commitSubs(AbstractBlock node) {
  final Object? defaultSubs = node is Block ? node.defaultSubs : null;
  late List<String> effective;
  if (!isTruthy(defaultSubs)) {
    switch (node.contentModel) {
      case 'simple':
        effective = normalSubs;
      case 'verbatim':
        effective = node.context == 'verse' ? normalSubs : verbatimSubs;
      case 'raw':
        // TODO make pass subs a compliance setting; AsciiDoc.py performs
        // :attributes and :macros on a pass block
        effective = node.context == 'stem' ? basicSubs : noSubs;
      default:
        return node.subs;
    }
  } else {
    effective = List<String>.from(defaultSubs as List);
  }

  final customSubs = node.attributes['subs'];
  if (isTruthy(customSubs)) {
    node.subs =
        resolveBlockSubs(
          node,
          customSubs.toString(),
          effective,
          node.context,
        ) ??
        [];
  } else {
    node.subs = List<String>.of(effective);
  }

  // QUESTION delegate this logic to a method?
  final doc = node.document;
  final syntaxHl = doc is Document ? doc.syntaxHighlighter : null;
  if (node.context == 'listing' &&
      node.style == 'source' &&
      syntaxHl is SyntaxHighlighterBase &&
      syntaxHl.canHighlight) {
    final idx = node.subs.indexOf('specialcharacters');
    if (idx != -1) node.subs[idx] = 'highlight';
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
Map<Object, Object?> parseAttributes(
  AbstractNode node,
  String? attrlist, {
  List<String?> posattrs = const [],
  Map<Object, Object?>? into,
  bool subInput = false,
  bool subResult = false,
  bool unescapeInput = false,
}) {
  if (attrlist == null || attrlist.isEmpty) return <Object, Object?>{};
  var source = attrlist;
  if (unescapeInput) source = normalizeText(source, true, true);
  if (subInput && source.contains(attrRefHead)) {
    source = subAttributes(_documentOf(node), source);
  }
  // substitutions are only performed on attribute values if block is not
  // nil
  final block = subResult ? _BlockSubsApplier(node) : null;
  final parsed = AttributeList(source, block).parse(posattrs);
  if (into != null) {
    into.addAll(parsed);
    return into;
  }
  return Map<Object, Object?>.of(parsed);
}

/// Extracts attributes mixed with macro text.
///
/// If no attributes are detected aside from the first positional attribute,
/// and it matches [text], the original text is returned. [defaultText] is
/// returned as the text when no positional attribute is found.
///
/// Port of `Substitutors#extract_attributes_from_text`.
({String? text, Map<Object, Object?> attributes}) extractAttributesFromText(
  AbstractNode node,
  String text, [
  String? defaultText,
]) {
  final attrlist = text.contains(lf) ? text.replaceAll(lf, ' ') : text;
  final attrs = AttributeList(attrlist, _BlockSubsApplier(node)).parse();
  final resolvedText = attrs[1];
  if (resolvedText != null) {
    // NOTE if resolved text remains unchanged, clear attributes and
    // return unparsed text
    if (resolvedText == attrlist) {
      attrs.clear();
      return (text: text, attributes: Map<Object, Object?>.of(attrs));
    }
    return (text: resolvedText, attributes: Map<Object, Object?>.of(attrs));
  }
  return (text: defaultText, attributes: Map<Object, Object?>.of(attrs));
}

/// Substitutes [value] into the `%s` placeholder of [format].
///
/// Port of `Substitutors#sub_placeholder` (an alias of `sprintf`; every
/// call site formats a single `%s` value).
String subPlaceholder(String format, Object? value) {
  const token = '\u0000';
  final escaped = format.replaceAll('%%', token);
  final idx = escaped.indexOf('%s');
  final substituted = idx == -1
      ? escaped
      : '${escaped.substring(0, idx)}${_str(value)}${escaped.substring(idx + 2)}';
  return substituted.replaceAll(token, '%');
}

/// Parses the attributes defined on quoted (formatted) text.
///
/// [str] is space-separated roles or the id/role shorthand syntax (e.g.,
/// `#idname.role`). Returns the role and id attributes.
///
/// Port of `Substitutors#parse_quoted_text_attributes`.
Map<String, Object?> parseQuotedTextAttributes(AbstractNode node, String str) {
  // NOTE attributes are typically resolved after quoted text, so
  // substitute eagerly
  var text = str.contains(attrRefHead) ? subAttributes(node, str) : str;
  // for compliance, only consider first positional attribute (very
  // unlikely)
  if (text.contains(',')) text = text.substring(0, text.indexOf(','));
  text = text.trim();
  if (text.isEmpty) {
    return <String, Object?>{};
  } else if ((text.startsWith('.') || text.startsWith('#')) &&
      Compliance.shorthandPropertySyntax) {
    final hashIdx = text.indexOf('#');
    final before = hashIdx == -1 ? text : text.substring(0, hashIdx);
    final after = hashIdx == -1 ? '' : text.substring(hashIdx + 1);
    final attrs = <String, Object?>{};
    if (after.isEmpty) {
      if (before.length > 1) {
        attrs['role'] = before.replaceAll('.', ' ').trimLeft();
      }
    } else {
      final dotIdx = after.indexOf('.');
      final id = dotIdx == -1 ? after : after.substring(0, dotIdx);
      final roles = dotIdx == -1 ? '' : after.substring(dotIdx + 1);
      if (id.isNotEmpty) attrs['id'] = id;
      if (roles.isEmpty) {
        if (before.length > 1) {
          attrs['role'] = before.replaceAll('.', ' ').trimLeft();
        }
      } else if (before.length > 1) {
        attrs['role'] = '$before.$roles'.replaceAll('.', ' ').trimLeft();
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
  String text, [
  bool? normalizeWhitespace,
  bool? unescapeClosingSquareBrackets,
]) {
  var result = text;
  if (result.isNotEmpty) {
    if (isTruthy(normalizeWhitespace)) {
      result = result.trim().replaceAll(lf, ' ');
    }
    if (isTruthy(unescapeClosingSquareBrackets) && result.contains(rSb)) {
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
          values.add(accum.toString().trim());
          accum = StringBuffer();
        }
      } else if (c == '"') {
        quoteOpen = !quoteOpen;
      } else {
        accum.write(c);
      }
    }
    values.add(accum.toString().trim());
    return values;
  } else {
    return rubySplit(str, ',').map((item) => item.trim()).toList();
  }
}
