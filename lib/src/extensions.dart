/// Extension framework: processors, registries and groups.
///
/// Port of `lib/asciidoctor/extensions.rb`.
///
/// Extensions participate in AsciiDoc processing as follows:
///
/// 1. After the source lines are normalized, [Preprocessor]s modify or replace
///    the source lines before parsing begins. [IncludeProcessor]s are used to
///    process include directives for targets which they claim to handle.
/// 2. The parser parses the block-level content into an abstract syntax tree.
///    Custom blocks and block macros are processed by associated
///    [BlockProcessor]s and [BlockMacroProcessor]s, respectively.
/// 3. [TreeProcessor]s are run on the abstract syntax tree.
/// 4. Conversion of the document begins, at which point inline markup is
///    processed and converted. Custom inline macros are processed by
///    associated [InlineMacroProcessor]s.
/// 5. [Postprocessor]s modify or replace the converted document.
/// 6. The output is written to the output stream.
///
/// Extensions may be registered globally using [Extensions.register] or added
/// to a custom [Registry] and passed to a single document through the
/// `extensionRegistry` option.
///
/// A processor either extends its family class and overrides `process`, or
/// is built inline through a registry method's `build` callback, which
/// assigns the family's typed `onProcess` callback (e.g.
/// [TreeProcessor.onProcess]).
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/attribute_list.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/constants.dart';
import 'package:asciidart/src/context.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/helpers.dart';
import 'package:asciidart/src/inline.dart';
import 'package:asciidart/src/list.dart';
import 'package:asciidart/src/parser.dart';
import 'package:asciidart/src/reader.dart';
import 'package:asciidart/src/ruby_semantics.dart';
import 'package:asciidart/src/rx.dart';
import 'package:asciidart/src/section.dart';
import 'package:asciidart/src/substitutors.dart' as substitutors;
import 'package:asciidart/src/text_case.dart';
import 'package:meta/meta.dart';

/// How a macro processor receives the attribute list of its macro.
enum MacroAttributes {
  /// Parsed into named and positional attributes.
  parsed,

  /// As written, in the `text` attribute.
  text,
}

/// The configuration of a processor.
///
/// Each processor family reads the settings that apply to it: block
/// processors the [contexts] and the attribute settings, macro processors
/// the attribute settings, inline macro processors the [format] and
/// [regexp], and docinfo processors the [location].
final class ProcessorConfig {
  /// Creates a configuration.
  new({
    this.contentModel,
    this.macroAttributes = MacroAttributes.parsed,
    List<String>? positionalAttrs,
    Map<String, String>? defaultAttrs,
    Set<String>? contexts,
    this.format,
    this.regexp,
    this.location = 'head',
    this.preferred = false,
  }) : positionalAttrs = positionalAttrs ?? <String>[],
       defaultAttrs = defaultAttrs ?? <String, String>{},
       contexts = contexts ?? <String>{'open', 'paragraph'};

  /// How the content of a block is parsed (block processors). Defaults to
  /// [ContentModel.compound].
  ContentModel? contentModel;

  /// How a macro's attribute list is handled (macro processors).
  MacroAttributes macroAttributes;

  /// The names assigned to the positional attributes, in order.
  List<String> positionalAttrs;

  /// Attributes seeded before the attribute list is applied.
  Map<String, String> defaultAttrs;

  /// The block contexts a block processor handles (default: open blocks
  /// and paragraphs).
  Set<String> contexts;

  /// The inline macro syntax: `short` (no target) or `full` (default).
  String? format;

  /// An explicit pattern matching an inline macro.
  RegExp? regexp;

  /// Where docinfo content goes: `head` (default) or `footer`.
  String location;

  /// Whether the processor runs ahead of the others of its kind.
  bool preferred;
}

/// Assigns [name] at [index] in [names], growing the list with `null`
/// placeholders when the index lies past the end.
void _assignPositionalName(List<String?> names, String index, String name) {
  var idx = index == '@' ? names.length : parseLeadingInt(index);
  if (idx < 0) idx = names.length + idx;
  if (idx < 0) {
    throw RangeError('positional attribute index out of range: $index');
  }
  while (names.length <= idx) {
    names.add(null);
  }
  names[idx] = name;
}

/// An abstract base class for document and syntax processors.
///
/// Instances provide convenience methods for creating AST nodes, such as
/// [Block] and [Inline], and for parsing child content.
abstract class Processor {
  /// Creates a processor with [config].
  new([ProcessorConfig? config]) : config = config ?? ProcessorConfig();

  /// The configuration of this processor instance.
  final ProcessorConfig config;

  /// Whether a process callback was assigned through the registration DSL.
  bool get hasOnProcess;

  /// Marks this processor as preferred: it runs ahead of the other
  /// processors of its kind.
  void prefer() {
    config.preferred = true;
  }

  /// Creates a new [Section] node in the same manner as the parser.
  ///
  /// [parent] is the parent section (or document) of the new section,
  /// [title] its title, and [attrs] controls how the section is built: the
  /// `style` attribute sets the name of a special section (e.g. appendix),
  /// and the `id` attribute assigns an explicit ID. [generateId] set to
  /// `false` disables automatic ID generation. [level] assigns an explicit
  /// level (default: one greater than the parent level); [numbered] forces
  /// numbering on or off (default: per the `sectnums` document attribute).
  Section createSection(
    AbstractBlock parent,
    String title,
    Map<String, String> attrs, {
    int? level,
    bool? numbered,
    bool generateId = true,
  }) {
    final nodeDoc = parent.document;
    if (nodeDoc is! Document) {
      throw StateError(
        'Cannot create a section: parent is not attached to a document.',
      );
    }
    final doc = nodeDoc;
    final doctype = doc.doctype;
    final book = doctype == 'book';
    var sectLevel = level ?? (parent.level! + 1);
    String? sectname;
    var special = false;
    final style = attrs.remove('style');
    if (style != null) {
      if (book && style == 'abstract') {
        sectname = 'chapter';
        sectLevel = 1;
      } else {
        sectname = style;
        special = true;
        if (sectLevel == 0) sectLevel = 1;
      }
    } else if (book) {
      sectname = sectLevel == 0
          ? 'part'
          : (sectLevel > 1 ? 'section' : 'chapter');
    } else if (doctype == 'manpage' && downcase(title) == 'synopsis') {
      sectname = 'synopsis';
      special = true;
    } else {
      sectname = 'section';
    }
    final sect = (Section(parent, sectLevel))
      ..title = title
      ..sectname = sectname;
    if (special) {
      sect.special = true;
      if (numbered ?? (style == 'appendix')) {
        sect.numbered = true;
      } else if (numbered == null && doc.hasAttr('sectnums', 'all')) {
        sect
          ..numbered = true
          ..chapterNumbering = book && sectLevel == 1;
      }
    } else if (sectLevel > 0) {
      if (numbered ?? doc.hasAttr('sectnums')) {
        sect.numbered = !sect.special || (parent is Section && parent.numbered);
      }
    } else if (numbered ?? (book && doc.hasAttr('partnums'))) {
      sect.numbered = true;
    }
    if (generateId || attrs.containsKey('id')) {
      final id =
          attrs['id'] ??
          (doc.hasAttr('sectids')
              ? Section.generateId(sect.title ?? '', doc)
              : null);
      if (id != null) attrs['id'] = id;
      sect.id = id;
    }
    sect.updateAttributes(attrs);
    return sect;
  }

  /// Creates a block node and links it to [parent].
  ///
  /// [context] is the kind of block, [source] the raw source text, and
  /// [attrs] the block attributes. [contentModel] and [subs] mirror the
  /// corresponding [Block] constructor options.
  Block createBlock(
    AbstractBlock parent,
    BlockContext context,
    String? source,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => Block(
    parent,
    context,
    attributes: attrs,
    contentModel: contentModel,
    subs: subs,
    source: source,
  );

  /// Creates a block node from source [lines] and links it to [parent]
  /// (see [createBlock]).
  Block createBlockFromLines(
    AbstractBlock parent,
    BlockContext context,
    List<String> lines,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => Block(
    parent,
    context,
    attributes: attrs,
    contentModel: contentModel,
    subs: subs,
    lines: lines,
  );

  /// Creates a list node and links it to [parent].
  ///
  /// [context] is the kind of list and [attrs] the attributes to set on
  /// the list block.
  ListBlock createList(
    AbstractBlock parent,
    BlockContext context, [
    Map<String, String>? attrs,
  ]) {
    final list = ListBlock(parent, context);
    if (attrs != null) list.updateAttributes(attrs);
    return list;
  }

  /// Creates a list item node with [text] and links it to [parent].
  ListItem createListItem(AbstractBlock parent, [String? text]) =>
      ListItem(parent, text);

  /// Creates an image block node and links it to [parent].
  ///
  /// The `target` attribute sets the source of the image (required) and the
  /// `alt` attribute the alternative text (defaulting to the target
  /// basename with `_` and `-` rewritten to spaces). A `title` attribute is
  /// promoted to a captioned block title.
  Block createImageBlock(
    AbstractBlock parent,
    Map<String, String> attrs, {
    ContentModel? contentModel,
  }) {
    final target = attrs['target'];
    if (target == null) {
      throw ArgumentError(
        'Unable to create an image block, target attribute is required',
      );
    }
    if (!attrs.containsKey('alt')) {
      attrs['alt'] = attrs['default-alt'] = Helpers.basename(
        target,
        dropExtension: true,
      ).replaceAll('_', ' ').replaceAll('-', ' ');
    }
    final title = attrs.remove('title');
    final block = createBlock(
      parent,
      BlockContext.image,
      null,
      attrs,
      contentModel: contentModel,
    );
    if (title != null) {
      block
        ..title = title
        ..assignCaption(attrs.remove('caption'), figure: true);
    }
    return block;
  }

  /// Creates an inline node with [text] and binds it to [parent].
  ///
  /// [context] is the kind of inline element. For a quoted node the [type]
  /// defaults to `'unquoted'`; [target], [attributes] and [id] are stored
  /// on the node.
  Inline createInline(
    AbstractBlock? parent,
    InlineContext context,
    String? text, {
    String? type,
    String? target,
    Map<String, String>? attributes,
    String? id,
  }) => Inline(
    parent,
    context,
    text: text,
    type: context == InlineContext.quoted ? (type ?? 'unquoted') : type,
    target: target,
    attributes: attributes,
    id: id,
  );

  /// Parses the blocks in [reader] and attaches them to [parent].
  ///
  /// [attributes] seed the attributes of each parsed block. Returns
  /// [parent].
  AbstractBlock parseContent(
    AbstractBlock parent,
    Reader reader, [
    Map<String, String>? attributes,
  ]) {
    Parser.parseBlocks(
      reader,
      parent,
      attributes == null ? null : BlockAttributes(attributes),
    );
    return parent;
  }

  /// Parses the blocks in the AsciiDoc [source] and attaches them to
  /// [parent] (see [parseContent]).
  AbstractBlock parseSource(
    AbstractBlock parent,
    String source, [
    Map<String, String>? attributes,
  ]) => parseContent(parent, Reader.fromString(source), attributes);

  /// Parses the attrlist [attrlist] into a map of attributes.
  ///
  /// [block] supplies substitution context when [subAttributes] is set;
  /// [positionalAttributes] maps positional arguments to names.
  Map<String, String> parseAttributes(
    AbstractBlock block,
    String? attrlist, {
    List<String?> positionalAttributes = const [],
    bool subAttributes = false,
  }) {
    if (attrlist == null || attrlist.isEmpty) return <String, String>{};
    var source = attrlist;
    if (subAttributes && source.contains(attrRefHead)) {
      source = substitutors.subAttributes(block, source);
    }
    return Map<String, String>.of(
      AttributeList(source).parse(positionalAttributes),
    );
  }

  /// Creates a paragraph block (see [createBlock]).
  Block createParagraph(
    AbstractBlock parent,
    String? source,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => createBlock(
    parent,
    BlockContext.paragraph,
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
  );

  /// Creates an open block (see [createBlock]).
  Block createOpenBlock(
    AbstractBlock parent,
    String? source,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => createBlock(
    parent,
    BlockContext.open,
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
  );

  /// Creates an example block (see [createBlock]).
  Block createExampleBlock(
    AbstractBlock parent,
    String? source,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => createBlock(
    parent,
    BlockContext.example,
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
  );

  /// Creates a pass block (see [createBlock]).
  Block createPassBlock(
    AbstractBlock parent,
    String? source,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => createBlock(
    parent,
    BlockContext.pass,
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
  );

  /// Creates a listing block (see [createBlock]).
  Block createListingBlock(
    AbstractBlock parent,
    String? source,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => createBlock(
    parent,
    BlockContext.listing,
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
  );

  /// Creates a literal block (see [createBlock]).
  Block createLiteralBlock(
    AbstractBlock parent,
    String? source,
    Map<String, String> attrs, {
    ContentModel? contentModel,
    BlockSubs? subs,
  }) => createBlock(
    parent,
    BlockContext.literal,
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
  );

  /// Creates an anchor inline node (see [createInline]).
  Inline createAnchor(
    AbstractBlock? parent,
    String? text, {
    String? type,
    String? target,
    Map<String, String>? attributes,
    String? id,
  }) => createInline(
    parent,
    InlineContext.anchor,
    text,
    type: type,
    target: target,
    attributes: attributes,
    id: id,
  );

  /// Creates an unquoted (passthrough) inline node (see [createInline]).
  Inline createInlinePass(
    AbstractBlock? parent,
    String? text, {
    String? type,
    Map<String, String>? attributes,
  }) => createInline(
    parent,
    InlineContext.quoted,
    text,
    type: type,
    attributes: attributes,
  );
}

/// An abstract base class for the named (syntax) processor families
/// ([BlockProcessor], [BlockMacroProcessor] and [InlineMacroProcessor]).
///
/// Shares the `name` accessor and the syntax builder DSL (port of
/// `Extensions::SyntaxProcessorDsl`).
abstract class NamedProcessor extends Processor {
  /// Creates a named processor with [name] and [config].
  new([this.name, super.config]);

  /// The name this processor is registered under.
  String? name;

  /// Maps the positional attributes to [names], in order.
  void positionalAttributes(List<String> names) {
    config.positionalAttrs = List<String>.of(names);
  }

  /// Seeds the attributes map with [value].
  void defaultAttributes(Map<String, String> value) {
    config.defaultAttrs = Map<String, String>.of(value);
  }

  /// Declares how the macro attribute list maps to named attributes.
  ///
  /// Each of [specs] is `name=value` (a default, with an optional `index:`
  /// prefix assigning a positional slot), `index:name` (a positional slot)
  /// or a bare name (the next positional slot). The index is a number or
  /// `@` (the next slot). With no specs, both lists are reset to empty.
  void resolveAttributes([List<String> specs = const <String>[]]) {
    final names = <String?>[];
    final defaults = <String, String>{};
    for (final arg in specs) {
      final equals = arg.indexOf('=');
      if (equals != -1) {
        var name = arg.substring(0, equals);
        final value = arg.substring(equals + 1);
        final colon = name.indexOf(':');
        if (colon != -1) {
          final index = name.substring(0, colon);
          name = name.substring(colon + 1);
          _assignPositionalName(names, index, name);
        }
        defaults[name] = value;
      } else {
        final colon = arg.indexOf(':');
        if (colon != -1) {
          final index = arg.substring(0, colon);
          _assignPositionalName(names, index, arg.substring(colon + 1));
        } else {
          names.add(arg);
        }
      }
    }
    config
      ..positionalAttrs = [for (final name in names) ?name]
      ..defaultAttrs = defaults;
  }
}

/// The process callback of a [Preprocessor] built through the
/// registration DSL.
typedef PreprocessorCallback = Reader? Function(
  Document document,
  Reader reader,
);

/// Preprocessors run after the source text is split into lines and
/// normalized, but before parsing begins.
///
/// Asciidoctor passes the document and the document's [Reader] to [process].
/// The preprocessor can modify the reader as necessary and return `null`
/// (or the same reader), or return a substitute reader.
class Preprocessor extends Processor {
  /// Creates a preprocessor with [config].
  new([super.config]);

  /// The process callback assigned through the registration DSL.
  PreprocessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// Processes [document] and [reader], returning a substitute reader or
  /// `null` to keep [reader].
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Reader? process(Document document, Reader reader) {
    final handler = onProcess;
    if (handler != null) return handler(document, reader);
    throw UnimplementedError(
      'Preprocessor subclass $runtimeType must implement the process method',
    );
  }
}

/// The process callback of a [TreeProcessor] built through the
/// registration DSL.
typedef TreeProcessorCallback = Document? Function(Document document);

/// Tree processors run on the [Document] after the source has been parsed
/// into an abstract syntax tree.
class TreeProcessor extends Processor {
  /// Creates a tree processor with [config].
  new([super.config]);

  /// The process callback assigned through the registration DSL.
  TreeProcessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// Processes [document], returning a replacement document or `null` to
  /// keep [document].
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Document? process(Document document) {
    final handler = onProcess;
    if (handler != null) return handler(document);
    throw UnimplementedError(
      'TreeProcessor subclass $runtimeType must implement the process method',
    );
  }
}

/// The process callback of a [Postprocessor] built through the
/// registration DSL.
typedef PostprocessorCallback = String Function(
  Document document,
  String output,
);

/// Postprocessors run after the document is converted, but before it is
/// written to the output stream.
///
/// Asciidoctor passes the converted `output` to [process], which modifies it
/// as necessary and returns the replacement.
class Postprocessor extends Processor {
  /// Creates a postprocessor with [config].
  new([super.config]);

  /// The process callback assigned through the registration DSL.
  PostprocessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// Processes the converted [output] of [document], returning the
  /// replacement output.
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  String process(Document document, String output) {
    final handler = onProcess;
    if (handler != null) return handler(document, output);
    throw UnimplementedError(
      'Postprocessor subclass $runtimeType must implement the process method',
    );
  }
}

/// The process callback of an [IncludeProcessor] built through the
/// registration DSL.
typedef IncludeProcessorCallback = void Function(
  Document document,
  PreprocessorReader reader,
  String target,
  Map<String, String> attributes,
);

/// Include processors handle `include::<target>[]` directives for targets
/// which they claim to handle.
///
/// When Asciidoctor comes across an include directive, it iterates through
/// the include processors and delegates the work of reading the content to
/// the first processor whose [handles] returns true.
class IncludeProcessor extends Processor {
  /// Creates an include processor with [config].
  new([super.config]);

  /// The process callback assigned through the registration DSL.
  IncludeProcessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// The handles callback assigned through the registration DSL.
  ///
  /// It receives the include target.
  bool Function(String target)? onHandles;

  /// Whether this processor handles the include [target].
  ///
  /// Runs [onHandles] when assigned through the registration DSL, else
  /// returns true.
  bool handles(String target) {
    final handler = onHandles;
    if (handler != null) return handler(target);
    return true;
  }

  /// Pushes the content for [target] onto [reader] (see
  /// [PreprocessorReader.pushInclude]).
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  void process(
    Document document,
    PreprocessorReader reader,
    String target,
    Map<String, String> attributes,
  ) {
    final handler = onProcess;
    if (handler != null) {
      handler(document, reader, target, attributes);
      return;
    }
    throw UnimplementedError(
      'IncludeProcessor subclass $runtimeType must implement the '
      'process method',
    );
  }
}

/// The process callback of a [DocinfoProcessor] built through the
/// registration DSL.
typedef DocinfoProcessorCallback = String? Function(Document document);

/// Docinfo processors add additional content to the header and/or footer of
/// the generated document.
///
/// The placement of docinfo content is controlled by the converter. When no
/// location is specified, the processor is assumed to add content to the
/// header.
class DocinfoProcessor extends Processor {
  /// Creates a docinfo processor with [config].
  new([super.config]);

  /// The process callback assigned through the registration DSL.
  DocinfoProcessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// Processes [document], returning the docinfo content (or `null` for
  /// none).
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  String? process(Document document) {
    final handler = onProcess;
    if (handler != null) return handler(document);
    throw UnimplementedError(
      'DocinfoProcessor subclass $runtimeType must implement the '
      'process method',
    );
  }
}

/// The process callback of a [BlockProcessor] built through the
/// registration DSL.
typedef BlockProcessorCallback = AbstractBlock? Function(
  AbstractBlock parent,
  Reader reader,
  Map<String, String> attributes,
);

/// Block processors handle delimited blocks and paragraphs that have a
/// custom name.
///
/// When Asciidoctor encounters a delimited block or paragraph with an
/// unrecognized name while parsing the document, it looks for a
/// [BlockProcessor] registered to handle this name and, if found, invokes
/// its [process] method to build a corresponding node in the document tree.
///
/// If [process] returns a [Block] whose content model is `'compound'` and
/// which contains at least one line, the parser parses those lines into
/// blocks and appends them to the returned block.
///
/// The [config] selects the [ProcessorConfig.contexts] the block applies
/// to (default: open blocks and paragraphs), its content model (default:
/// `compound`), and the positional and default attributes.
class BlockProcessor extends NamedProcessor {
  /// Creates a block processor with [name] and [config].
  new([super.name, super.config]) {
    config.contentModel ??= ContentModel.compound;
  }

  /// The process callback assigned through the registration DSL.
  BlockProcessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// Builds the node for the custom block, or returns `null` to drop it.
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  AbstractBlock? process(
    AbstractBlock parent,
    Reader reader,
    Map<String, String> attributes,
  ) {
    final handler = onProcess;
    if (handler != null) return handler(parent, reader, attributes);
    throw UnimplementedError(
      'BlockProcessor subclass $runtimeType must implement the process method',
    );
  }

  /// Binds this processor to the block [contexts].
  void contexts(Iterable<String> contexts) {
    config.contexts = Set<String>.of(contexts);
  }

  /// Binds this processor to the single block [context].
  void onContext(String context) {
    contexts(<String>[context]);
  }
}

/// The process callback of a [BlockMacroProcessor] built through the
/// registration DSL.
typedef BlockMacroProcessorCallback = AbstractBlock? Function(
  AbstractBlock parent,
  String target,
  Map<String, String> attributes,
);

/// The process callback of an [InlineMacroProcessor] built through the
/// registration DSL.
typedef InlineMacroProcessorCallback = Inline? Function(
  AbstractBlock parent,
  String target,
  Map<String, String> attributes,
);

/// An abstract base class for the macro processor families
/// ([BlockMacroProcessor] and [InlineMacroProcessor]).
///
/// The attribute list of the macro is parsed into attributes (content
/// model `attributes`, the default) or passed through as the `text`
/// attribute (content model `text`).
abstract class MacroProcessor extends NamedProcessor {
  /// Creates a macro processor with [name] and [config].
  new([super.name, super.config]);

  /// Declares how the macro attribute list maps to named attributes (see
  /// [NamedProcessor.resolveAttributes]) and selects the `attributes`
  /// content model.
  @override
  void resolveAttributes([List<String> specs = const <String>[]]) {
    super.resolveAttributes(specs);
    config.macroAttributes = MacroAttributes.parsed;
  }

  /// Passes the raw attribute list through as the `text` attribute
  /// instead of parsing it.
  void passAttributesAsText() {
    config.macroAttributes = MacroAttributes.text;
  }
}

/// Block macro processors handle block macros that have a custom name.
///
/// If [process] returns a [Block] whose content model is `'compound'` and
/// which contains at least one line, the parser parses those lines into
/// blocks and assigns them to the returned block.
class BlockMacroProcessor extends MacroProcessor {
  /// Creates a block macro processor with [name] and [config].
  new([super.name, super.config]);

  /// The process callback assigned through the registration DSL.
  BlockMacroProcessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// The name this processor is registered under.
  ///
  /// Reading the name validates it against [macroNameRx], throwing
  /// [ArgumentError] for a missing or illegal name.
  @override
  String? get name {
    final value = super.name;
    if (value == null || !macroNameRx.hasMatch(value)) {
      throw ArgumentError('invalid name for block macro: ${value ?? ''}');
    }
    return value;
  }

  /// Builds the node for the macro invocation, or returns `null` to drop
  /// it.
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  AbstractBlock? process(
    AbstractBlock parent,
    String target,
    Map<String, String> attributes,
  ) {
    final handler = onProcess;
    if (handler != null) return handler(parent, target, attributes);
    throw UnimplementedError(
      'BlockMacroProcessor subclass $runtimeType must implement the '
      'process method',
    );
  }
}

/// Inline macro processors handle inline macros that have a custom name.
class InlineMacroProcessor extends MacroProcessor {
  /// Creates an inline macro processor with [name] and [config].
  new([super.name, super.config]);

  /// The process callback assigned through the registration DSL.
  InlineMacroProcessorCallback? onProcess;

  @override
  bool get hasOnProcess => onProcess != null;

  /// Cache of resolved inline macro patterns by name and format.
  static final Map<String, RegExp> _rxCache = <String, RegExp>{};

  /// The pattern matching this macro in inline content.
  ///
  /// The pattern resolves lazily from the name and the format on first
  /// access and is then considered frozen.
  RegExp get regexp =>
      config.regexp ??= resolveRegexp(name ?? '', config.format);

  /// Resolves the inline macro pattern for [name] and [format].
  ///
  /// Throws [ArgumentError] for an illegal name. Resolved patterns are
  /// memoized.
  static RegExp resolveRegexp(String name, String? format) {
    if (!macroNameRx.hasMatch(name)) {
      throw ArgumentError('invalid name for inline macro: $name');
    }
    // The NUL separator keeps the composite key unambiguous.
    return _rxCache.putIfAbsent(
      '$name\x00${format ?? ''}',
      () => RegExp(
        '\\\\?$name:${format == 'short' ? '(){0}' : r'([^ \t\n\v\f\r]+?)'}\\[(|$ccAny*?[^\\\\])\\]',
      ),
    );
  }

  /// Builds the inline node for the macro invocation, or returns `null` to
  /// replace it with nothing.
  ///
  /// Runs [onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Inline? process(
    AbstractBlock parent,
    String target,
    Map<String, String> attributes,
  ) {
    final handler = onProcess;
    if (handler != null) return handler(parent, target, attributes);
    throw UnimplementedError(
      'InlineMacroProcessor subclass $runtimeType must implement the '
      'process method',
    );
  }
}

/// A registered processor: the processor [instance] and its [kind].
///
/// This is what gets stored in the extension registry when activated.
class ProcessorExtension<P extends Processor> {
  /// Creates an extension of [kind] for [instance].
  new(this.kind, this.instance);

  /// The extension kind (e.g. `'preprocessor'`, `'block_macro'`).
  final String kind;

  /// The processor.
  final P instance;

  /// The configuration of the processor.
  ProcessorConfig get config => instance.config;
}

/// A group used to register one or more extensions with the [Registry].
///
/// The group should be subclassed and registered with [Extensions.register].
/// Extensions are registered inside [activate].
abstract class ExtensionGroup {
  /// Registers this group's extensions with [registry].
  void activate(Registry registry);
}

/// The primary entry point into the extension system.
///
/// A registry holds the extensions which have been registered and activated,
/// has methods for registering or defining a processor, and looks up
/// extensions stored in the registry during parsing.
class Registry {
  /// Creates a registry holding the extension [groups] (by name).
  new([Map<String, void Function(Registry registry)>? groups])
    : groups = groups ?? <String, void Function(Registry registry)>{};

  /// The document on which the extensions in this registry are being used.
  Document? get document => _document;
  Document? _document;

  /// The extension groups registered with this registry, by name.
  final Map<String, void Function(Registry registry)> groups;

  List<ProcessorExtension<Preprocessor>>? _preprocessorExtensions;
  List<ProcessorExtension<TreeProcessor>>? _treeProcessorExtensions;
  List<ProcessorExtension<Postprocessor>>? _postprocessorExtensions;
  List<ProcessorExtension<IncludeProcessor>>? _includeProcessorExtensions;
  List<ProcessorExtension<DocinfoProcessor>>? _docinfoProcessorExtensions;
  Map<String, ProcessorExtension<BlockProcessor>>? _blockExtensions;
  Map<String, ProcessorExtension<BlockMacroProcessor>>? _blockMacroExtensions;
  Map<String, ProcessorExtension<InlineMacroProcessor>>? _inlineMacroExtensions;

  /// Activates all the global extension groups and the extension groups
  /// associated with this registry for [document].
  void activate(Document document) {
    if (_document != null) _reset();
    _document = document;
    for (final group in [...Extensions.groups.values, ...groups.values]) {
      group(this);
    }
  }

  /// Registers a [Preprocessor] with the registry: [processor], or a fresh
  /// one configured by [build] (which must assign
  /// [Preprocessor.onProcess]).
  ///
  /// Returns the extension stored in the registry.
  ProcessorExtension<Preprocessor> preprocessor({
    Preprocessor? processor,
    void Function(Preprocessor processor)? build,
  }) => _addDocumentProcessor(
    'preprocessor',
    _preprocessorExtensions ??= <ProcessorExtension<Preprocessor>>[],
    _resolve(processor, build, Preprocessor.new, 'preprocessor'),
  );

  /// Whether any [Preprocessor] extensions have been registered.
  bool get hasPreprocessors => _preprocessorExtensions != null;

  /// The [Preprocessor] extensions in this registry.
  List<ProcessorExtension<Preprocessor>> get preprocessors =>
      _preprocessorExtensions ?? <ProcessorExtension<Preprocessor>>[];

  /// Registers a [TreeProcessor] with the registry (see [preprocessor]).
  ProcessorExtension<TreeProcessor> treeProcessor({
    TreeProcessor? processor,
    void Function(TreeProcessor processor)? build,
  }) => _addDocumentProcessor(
    'tree_processor',
    _treeProcessorExtensions ??= <ProcessorExtension<TreeProcessor>>[],
    _resolve(processor, build, TreeProcessor.new, 'tree processor'),
  );

  /// Whether any [TreeProcessor] extensions have been registered.
  bool get hasTreeProcessors => _treeProcessorExtensions != null;

  /// The [TreeProcessor] extensions in this registry.
  List<ProcessorExtension<TreeProcessor>> get treeProcessors =>
      _treeProcessorExtensions ?? <ProcessorExtension<TreeProcessor>>[];

  /// Registers a [Postprocessor] with the registry (see [preprocessor]).
  ProcessorExtension<Postprocessor> postprocessor({
    Postprocessor? processor,
    void Function(Postprocessor processor)? build,
  }) => _addDocumentProcessor(
    'postprocessor',
    _postprocessorExtensions ??= <ProcessorExtension<Postprocessor>>[],
    _resolve(processor, build, Postprocessor.new, 'postprocessor'),
  );

  /// Whether any [Postprocessor] extensions have been registered.
  bool get hasPostprocessors => _postprocessorExtensions != null;

  /// The [Postprocessor] extensions in this registry.
  List<ProcessorExtension<Postprocessor>> get postprocessors =>
      _postprocessorExtensions ?? <ProcessorExtension<Postprocessor>>[];

  /// Registers an [IncludeProcessor] with the registry (see
  /// [preprocessor]).
  ProcessorExtension<IncludeProcessor> includeProcessor({
    IncludeProcessor? processor,
    void Function(IncludeProcessor processor)? build,
  }) => _addDocumentProcessor(
    'include_processor',
    _includeProcessorExtensions ??= <ProcessorExtension<IncludeProcessor>>[],
    _resolve(processor, build, IncludeProcessor.new, 'include processor'),
  );

  /// Whether any [IncludeProcessor] extensions have been registered.
  bool get hasIncludeProcessors => _includeProcessorExtensions != null;

  /// The [IncludeProcessor] extensions in this registry.
  List<ProcessorExtension<IncludeProcessor>> get includeProcessors =>
      _includeProcessorExtensions ?? <ProcessorExtension<IncludeProcessor>>[];

  /// Registers a [DocinfoProcessor] with the registry (see
  /// [preprocessor]).
  ProcessorExtension<DocinfoProcessor> docinfoProcessor({
    DocinfoProcessor? processor,
    void Function(DocinfoProcessor processor)? build,
  }) => _addDocumentProcessor(
    'docinfo_processor',
    _docinfoProcessorExtensions ??= <ProcessorExtension<DocinfoProcessor>>[],
    _resolve(processor, build, DocinfoProcessor.new, 'docinfo processor'),
  );

  /// Whether any [DocinfoProcessor] extensions have been registered,
  /// optionally selecting [location] (`'head'` or `'footer'`).
  bool hasDocinfoProcessors([String? location]) {
    final extensions = _docinfoProcessorExtensions;
    if (extensions == null) return false;
    if (location == null) return true;
    return extensions.any((ext) => ext.config.location == location);
  }

  /// The [DocinfoProcessor] extensions in this registry, optionally
  /// selecting [location] (`'head'` or `'footer'`).
  List<ProcessorExtension<DocinfoProcessor>> docinfoProcessors([
    String? location,
  ]) {
    final extensions = _docinfoProcessorExtensions;
    if (extensions == null) return <ProcessorExtension<DocinfoProcessor>>[];
    if (location == null) return extensions;
    return extensions.where((ext) => ext.config.location == location).toList();
  }

  /// Registers a [BlockProcessor] with the registry: [processor], or a
  /// fresh one configured by [build] (which must assign
  /// [BlockProcessor.onProcess]). [name] names the block, overriding the
  /// processor's own name.
  ///
  /// Returns the extension stored in the registry.
  ProcessorExtension<BlockProcessor> block({
    BlockProcessor? processor,
    String? name,
    void Function(BlockProcessor processor)? build,
  }) => _addSyntaxProcessor(
    'block',
    _blockExtensions ??= <String, ProcessorExtension<BlockProcessor>>{},
    _resolve(processor, build, BlockProcessor.new, 'block', name: name),
  );

  /// Whether any [BlockProcessor] extensions have been registered.
  bool get hasBlocks => _blockExtensions != null;

  /// The [BlockProcessor] extension matching the block [name] and
  /// [context], or `null` if no match is found.
  ProcessorExtension<BlockProcessor>? registeredForBlock(
    String name,
    String context,
  ) {
    final ext = _blockExtensions?[name];
    if (ext == null || !ext.config.contexts.contains(context)) return null;
    return ext;
  }

  /// The [BlockProcessor] extension registered for block content with
  /// [name], or `null` if no match is found.
  ProcessorExtension<BlockProcessor>? findBlockExtension(String name) =>
      _blockExtensions?[name];

  /// Registers a [BlockMacroProcessor] with the registry (see [block]).
  ProcessorExtension<BlockMacroProcessor> blockMacro({
    BlockMacroProcessor? processor,
    String? name,
    void Function(BlockMacroProcessor processor)? build,
  }) => _addSyntaxProcessor(
    'block_macro',
    _blockMacroExtensions ??=
        <String, ProcessorExtension<BlockMacroProcessor>>{},
    _resolve(
      processor,
      build,
      BlockMacroProcessor.new,
      'block macro',
      name: name,
    ),
  );

  /// Whether any [BlockMacroProcessor] extensions have been registered.
  bool get hasBlockMacros => _blockMacroExtensions != null;

  /// The [BlockMacroProcessor] extension matching the macro [name], or
  /// `null` if no match is found.
  ProcessorExtension<BlockMacroProcessor>? registeredForBlockMacro(
    String name,
  ) => _blockMacroExtensions?[name];

  /// Registers an [InlineMacroProcessor] with the registry (see [block]).
  ProcessorExtension<InlineMacroProcessor> inlineMacro({
    InlineMacroProcessor? processor,
    String? name,
    void Function(InlineMacroProcessor processor)? build,
  }) => _addSyntaxProcessor(
    'inline_macro',
    _inlineMacroExtensions ??=
        <String, ProcessorExtension<InlineMacroProcessor>>{},
    _resolve(
      processor,
      build,
      InlineMacroProcessor.new,
      'inline macro',
      name: name,
    ),
  );

  /// Whether any [InlineMacroProcessor] extensions have been registered.
  bool get hasInlineMacros => _inlineMacroExtensions != null;

  /// The [InlineMacroProcessor] extension matching the macro [name], or
  /// `null` if no match is found.
  ProcessorExtension<InlineMacroProcessor>? registeredForInlineMacro(
    String name,
  ) => _inlineMacroExtensions?[name];

  /// The [InlineMacroProcessor] extensions in this registry.
  List<ProcessorExtension<InlineMacroProcessor>> get inlineMacros =>
      (_inlineMacroExtensions ??
              const <String, ProcessorExtension<InlineMacroProcessor>>{})
          .values
          .toList();

  /// Moves the document processor [extension] ahead of the others of its
  /// kind. Returns [extension].
  ProcessorExtension<P> prefer<P extends Processor>(
    ProcessorExtension<P> extension,
  ) {
    final store = switch (extension.kind) {
      'preprocessor' => _preprocessorExtensions,
      'tree_processor' => _treeProcessorExtensions,
      'postprocessor' => _postprocessorExtensions,
      'include_processor' => _includeProcessorExtensions,
      'docinfo_processor' => _docinfoProcessorExtensions,
      _ => null,
    };
    if (store == null || !store.remove(extension)) {
      throw StateError(
        'Cannot prefer ${extension.kind} extension: it is not registered '
        'in this registry',
      );
    }
    store.insert(0, extension);
    return extension;
  }

  /// Returns [processor], or a fresh one from [create] configured by
  /// [build]; [name] names a syntax processor.
  static P _resolve<P extends Processor>(
    P? processor,
    void Function(P processor)? build,
    P Function() create,
    String kindName, {
    String? name,
  }) {
    if ((processor == null) == (build == null)) {
      throw ArgumentError(
        'Pass either a processor or a build callback to register a '
        '$kindName extension',
      );
    }
    final P instance;
    if (build != null) {
      instance = create();
      if (name != null && instance is NamedProcessor) instance.name = name;
      build(instance);
      if (!instance.hasOnProcess) {
        throw StateError(
          'No process callback assigned for $kindName extension',
        );
      }
    } else {
      instance = processor!;
      if (name != null && instance is NamedProcessor) instance.name = name;
    }
    if (instance is NamedProcessor && instance.name == null) {
      throw ArgumentError('No name specified for $kindName extension');
    }
    return instance;
  }

  /// Stores the document processor [instance] of [kind] in [store].
  static ProcessorExtension<P> _addDocumentProcessor<P extends Processor>(
    String kind,
    List<ProcessorExtension<P>> store,
    P instance,
  ) {
    final extension = ProcessorExtension<P>(kind, instance);
    if (instance.config.preferred) {
      store.insert(0, extension);
    } else {
      store.add(extension);
    }
    return extension;
  }

  /// Stores the syntax processor [instance] of [kind] in [store] under its
  /// name.
  static ProcessorExtension<P> _addSyntaxProcessor<P extends NamedProcessor>(
    String kind,
    Map<String, ProcessorExtension<P>> store,
    P instance,
  ) {
    final extension = ProcessorExtension<P>(kind, instance);
    // Reading the name validates it for block macros.
    store[instance.name!] = extension;
    return extension;
  }

  /// A copy of this registry in its current state, which a discovery pass
  /// activates in place of this one; the real run then activates this
  /// registry as if no pass had run.
  @internal
  Registry snapshot() => Registry(groups)
    .._document = _document
    .._preprocessorExtensions = _preprocessorExtensions?.toList()
    .._treeProcessorExtensions = _treeProcessorExtensions?.toList()
    .._postprocessorExtensions = _postprocessorExtensions?.toList()
    .._includeProcessorExtensions = _includeProcessorExtensions?.toList()
    .._docinfoProcessorExtensions = _docinfoProcessorExtensions?.toList()
    .._blockExtensions = _blockExtensions == null
        ? null
        : {..._blockExtensions!}
    .._blockMacroExtensions = _blockMacroExtensions == null
        ? null
        : {..._blockMacroExtensions!}
    .._inlineMacroExtensions = _inlineMacroExtensions == null
        ? null
        : {..._inlineMacroExtensions!};

  /// Clears all extension stores and detaches the document.
  void _reset() {
    _preprocessorExtensions = null;
    _treeProcessorExtensions = null;
    _postprocessorExtensions = null;
    _includeProcessorExtensions = null;
    _docinfoProcessorExtensions = null;
    _blockExtensions = null;
    _blockMacroExtensions = null;
    _inlineMacroExtensions = null;
    _document = null;
  }
}

/// Global entry point for the extension system: group registration and
/// standalone registry creation.
abstract final class Extensions {
  /// The globally registered extension groups by name.
  static Map<String, void Function(Registry registry)> get groups => _groups;
  static final Map<String, void Function(Registry registry)> _groups =
      <String, void Function(Registry registry)>{};

  static int _autoId = -1;

  /// Generates an automatic extension group name (`'extgrp0'`, ...).
  static String generateName() => 'extgrp${++_autoId}';

  /// Creates a standalone registry that is not globally registered.
  ///
  /// When [build] is given, it is stored under [name] (or a generated
  /// name) and runs when the registry is activated.
  static Registry create({String? name, void Function(Registry)? build}) {
    if (build == null) return Registry();
    return Registry({name ?? generateName(): build});
  }

  /// Registers an extension group globally under [name] (default: a
  /// generated name): the [group] instance or the [build] callback.
  ///
  /// Returns the name the group is registered under.
  static String register({
    String? name,
    ExtensionGroup? group,
    void Function(Registry registry)? build,
  }) {
    if ((group == null) == (build == null)) {
      throw ArgumentError('Pass either an extension group or a build callback');
    }
    final key = name ?? generateName();
    _groups[key] = build ?? group!.activate;
    return key;
  }

  /// Unregisters all globally registered extension groups.
  static void unregisterAll() {
    _groups.clear();
  }

  /// Unregisters the globally registered extension groups in [names].
  static void unregister(Iterable<String> names) {
    names.forEach(_groups.remove);
  }
}
