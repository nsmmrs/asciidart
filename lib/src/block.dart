/// Block-level content nodes in a parsed AsciiDoc document.
///
/// Port of `lib/asciidoctor/block.rb`.
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/abstract_node.dart';
import 'package:asciidart/src/core_ext.dart';
import 'package:asciidart/src/helpers.dart';

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

/// How a new [Block] resolves its substitutions.
///
/// Passed as the `subs` argument of the [Block] constructor; any value
/// resolves the substitutions eagerly. Leaving it out defers resolution to
/// the parser, which honors the `subs` attribute.
sealed class BlockSubs {
  const new();

  /// Applies no substitutions (ignores the `subs` attribute).
  const factory none() = _NoSubs;

  /// Honors the `subs` attribute, falling back to [defaults] and then to
  /// the built-in substitutions for the block's context.
  const factory defaults([List<String>? defaults]) = _DefaultSubs;

  /// Applies exactly [subs] (ignores the `subs` attribute).
  const factory fixed(List<String> subs) = _FixedSubs;

  /// Resolves the substitutions from [spec], a `subs` attribute value such
  /// as `'+quotes'` or `'normal,-replacements'`.
  const factory spec(String spec) = _SpecSubs;
}

final class _NoSubs extends BlockSubs {
  const new();
}

final class _DefaultSubs extends BlockSubs {
  const new([this.defaults]);

  final List<String>? defaults;
}

final class _FixedSubs extends BlockSubs {
  const new(this.subs);

  final List<String> subs;
}

final class _SpecSubs extends BlockSubs {
  const new(this.spec);

  final String spec;
}

/// Methods for managing AsciiDoc content blocks.
///
/// Port of `Asciidoctor::Block`.
class Block extends AbstractBlock {
  /// Creates a block with [parent] and [context].
  ///
  /// [contentModel] selects how [lines] are processed (`'compound'`,
  /// `'simple'`, `'verbatim'`, `'raw'` or `'empty'`), defaulting per
  /// [defaultContentModels] (`'simple'` when the context is unknown).
  /// [source] is the raw source text, or [lines] the source lines (only
  /// one may be given). [subs] resolves the substitutions eagerly (see
  /// [BlockSubs]); leaving it out defers resolution.
  new(
    super.parent,
    super.context, {
    super.attributes,
    String? contentModel,
    BlockSubs? subs,
    String? source,
    List<String>? lines,
  }) : assert(source == null || lines == null, 'pass source or lines'),
       lines = lines != null
           ? List<String>.of(lines)
           : source == null || source.isEmpty
           ? <String>[]
           : Helpers.prepareSourceString(source) {
    this.contentModel =
        contentModel ?? defaultContentModels[context] ?? 'simple';
    switch (subs) {
      case null:
        // Defer subs resolution; the subs attribute is honored later.
        // NOTE subs is initialized as an empty list by the super
        // constructor.
        defaultSubs = null;
        return;
      case _NoSubs():
        // Prevent subs from being resolved.
        defaultSubs = <String>[];
        attributes.remove('subs');
      case _DefaultSubs(:final defaults):
        // Subs attribute is honored; falls back to defaults, then to the
        // built-in defaults based on context.
        defaultSubs = defaults == null ? null : List<String>.of(defaults);
      case _FixedSubs(subs: final fixed):
        // Subs attribute is not honored.
        defaultSubs = List<String>.of(fixed);
        attributes.remove('subs');
      case _SpecSubs(:final spec):
        defaultSubs = null;
        attributes['subs'] = spec;
    }
    // Resolve the subs eagerly only if the subs option is specified.
    commitSubs();
  }

  /// The original content lines of this block, if applicable.
  List<String> lines;

  /// Substitution overrides consulted by `commitSubs`.
  ///
  /// Internal: `null` defers to the content model defaults, an empty list
  /// prevents substitutions, and any other value seeds them.
  List<String>? defaultSubs;

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
        return super.content();
      case 'simple':
        return applySubs(lines.join(lf), subs);
      case 'verbatim':
      case 'raw':
        // QUESTION could we use strip here instead of popping empty lines?
        // maybe apply_subs can know how to strip whitespace?
        final result = applySubsToLines(lines, subs);
        if (result.length < 2) return result.isEmpty ? '' : result[0];
        while (result.isNotEmpty && result.first.trimRightAscii().isEmpty) {
          result.removeAt(0);
        }
        while (result.isNotEmpty && result.last.trimRightAscii().isEmpty) {
          result.removeLast();
        }
        return result.join(lf);
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
    return 'Block(context: $context, contentModel: $contentModel, '
        'style: ${debugQuote(style)}, $summary)';
  }
}
