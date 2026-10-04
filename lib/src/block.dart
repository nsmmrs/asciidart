/// Block-level content nodes in a parsed AsciiDoc document.
///
/// Port of `lib/asciidoctor/block.rb`.
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/helpers.dart';

/// Default content models by block context.
///
/// Port of `Block::DEFAULT_CONTENT_MODEL`. Contexts missing from this map
/// default to `'simple'`, mirroring the `Hash` default.
const Map<String, String> defaultContentModels = <String, String>{
  'audio': 'empty',
  'image': 'empty',
  'listing': 'verbatim',
  'literal': 'verbatim',
  'stem': 'raw',
  'open': 'compound',
  'page_break': 'empty',
  'pass': 'raw',
  'thematic_break': 'empty',
  'video': 'empty',
};

/// Sentinel marking the [Block.subs] option as absent.
///
/// Ruby's constructor distinguishes a missing `:subs` option from an
/// explicit `subs: nil`; this default preserves that distinction.
const Object subsAbsent = Object();

/// Methods for managing AsciiDoc content blocks.
///
/// Port of `Asciidoctor::Block`.
class Block extends AbstractBlock {
  /// Creates a block with [parent] and [context].
  ///
  /// [contentModel] selects how [lines] are processed (`'compound'`,
  /// `'simple'`, `'verbatim'`, `'raw'` or `'empty'`), defaulting per
  /// [defaultContentModels] (`'simple'` when the context is unknown).
  /// [source] is the raw source as a string or a list of lines. [subs]
  /// controls substitution resolution: omitted defers it, `null` prevents
  /// it, `'default'` honors the `subs` attribute (falling back to
  /// [defaultSubs] and then to the context built-ins), a list fixes the
  /// substitutions (ignoring the `subs` attribute), and any other value is
  /// stored as the `subs` attribute. Passing [subs] resolves eagerly
  /// through `commitSubs`, which the substitutors wave still has to port.
  new(
    super.parent,
    super.context, {
    super.attributes,
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
    Object? source,
  }) : lines = _linesFromSource(source) {
    this.contentModel =
        contentModel ?? defaultContentModels[context] ?? 'simple';
    if (identical(subs, subsAbsent)) {
      // Defer subs resolution; the subs attribute is honored later.
      // NOTE @subs is initialized as empty array by super constructor.
      // QUESTION should we honor the :default_subs option here?
      this.defaultSubs = null;
    } else if (subs == null) {
      // NOTE @subs is initialized as empty array by super constructor.
      // Prevent subs from being resolved.
      this.defaultSubs = <String>[];
      attributes.remove('subs');
    } else {
      if (subs == 'default') {
        // Subs attribute is honored; falls back to defaultSubs, then to
        // the built-in defaults based on context.
        this.defaultSubs = defaultSubs;
      } else if (subs is List<Object?>) {
        // Subs attribute is not honored.
        this.defaultSubs = List<String>.from(subs);
        attributes.remove('subs');
      } else {
        // Subs attribute is not honored.
        this.defaultSubs = null;
        attributes['subs'] = subs.toString();
      }
      // Resolve the subs eagerly only if the subs option is specified.
      // QUESTION should we skip subsequent calls to commit_subs?
      commitSubs();
    }
  }

  /// The original content lines of this block, if applicable.
  List<String> lines;

  /// Substitution overrides consulted by `commitSubs` (substitutors wave).
  ///
  /// Internal: `null` defers resolution, an empty list prevents it, and any
  /// other value seeds it.
  Object? defaultSubs;

  /// Copies [source] into content lines.
  ///
  /// A `null` or empty source yields no lines, a string is split into
  /// lines, and a list is duplicated.
  static List<String> _linesFromSource(Object? source) {
    if (source == null) return <String>[];
    if (source is String) {
      if (source.isEmpty) return <String>[];
      return Helpers.prepareSourceString(source);
    }
    if (source is List<Object?>) {
      if (source.isEmpty) return <String>[];
      return List<String>.from(source);
    }
    throw ArgumentError.value(
      source,
      'source',
      'must be a String or a List<String>',
    );
  }

  /// The context of this block. Alias of [AbstractNode.context].
  String get blockname => context;

  /// Returns the converted result of this block, per its content model.
  ///
  /// Compound blocks convert their children, simple blocks apply
  /// substitutions to the joined lines, and verbatim/raw blocks apply
  /// substitutions per line and strip leading and trailing blank lines.
  /// Returns `null` for the `'empty'` model (logging a warning for any
  /// other unknown model).
  @override
  String? content() {
    switch (contentModel) {
      case 'compound':
        // The base implementation always joins converted children into a
        // string; the cast only narrows the widened (polymorphic) override.
        return super.content() as String?;
      case 'simple':
        return applySubs(lines.join(lf), subs)! as String;
      case 'verbatim':
      case 'raw':
        // QUESTION could we use strip here instead of popping empty lines?
        // maybe apply_subs can know how to strip whitespace?
        final result = (applySubs(lines, subs)! as List<Object?>)
            .map((line) => line as String?)
            .toList();
        if (result.length < 2) {
          return result.isEmpty ? '' : (result[0] ?? '');
        }
        while (result.isNotEmpty) {
          final first = result.first;
          if (first == null || first.rstrip().isNotEmpty) break;
          result.removeAt(0);
        }
        while (result.isNotEmpty) {
          final last = result.last;
          if (last == null || last.rstrip().isNotEmpty) break;
          result.removeLast();
        }
        return result.map((line) => line ?? '').join(lf);
      default:
        if (contentModel != 'empty') {
          logger.warn("unknown content model '$contentModel' for block: $this");
        }
        return null;
    }
  }

  /// Returns the preprocessed source of this block.
  String source() => lines.join(lf);

  @override
  String toString() {
    final summary = contentModel == 'compound'
        ? 'blocks: ${blocks.length}'
        : 'lines: ${lines.length}';
    final styleRepr = style == null ? 'nil' : '"$style"';
    return '#<Block@${identityHashCode(this)} '
        '{context: :$context, content_model: :$contentModel, '
        'style: $styleRepr, $summary}>';
  }
}
