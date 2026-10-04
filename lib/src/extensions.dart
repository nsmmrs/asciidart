// Deprecated aliases mirror Ruby; removed only when upstream removes them.
// ignore_for_file: remove_deprecations_in_breaking_versions
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
/// to a custom [Registry] and passed as an option to a single processor.
///
/// ## Dart adaptations
///
/// * Ruby symbols become strings, in both config keys and values
///   (e.g. `:content_model` / `:compound` become `'content_model'` /
///   `'compound'`).
/// * Ruby classes passed for registration (e.g. `registry.preprocessor
///   SamplePreprocessor`) cannot be instantiated reflectively in Dart, so a
///   factory function or typedef tear-off (e.g. `SamplePreprocessor.new`) or
///   an instance is passed instead. String class names resolve through the
///   factory table populated by [Extensions.registerProcessorFactory].
/// * Ruby blocks become callbacks: the registration block receives the
///   processor instance (e.g. `registry.block(name: 'shout', build: (p) {...})`)
///   and the `process do ... end` form becomes an assignment to
///   [Processor.onProcess].
/// * Class-level `option` defaults from Ruby (`Processor.option`) are
///   expressed by merging defaults in the subclass constructor.
/// * `registeredForBlock`, [Registry.registeredForBlockMacro] and
///   [Registry.registeredForInlineMacro] return `null` instead of Ruby's
///   `false` when no extension matches.
library;

import 'package:asciidoctor/src/abstract_block.dart';
import 'package:asciidoctor/src/attribute_list.dart';
import 'package:asciidoctor/src/block.dart';
import 'package:asciidoctor/src/constants.dart';
import 'package:asciidoctor/src/core_ext.dart';
import 'package:asciidoctor/src/document.dart';
import 'package:asciidoctor/src/helpers.dart';
import 'package:asciidoctor/src/inline.dart';
import 'package:asciidoctor/src/list.dart';
import 'package:asciidoctor/src/parser.dart';
import 'package:asciidoctor/src/reader.dart';
import 'package:asciidoctor/src/rx.dart';
import 'package:asciidoctor/src/section.dart';
import 'package:asciidoctor/src/substitutors.dart' as substitutors;

/// Sentinel distinguishing a missing `numbered` argument from an explicit
/// value in [Processor.createSection] (mirrors `Hash#fetch` with a default).
const Object _absent = Object();

/// Converts a loosely-typed config [map] to string keys.
Map<String, Object?> _asConfig(Map<dynamic, dynamic> map) =>
    map.map((key, value) => MapEntry(key.toString(), value));

/// Ruby `String#to_i` semantics for a positional index: an optional sign and
/// leading digits, else 0.
int _rubyToInt(String value) {
  final match = RegExp(r'^\s*[+-]?\d+').firstMatch(value);
  if (match == null) return 0;
  return int.tryParse(match.group(0)!.trim()) ?? 0;
}

/// Assigns [name] at [index] in [names], growing the list with `null`
/// placeholders when the index lies past the end (mirrors Ruby's `ary`idx` =
/// name` padding semantics).
void _assignPositionalName(List<String?> names, String index, String name) {
  var idx = index == '@' ? names.length : _rubyToInt(index);
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
/// [Block] and [Inline], and for parsing child content. Configuration
/// defaults declared with [option] apply to the instance; subclass
/// constructors merge class-wide defaults underneath any explicitly passed
/// [config] (the Dart equivalent of Ruby's `Processor.option` class-level
/// defaults).
class Processor {
  /// Creates a processor with [config].
  new([Map<String, Object?>? config])
    : config = Map<String, Object?>.of(config ?? const <String, Object?>{});

  /// The configuration of this processor instance.
  final Map<String, Object?> config;

  /// The process callback assigned through the registration DSL.
  ///
  /// This is the Dart equivalent of Ruby's `process do ... end` block. Each
  /// processor family invokes it from its `process` method with that
  /// family's arguments; a subclass that overrides `process` never consults
  /// it.
  Function? onProcess;

  /// Merges [config] into this processor's configuration.
  void updateConfig(Map<String, Object?> config) {
    this.config.addAll(config);
  }

  /// Assigns [value] as the configuration [key] on this processor.
  ///
  /// This is the instance-level DSL counterpart of Ruby's `option` (see the
  /// library docs for how class-level defaults are expressed instead).
  void option(String key, Object? value) {
    config[key] = value;
  }

  /// Creates a new [Section] node in the same manner as the parser.
  ///
  /// [parent] is the parent section (or document) of the new section,
  /// [title] its title, and [attrs] controls how the section is built: the
  /// `style` attribute sets the name of a special section (e.g. appendix),
  /// and the `id` attribute assigns an explicit ID (or disables automatic ID
  /// generation when `false`). [level] assigns an explicit level (defaulting
  /// to one greater than the parent level); [numbered] forces numbering
  /// (defaulting to the state of the `sectnums` document attribute). An
  /// omitted [numbered] is distinguished from an explicit `false`, exactly
  /// like Ruby's `opts.fetch :numbered`.
  Section createSection(
    AbstractBlock parent,
    String title,
    Map<String, Object?> attrs, {
    int? level,
    Object? numbered = _absent,
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
    if (isTruthy(style)) {
      final styleName = style.toString();
      if (book && styleName == 'abstract') {
        sectname = 'chapter';
        sectLevel = 1;
      } else {
        sectname = styleName;
        special = true;
        if (sectLevel == 0) sectLevel = 1;
      }
    } else if (book) {
      sectname = sectLevel == 0
          ? 'part'
          : (sectLevel > 1 ? 'section' : 'chapter');
    } else if (doctype == 'manpage' && title.toLowerCase() == 'synopsis') {
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
      final numberedValue = identical(numbered, _absent)
          ? (style.toString() == 'appendix')
          : numbered;
      if (isTruthy(numberedValue)) {
        sect.numbered = true;
      } else if (identical(numbered, _absent) &&
          doc.hasAttr('sectnums', 'all')) {
        sect.numbered = book && sectLevel == 1 ? 'chapter' : true;
      }
    } else if (sectLevel > 0) {
      final numberedValue = identical(numbered, _absent)
          ? doc.hasAttr('sectnums')
          : numbered;
      if (isTruthy(numberedValue)) {
        if (sect.special) {
          final parentNumbered = parent is Section ? parent.numbered : null;
          sect.numbered = isTruthy(parentNumbered) ? true : parentNumbered;
        } else {
          sect.numbered = true;
        }
      }
    } else {
      final numberedValue = identical(numbered, _absent)
          ? (book && doc.hasAttr('partnums'))
          : numbered;
      if (isTruthy(numberedValue)) {
        sect.numbered = true;
      }
    }
    final id = attrs['id'];
    if (id == false) {
      attrs.remove('id');
    } else {
      final newId = isTruthy(id)
          ? id.toString()
          : (doc.hasAttr('sectids') ? Section.generateId(title, doc) : null);
      attrs['id'] = newId;
      sect.id = newId;
    }
    sect.updateAttributes(attrs);
    return sect;
  }

  /// Creates a block node and links it to [parent].
  ///
  /// [context] is the block context (e.g. `'paragraph'`), [source] the raw
  /// source as a string or a list of lines, and [attrs] the block
  /// attributes. [contentModel], [subs] and [defaultSubs] mirror the
  /// corresponding [Block] constructor options.
  Block createBlock(
    AbstractBlock parent,
    String context,
    Object? source,
    Map<String, Object?> attrs, {
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
  }) {
    return Block(
      parent,
      context,
      attributes: attrs,
      contentModel: contentModel,
      subs: subs,
      defaultSubs: defaultSubs,
      source: source,
    );
  }

  /// Creates a list node and links it to [parent].
  ///
  /// [context] is the list context (e.g. `'ulist'`, `'olist'`, `'colist'`,
  /// `'dlist'`) and [attrs] the attributes to set on the list block.
  ListBlock createList(
    AbstractBlock parent,
    String context, [
    Map<String, Object?>? attrs,
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
    Map<String, Object?> attrs, {
    String? contentModel,
  }) {
    final target = attrs['target'];
    if (!isTruthy(target)) {
      throw ArgumentError(
        'Unable to create an image block, target attribute is required',
      );
    }
    if (!isTruthy(attrs['alt'])) {
      attrs['alt'] = attrs['default-alt'] = Helpers.basename(
        target.toString(),
        true,
      ).replaceAll('_', ' ').replaceAll('-', ' ');
    }
    final title = attrs.containsKey('title') ? attrs.remove('title') : null;
    final block = createBlock(
      parent,
      'image',
      null,
      attrs,
      contentModel: contentModel,
    );
    if (isTruthy(title)) {
      block
        ..title = title.toString()
        ..assignCaption(attrs.remove('caption'), 'figure');
    }
    return block;
  }

  /// Creates an inline node with [text] and binds it to [parent].
  ///
  /// [context] is the inline context (e.g. `'quoted'`, `'anchor'`). For a
  /// `'quoted'` node the [type] defaults to `'unquoted'`; [target],
  /// [attributes] and [id] are stored on the node.
  Inline createInline(
    AbstractBlock? parent,
    String context,
    String? text, {
    String? type,
    String? target,
    Map<String, Object?>? attributes,
    String? id,
  }) {
    return Inline(
      parent,
      context,
      text: text,
      type: context == 'quoted' ? (type ?? 'unquoted') : type,
      target: target,
      attributes: attributes,
      id: id,
    );
  }

  /// Parses blocks in [content] and attaches the blocks to [parent].
  ///
  /// [content] is a [Reader] or the source as a string or list of lines;
  /// [attributes] are passed through to the parser. Returns [parent].
  ///
  /// Port of `Extensions::Processor#parse_content`
  /// (lib/asciidoctor/extensions.rb:227-231).
  AbstractBlock parseContent(
    AbstractBlock parent,
    Object? content, [
    Map<String, Object?>? attributes,
  ]) {
    final reader = content is Reader ? content : Reader(content);
    Parser.parseBlocks(
      reader,
      parent,
      attributes == null ? null : Map<Object, Object?>.of(attributes),
    );
    return parent;
  }

  /// Parses the attrlist [attrlist] into a map of attributes.
  ///
  /// [block] supplies substitution context when [subAttributes] is set;
  /// [positionalAttributes] maps positional arguments to names.
  Map<Object, String?> parseAttributes(
    AbstractBlock block,
    String? attrlist, {
    List<String?> positionalAttributes = const [],
    bool subAttributes = false,
  }) {
    if (attrlist == null || attrlist.isEmpty) return <Object, String?>{};
    // Port of `Extensions::Processor#parse_attributes`
    // (lib/asciidoctor/extensions.rb:242-246).
    var source = attrlist;
    if (subAttributes && source.contains(attrRefHead)) {
      source = substitutors.subAttributes(block, source);
    }
    return AttributeList(source).parse(positionalAttributes);
  }

  /// Creates a paragraph block (delegate of [createBlock]).
  Block createParagraph(
    AbstractBlock parent,
    Object? source,
    Map<String, Object?> attrs, {
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
  }) => createBlock(
    parent,
    'paragraph',
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
    defaultSubs: defaultSubs,
  );

  /// Creates an open block (delegate of [createBlock]).
  Block createOpenBlock(
    AbstractBlock parent,
    Object? source,
    Map<String, Object?> attrs, {
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
  }) => createBlock(
    parent,
    'open',
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
    defaultSubs: defaultSubs,
  );

  /// Creates an example block (delegate of [createBlock]).
  Block createExampleBlock(
    AbstractBlock parent,
    Object? source,
    Map<String, Object?> attrs, {
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
  }) => createBlock(
    parent,
    'example',
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
    defaultSubs: defaultSubs,
  );

  /// Creates a pass block (delegate of [createBlock]).
  Block createPassBlock(
    AbstractBlock parent,
    Object? source,
    Map<String, Object?> attrs, {
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
  }) => createBlock(
    parent,
    'pass',
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
    defaultSubs: defaultSubs,
  );

  /// Creates a listing block (delegate of [createBlock]).
  Block createListingBlock(
    AbstractBlock parent,
    Object? source,
    Map<String, Object?> attrs, {
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
  }) => createBlock(
    parent,
    'listing',
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
    defaultSubs: defaultSubs,
  );

  /// Creates a literal block (delegate of [createBlock]).
  Block createLiteralBlock(
    AbstractBlock parent,
    Object? source,
    Map<String, Object?> attrs, {
    String? contentModel,
    Object? subs = subsAbsent,
    Object? defaultSubs,
  }) => createBlock(
    parent,
    'literal',
    source,
    attrs,
    contentModel: contentModel,
    subs: subs,
    defaultSubs: defaultSubs,
  );

  /// Creates an anchor inline node (delegate of [createInline]).
  Inline createAnchor(
    AbstractBlock? parent,
    String? text, {
    String? type,
    String? target,
    Map<String, Object?>? attributes,
    String? id,
  }) => createInline(
    parent,
    'anchor',
    text,
    type: type,
    target: target,
    attributes: attributes,
    id: id,
  );

  /// Creates an unquoted (passthrough) inline node (delegate of
  /// [createInline]).
  Inline createInlinePass(
    AbstractBlock? parent,
    String? text, {
    String? type,
    Map<String, Object?>? attributes,
  }) =>
      createInline(parent, 'quoted', text, type: type, attributes: attributes);
}

/// Builder DSL shared by the document processor families
/// ([Preprocessor], [TreeProcessor], [Postprocessor], [IncludeProcessor] and
/// [DocinfoProcessor]).
///
/// Port of `Extensions::DocumentProcessorDsl` (whose `process` half is
/// [Processor.onProcess] in Dart).
mixin DocumentProcessorDsl on Processor {
  /// Marks this processor as preferred, moving it to the front of its
  /// registry list.
  void prefer() {
    option('position', '>>');
  }
}

/// An abstract base class for the named (syntax) processor families
/// ([BlockProcessor] and [MacroProcessor]).
///
/// Ruby gives [BlockProcessor] and `MacroProcessor` independent `name`
/// accessors; this intermediate base only shares the Dart implementation of
/// that contract and the syntax builder DSL (port of
/// `Extensions::SyntaxProcessorDsl`, whose `process` half is
/// [Processor.onProcess] in Dart).
abstract class NamedProcessor extends Processor {
  /// Creates a named processor with [config].
  new([super.config]);

  /// The name this processor is registered under.
  String? name;

  /// Sets the name this processor is registered under.
  ///
  /// A method (not a setter) for extension-DSL parity: extension authors
  /// call `processor.named('...')`, mirroring the Ruby/JS API.
  // ignore: use_setters_to_change_properties
  void named(String value) {
    name = value;
  }

  /// Sets the content model (e.g. `'compound'`, `'simple'`, `'raw'`).
  void contentModel(String value) {
    option('content_model', value);
  }

  /// Alias of [contentModel].
  void parseContentAs(String value) {
    contentModel(value);
  }

  /// Maps positional attributes to [values] (a single value or a list).
  void positionalAttributes(Object values) {
    final items = values is List ? values : [values];
    final flat = <Object?>[];
    for (final item in items) {
      if (item is List) {
        flat.addAll(item);
      } else {
        flat.add(item);
      }
    }
    option('positional_attrs', [for (final item in flat) item.toString()]);
  }

  /// Alias of [positionalAttributes].
  void namePositionAttributes(Object values) {
    positionalAttributes(values);
  }

  /// Alias of [positionalAttributes].
  @Deprecated('Use namePositionAttributes instead.')
  void positionalAttrs(Object values) {
    positionalAttributes(values);
  }

  /// Seeds the attributes map with [value].
  void defaultAttributes(Map<Object, Object?> value) {
    option('default_attrs', value);
  }

  /// Alias of [defaultAttributes].
  @Deprecated('Use defaultAttributes instead.')
  void defaultAttrs(Map<Object, Object?> value) {
    defaultAttributes(value);
  }

  /// Declares how the macro attribute list maps to named attributes.
  ///
  /// [args] is a single specification or a list of them (the Dart spelling
  /// of Ruby's variadic arguments): `name=value` pairs seed defaults (with
  /// an optional `index:` prefix assigning a positional slot), `index:name`
  /// pairs assign positional slots, and bare names append positional slots.
  /// A map assigns positional slots from `index:name` keys and seeds
  /// defaults from truthy values. With no arguments, both lists are reset
  /// to empty.
  void resolveAttributes([Object? args]) {
    final Object? spec;
    if (args == null) {
      // Zero-argument default (Ruby: args.fetch 0, true). An explicit null
      // is indistinguishable from an omitted argument in Dart and takes the
      // same path.
      spec = true;
    } else if (args is String) {
      // Rewrap a single string (Ruby: to_sym branch).
      spec = [args];
    } else {
      spec = args;
    }
    if (spec == true) {
      option('positional_attrs', <String>[]);
      option('default_attrs', <String, Object?>{});
    } else if (spec is List) {
      final names = <String?>[];
      final defaults = <String, Object?>{};
      for (final item in spec) {
        final arg = item.toString();
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
      option('positional_attrs', [for (final name in names) ?name]);
      option('default_attrs', defaults);
    } else if (spec is Map) {
      final names = <String?>[];
      final defaults = <String, Object?>{};
      spec.forEach((key, value) {
        var name = key.toString();
        final colon = name.indexOf(':');
        if (colon != -1) {
          final index = name.substring(0, colon);
          name = name.substring(colon + 1);
          _assignPositionalName(names, index, name);
        }
        if (isTruthy(value)) defaults[name] = value;
      });
      option('positional_attrs', [for (final name in names) ?name]);
      option('default_attrs', defaults);
    } else {
      throw ArgumentError(
        'unsupported attributes specification for macro: $spec',
      );
    }
  }

  /// Alias of [resolveAttributes].
  @Deprecated('Use resolveAttributes instead.')
  void resolvesAttributes([Object? args]) {
    resolveAttributes(args);
  }
}

/// Preprocessors run after the source text is split into lines and
/// normalized, but before parsing begins.
///
/// Asciidoctor passes the document and the document's [Reader] to [process].
/// The preprocessor can modify the reader as necessary and either return the
/// same reader (or a falsy value, which is equivalent) or a reference to a
/// substitute reader.
///
/// Preprocessor implementations must extend [Preprocessor].
class Preprocessor extends Processor with DocumentProcessorDsl {
  /// Creates a preprocessor with [config].
  new([super.config]);

  /// Processes [document] and [reader].
  ///
  /// Runs [Processor.onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Object? process(Document document, Reader reader) {
    final handler = onProcess;
    if (handler != null) return Function.apply(handler, [document, reader]);
    throw UnimplementedError(
      'Preprocessor subclass $runtimeType must implement the process method',
    );
  }
}

/// Tree processors run on the [Document] after the source has been parsed
/// into an abstract syntax tree.
///
/// Tree processor implementations must extend [TreeProcessor].
class TreeProcessor extends Processor with DocumentProcessorDsl {
  /// Creates a tree processor with [config].
  new([super.config]);

  /// Processes [document].
  ///
  /// Runs [Processor.onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Object? process(Document document) {
    final handler = onProcess;
    if (handler != null) return Function.apply(handler, [document]);
    throw UnimplementedError(
      'TreeProcessor subclass $runtimeType must implement the process method',
    );
  }
}

/// Alias of [TreeProcessor] for backwards compatibility.
@Deprecated('Use TreeProcessor instead.')
typedef Treeprocessor = TreeProcessor;

/// Postprocessors run after the document is converted, but before it is
/// written to the output stream.
///
/// Asciidoctor passes the converted `output` to [process], which modifies it
/// as necessary and returns the replacement.
///
/// Postprocessor implementations must extend [Postprocessor].
class Postprocessor extends Processor with DocumentProcessorDsl {
  /// Creates a postprocessor with [config].
  new([super.config]);

  /// Processes the converted [output] of [document].
  ///
  /// Runs [Processor.onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Object? process(Document document, String output) {
    final handler = onProcess;
    if (handler != null) return Function.apply(handler, [document, output]);
    throw UnimplementedError(
      'Postprocessor subclass $runtimeType must implement the process method',
    );
  }
}

/// Include processors handle `include::<target>[]` directives for targets
/// which they claim to handle.
///
/// When Asciidoctor comes across an include directive, it iterates through
/// the include processors and delegates the work of reading the content to
/// the first processor whose [handles] returns true.
///
/// Include processor implementations must extend [IncludeProcessor].
class IncludeProcessor extends Processor
    with DocumentProcessorDsl
    implements ReaderIncludeProcessor {
  /// Creates an include processor with [config].
  new([super.config]);

  /// The handles callback assigned through the registration DSL.
  ///
  /// This is the Dart equivalent of Ruby's `handles? do ... end` block. It
  /// always receives the document and the target (Ruby's single-argument
  /// legacy form has no Dart counterpart; there is no legacy adapter).
  bool Function(ReaderDocument, String)? onHandles;

  /// Whether this processor handles the include [target].
  ///
  /// Runs [onHandles] when assigned through the registration DSL, else
  /// returns true.
  @override
  bool handles(ReaderDocument document, String target) {
    final handler = onHandles;
    if (handler != null) return handler(document, target);
    return true;
  }

  /// Pushes the content for [target] onto [reader].
  ///
  /// Runs [Processor.onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  @override
  Object? process(
    ReaderDocument document,
    PreprocessorReader reader,
    String target,
    Map<Object, String?> attributes,
  ) {
    final handler = onProcess;
    if (handler != null) {
      return Function.apply(handler, [document, reader, target, attributes]);
    }
    throw UnimplementedError(
      'IncludeProcessor subclass $runtimeType must implement the process method',
    );
  }
}

/// Docinfo processors add additional content to the header and/or footer of
/// the generated document.
///
/// The placement of docinfo content is controlled by the converter. When no
/// location is specified, the processor is assumed to add content to the
/// header.
///
/// Docinfo processor implementations must extend [DocinfoProcessor].
class DocinfoProcessor extends Processor with DocumentProcessorDsl {
  /// Creates a docinfo processor with [config].
  new([super.config]) {
    if (!isTruthy(config['location'])) config['location'] = 'head';
  }

  /// Processes [document], returning the docinfo content.
  ///
  /// Runs [Processor.onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Object? process(Document document) {
    final handler = onProcess;
    if (handler != null) return Function.apply(handler, [document]);
    throw UnimplementedError(
      'DocinfoProcessor subclass $runtimeType must implement the process method',
    );
  }

  /// Sets the docinfo location (`'head'` or `'footer'`).
  void atLocation(String value) {
    option('location', value);
  }
}

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
/// Recognized options:
///
/// * `'name'`: the name of the block (required).
/// * `'contexts'`: the block contexts on which this style can be used
///   (default: `{'open', 'paragraph'}`).
/// * `'content_model'`: the structure of the content supported in this block
///   (default: `'compound'`).
/// * `'positional_attrs'`: attribute names used to map positional attributes.
/// * `'default_attrs'`: attribute names and values used to seed the
///   attributes map.
///
/// Block processor implementations must extend [BlockProcessor].
class BlockProcessor extends NamedProcessor {
  /// Creates a block processor with [name] and [config].
  ///
  /// The [name] falls back to the `'name'` config entry. A missing
  /// `'contexts'` entry defaults to `{'open', 'paragraph'}`; a single
  /// string or any iterable is normalized to a set of strings. A missing
  /// `'content_model'` entry defaults to `'compound'`.
  new([String? name, Map<String, Object?>? config]) : super(config) {
    this.name = name ?? this.config['name']?.toString();
    final contexts = this.config['contexts'];
    if (contexts == null) {
      this.config['contexts'] = <String>{'open', 'paragraph'};
    } else if (contexts is String) {
      this.config['contexts'] = <String>{contexts};
    } else if (contexts is Iterable) {
      this.config['contexts'] = <String>{
        for (final context in contexts) context.toString(),
      };
    }
    if (!isTruthy(this.config['content_model'])) {
      this.config['content_model'] = 'compound';
    }
  }

  /// Builds the node for the custom block.
  ///
  /// Runs [Processor.onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Object? process(
    AbstractBlock parent,
    Reader reader,
    Map<String, Object?> attributes,
  ) {
    final handler = onProcess;
    if (handler != null) {
      return Function.apply(handler, [parent, reader, attributes]);
    }
    throw UnimplementedError(
      'BlockProcessor subclass $runtimeType must implement the process method',
    );
  }

  /// Binds this processor to the block [contexts] (a single context or a
  /// collection of them).
  void contexts(Object contexts) {
    final items = contexts is Iterable ? contexts : [contexts];
    option('contexts', <String>{
      for (final context in items) context.toString(),
    });
  }

  /// Alias of [contexts].
  void onContexts(Object contexts) {
    this.contexts(contexts);
  }

  /// Alias of [contexts].
  void onContext(Object context) {
    contexts(context);
  }

  /// Alias of [contexts].
  void bindTo(Object contexts) {
    this.contexts(contexts);
  }
}

/// An abstract base class for the macro processor families
/// ([BlockMacroProcessor] and [InlineMacroProcessor]).
class MacroProcessor extends NamedProcessor {
  /// Creates a macro processor with [name] and [config].
  ///
  /// The [name] falls back to the `'name'` config entry. A missing
  /// `'content_model'` entry defaults to `'attributes'`.
  new([String? name, Map<String, Object?>? config]) : super(config) {
    this.name = name ?? this.config['name']?.toString();
    if (!isTruthy(this.config['content_model'])) {
      this.config['content_model'] = 'attributes';
    }
  }

  /// Builds the node for the macro invocation.
  ///
  /// Runs [Processor.onProcess] when the processor was built through the
  /// registration DSL, else throws [UnimplementedError].
  Object? process(
    AbstractBlock parent,
    String target,
    Map<Object, Object?> attributes,
  ) {
    final handler = onProcess;
    if (handler != null) {
      return Function.apply(handler, [parent, target, attributes]);
    }
    throw UnimplementedError(
      'MacroProcessor subclass $runtimeType must implement the process method',
    );
  }

  /// Declares how the macro attribute list maps to named attributes.
  ///
  /// Extends [NamedProcessor.resolveAttributes]: passing `false` switches
  /// the content model to `'text'` (the raw attrlist is passed through as
  /// the `text` attribute) instead of resolving attributes.
  @override
  void resolveAttributes([Object? args]) {
    if (args == false) {
      option('content_model', 'text');
    } else {
      super.resolveAttributes(args);
      option('content_model', 'attributes');
    }
  }
}

/// Block macro processors handle block macros that have a custom name.
///
/// If [process] returns a [Block] whose content model is `'compound'` and
/// which contains at least one line, the parser parses those lines into
/// blocks and assigns them to the returned block.
///
/// Block macro processor implementations must extend [BlockMacroProcessor].
class BlockMacroProcessor extends MacroProcessor {
  /// Creates a block macro processor with [name] and [config].
  new([super.name, super.config]);

  /// The name this processor is registered under.
  ///
  /// Reading the name validates it against [macroNameRx], throwing
  /// [ArgumentError] for a missing or illegal name, exactly like Ruby.
  @override
  String? get name {
    final value = super.name;
    if (value == null || !macroNameRx.hasMatch(value)) {
      throw ArgumentError('invalid name for block macro: ${value ?? ''}');
    }
    return value;
  }
}

/// Inline macro processors handle inline macros that have a custom name.
///
/// Inline macro processor implementations must extend
/// [InlineMacroProcessor].
class InlineMacroProcessor extends MacroProcessor {
  /// Creates an inline macro processor with [name] and [config].
  new([super.name, super.config]);

  /// Cache of resolved inline macro patterns by name and format.
  static final Map<String, RegExp> _rxCache = <String, RegExp>{};

  /// The pattern matching this macro in inline content.
  ///
  /// The pattern resolves lazily from the name and the `'format'` config
  /// entry on first access and is then considered frozen.
  RegExp get regexp {
    final cached = config['regexp'];
    if (cached is RegExp) return cached;
    final resolved = resolveRegexp(
      name.toString(),
      config['format']?.toString(),
    );
    config['regexp'] = resolved;
    return resolved;
  }

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
        '\\\\?$name:${format == 'short' ? '(){0}' : r'(\S+?)'}\\[(|$ccAny*?[^\\\\])\\]',
      ),
    );
  }

  /// Sets the match format (`'short'` or `'full'`).
  void format(String value) {
    option('format', value);
  }

  /// Alias of [format].
  void matchFormat(String value) {
    format(value);
  }

  /// Alias of [format].
  @Deprecated('Use matchFormat instead.')
  void usingFormat(String value) {
    format(value);
  }

  /// Sets an explicit match pattern.
  void match(RegExp value) {
    option('regexp', value);
  }
}

/// A proxy object for an extension implementation such as a processor.
///
/// The proxy separates preparation of the extension instance from its usage.
/// It encapsulates the extension [kind] (e.g. `'block'`), its [config] map
/// and the extension [instance]. This proxy is what gets stored in the
/// extension registry when activated.
class Extension {
  /// Creates a proxy of [kind] for [instance] with [config].
  new(this.kind, this.instance, this.config);

  /// The extension kind (e.g. `'preprocessor'`, `'block_macro'`).
  final String kind;

  /// The extension instance.
  final Processor instance;

  /// The configuration map of the extension instance.
  final Map<String, Object?> config;
}

/// An [Extension] proxy that additionally stores a reference to the
/// processor's `process` method.
///
/// By storing this reference, both concrete extension implementations and
/// [Processor.onProcess] callbacks are accommodated uniformly.
class ProcessorExtension extends Extension {
  /// Creates a proxy of [kind] for [instance].
  ///
  /// [processMethod] defaults to a closure invoking the family's `process`
  /// method on [instance].
  new(String kind, Processor instance, [Function? processMethod])
    : processMethod = processMethod ?? _processMethodFor(kind, instance),
      super(kind, instance, instance.config);

  /// The bound `process` function of the extension instance.
  final Function processMethod;

  /// Builds the default [processMethod] closure for [kind] and [instance].
  static Function _processMethodFor(String kind, Processor instance) {
    switch (kind) {
      case 'preprocessor':
        return (Document document, Reader reader) =>
            (instance as Preprocessor).process(document, reader);
      case 'tree_processor':
        return (Document document) =>
            (instance as TreeProcessor).process(document);
      case 'postprocessor':
        return (Document document, String output) =>
            (instance as Postprocessor).process(document, output);
      case 'include_processor':
        return (
          ReaderDocument document,
          PreprocessorReader reader,
          String target,
          Map<Object, String?> attributes,
        ) => (instance as IncludeProcessor).process(
          document,
          reader,
          target,
          attributes,
        );
      case 'docinfo_processor':
        return (Document document) =>
            (instance as DocinfoProcessor).process(document);
      case 'block':
        return (
          AbstractBlock parent,
          Reader reader,
          Map<String, Object?> attributes,
        ) => (instance as BlockProcessor).process(parent, reader, attributes);
      case 'block_macro':
        return (
          AbstractBlock parent,
          String target,
          Map<Object, Object?> attributes,
        ) => (instance as BlockMacroProcessor).process(
          parent,
          target,
          attributes,
        );
      case 'inline_macro':
        return (
          AbstractBlock parent,
          String target,
          Map<Object, Object?> attributes,
        ) => (instance as InlineMacroProcessor).process(
          parent,
          target,
          attributes,
        );
      default:
        throw ArgumentError('Unknown extension kind: $kind');
    }
  }
}

/// A group used to register one or more extensions with the [Registry].
///
/// The group should be subclassed and registered with [Extensions.register],
/// either directly or as a factory. Extensions are registered inside
/// [activate].
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
  /// Creates a registry holding [groups].
  new([Map<String, Object?>? groups]) : groups = groups ?? <String, Object?>{};

  /// The document on which the extensions in this registry are being used.
  Document? get document => _document;
  Document? _document;

  /// The group factories, instances and callbacks registered with this
  /// registry.
  final Map<String, Object?> groups;

  List<ProcessorExtension>? _preprocessorExtensions;
  List<ProcessorExtension>? _treeProcessorExtensions;
  List<ProcessorExtension>? _postprocessorExtensions;
  List<ProcessorExtension>? _includeProcessorExtensions;
  List<ProcessorExtension>? _docinfoProcessorExtensions;
  Map<String, ProcessorExtension>? _blockExtensions;
  Map<String, ProcessorExtension>? _blockMacroExtensions;
  Map<String, ProcessorExtension>? _inlineMacroExtensions;

  /// Activates all the global extension groups and the extension groups
  /// associated with this registry.
  ///
  /// Each group is a `void Function(Registry)` callback, a zero-argument
  /// callback (invoked without the registry, for groups that register
  /// nothing), an [ExtensionGroup] instance, or an [ExtensionGroup]
  /// factory.
  void activate(Document document) {
    if (_document != null) _reset();
    _document = document;
    final extGroups = [...Extensions.groups.values, ...groups.values];
    for (final group in extGroups) {
      if (group is void Function(Registry)) {
        group(this);
      } else if (group is ExtensionGroup Function()) {
        group().activate(this);
      } else if (group is ExtensionGroup) {
        group.activate(this);
      } else if (group is void Function()) {
        group();
      } else {
        throw ArgumentError('Invalid extension group: $group');
      }
    }
  }

  /// Registers a [Preprocessor] with the registry.
  ///
  /// The preprocessor may be an instance, a factory taking the config map
  /// (e.g. the `SamplePreprocessor.new` tear-off), or a [String] name
  /// resolving through [Extensions.registerProcessorFactory]. [config] is
  /// merged into the instance configuration. Alternatively, [build] receives
  /// a fresh [Preprocessor] to configure with the DSL (in which case
  /// [processor] may only carry a config map).
  ///
  /// Returns the [Extension] proxy stored in the registry.
  ProcessorExtension preprocessor({
    Object? processor,
    Map<String, Object?>? config,
    void Function(Preprocessor processor)? build,
  }) => _addDocumentProcessor<Preprocessor>(
    'preprocessor',
    Preprocessor.new,
    processor,
    config,
    build,
  );

  /// Whether any [Preprocessor] extensions have been registered.
  bool get hasPreprocessors => _preprocessorExtensions != null;

  /// The [Extension] proxies for all [Preprocessor] instances in this
  /// registry.
  List<ProcessorExtension> get preprocessors =>
      _preprocessorExtensions ?? <ProcessorExtension>[];

  /// Registers a [TreeProcessor] with the registry.
  ///
  /// See [preprocessor] for the accepted [processor], [config] and [build]
  /// forms. Returns the [Extension] proxy stored in the registry.
  ProcessorExtension treeProcessor({
    Object? processor,
    Map<String, Object?>? config,
    void Function(TreeProcessor processor)? build,
  }) => _addDocumentProcessor<TreeProcessor>(
    'tree_processor',
    TreeProcessor.new,
    processor,
    config,
    build,
  );

  /// Whether any [TreeProcessor] extensions have been registered.
  bool get hasTreeProcessors => _treeProcessorExtensions != null;

  /// The [Extension] proxies for all [TreeProcessor] instances in this
  /// registry.
  List<ProcessorExtension> get treeProcessors =>
      _treeProcessorExtensions ?? <ProcessorExtension>[];

  /// Alias of [treeProcessor] for backwards compatibility.
  @Deprecated('Use treeProcessor instead.')
  ProcessorExtension treeprocessor({
    Object? processor,
    Map<String, Object?>? config,
    void Function(TreeProcessor processor)? build,
  }) => treeProcessor(processor: processor, config: config, build: build);

  /// Alias of [hasTreeProcessors] for backwards compatibility.
  @Deprecated('Use hasTreeProcessors instead.')
  bool get hasTreeprocessors => hasTreeProcessors;

  /// Alias of [treeProcessors] for backwards compatibility.
  @Deprecated('Use treeProcessors instead.')
  List<ProcessorExtension> get treeprocessors => treeProcessors;

  /// Registers a [Postprocessor] with the registry.
  ///
  /// See [preprocessor] for the accepted [processor], [config] and [build]
  /// forms. Returns the [Extension] proxy stored in the registry.
  ProcessorExtension postprocessor({
    Object? processor,
    Map<String, Object?>? config,
    void Function(Postprocessor processor)? build,
  }) => _addDocumentProcessor<Postprocessor>(
    'postprocessor',
    Postprocessor.new,
    processor,
    config,
    build,
  );

  /// Whether any [Postprocessor] extensions have been registered.
  bool get hasPostprocessors => _postprocessorExtensions != null;

  /// The [Extension] proxies for all [Postprocessor] instances in this
  /// registry.
  List<ProcessorExtension> get postprocessors =>
      _postprocessorExtensions ?? <ProcessorExtension>[];

  /// Registers an [IncludeProcessor] with the registry.
  ///
  /// See [preprocessor] for the accepted [processor], [config] and [build]
  /// forms. Returns the [Extension] proxy stored in the registry.
  ProcessorExtension includeProcessor({
    Object? processor,
    Map<String, Object?>? config,
    void Function(IncludeProcessor processor)? build,
  }) => _addDocumentProcessor<IncludeProcessor>(
    'include_processor',
    IncludeProcessor.new,
    processor,
    config,
    build,
  );

  /// Whether any [IncludeProcessor] extensions have been registered.
  bool get hasIncludeProcessors => _includeProcessorExtensions != null;

  /// The [Extension] proxies for all [IncludeProcessor] instances in this
  /// registry.
  List<ProcessorExtension> get includeProcessors =>
      _includeProcessorExtensions ?? <ProcessorExtension>[];

  /// Registers a [DocinfoProcessor] with the registry.
  ///
  /// See [preprocessor] for the accepted [processor], [config] and [build]
  /// forms. Returns the [Extension] proxy stored in the registry.
  ProcessorExtension docinfoProcessor({
    Object? processor,
    Map<String, Object?>? config,
    void Function(DocinfoProcessor processor)? build,
  }) => _addDocumentProcessor<DocinfoProcessor>(
    'docinfo_processor',
    DocinfoProcessor.new,
    processor,
    config,
    build,
  );

  /// Whether any [DocinfoProcessor] extensions have been registered,
  /// optionally selecting [location] (`'head'` or `'footer'`).
  bool hasDocinfoProcessors([String? location]) {
    final extensions = _docinfoProcessorExtensions;
    if (extensions == null) return false;
    if (location == null) return true;
    return extensions.any((ext) => ext.config['location'] == location);
  }

  /// The [Extension] proxies for all [DocinfoProcessor] instances in this
  /// registry, optionally selecting [location] (`'head'` or `'footer'`).
  List<ProcessorExtension> docinfoProcessors([String? location]) {
    final extensions = _docinfoProcessorExtensions;
    if (extensions == null) return <ProcessorExtension>[];
    if (location == null) return extensions;
    return extensions
        .where((ext) => ext.config['location'] == location)
        .toList();
  }

  /// Registers a [BlockProcessor] with the registry.
  ///
  /// [processor] is a [BlockProcessor] instance, a factory (taking the
  /// config map, or the name and the config map), or a [String] class name
  /// resolving through [Extensions.registerProcessorFactory]. [name] is
  /// the explicit block name for those forms, or the block name for the
  /// [build] form. Alternatively, [build] receives a fresh [BlockProcessor]
  /// to configure with the DSL; the name is then read from the processor
  /// unless passed as [name].
  ///
  /// Returns the [Extension] proxy stored in the registry.
  ProcessorExtension block({
    Object? processor,
    String? name,
    Map<String, Object?>? config,
    void Function(BlockProcessor processor)? build,
  }) => _addSyntaxProcessor<BlockProcessor>(
    'block',
    BlockProcessor.new,
    processor,
    name,
    config,
    build,
  );

  /// Whether any [BlockProcessor] extensions have been registered.
  bool get hasBlocks => _blockExtensions != null;

  /// The [Extension] proxy for the [BlockProcessor] matching the block
  /// [name] and [context], or `null` if no match is found.
  ProcessorExtension? registeredForBlock(String name, String context) {
    final ext = _blockExtensions?[name];
    if (ext == null) return null;
    final contexts = ext.config['contexts'];
    if (contexts is Iterable && contexts.contains(context)) return ext;
    return null;
  }

  /// The [Extension] proxy for the [BlockProcessor] registered to handle
  /// block content with [name], or `null` if no match is found.
  ProcessorExtension? findBlockExtension(String name) =>
      _blockExtensions?[name];

  /// Registers a [BlockMacroProcessor] with the registry.
  ///
  /// See [block] for the accepted argument forms. Returns the [Extension]
  /// proxy stored in the registry.
  ProcessorExtension blockMacro({
    Object? processor,
    String? name,
    Map<String, Object?>? config,
    void Function(BlockMacroProcessor processor)? build,
  }) => _addSyntaxProcessor<BlockMacroProcessor>(
    'block_macro',
    BlockMacroProcessor.new,
    processor,
    name,
    config,
    build,
  );

  /// Whether any [BlockMacroProcessor] extensions have been registered.
  bool get hasBlockMacros => _blockMacroExtensions != null;

  /// The [Extension] proxy for the [BlockMacroProcessor] matching the macro
  /// [name], or `null` if no match is found.
  ProcessorExtension? registeredForBlockMacro(String name) =>
      _blockMacroExtensions?[name];

  /// The [Extension] proxy for the [BlockMacroProcessor] registered to
  /// handle a block macro with [name], or `null` if no match is found.
  ProcessorExtension? findBlockMacroExtension(String name) =>
      _blockMacroExtensions?[name];

  /// Registers an [InlineMacroProcessor] with the registry.
  ///
  /// See [block] for the accepted argument forms. Returns the [Extension]
  /// proxy stored in the registry.
  ProcessorExtension inlineMacro({
    Object? processor,
    String? name,
    Map<String, Object?>? config,
    void Function(InlineMacroProcessor processor)? build,
  }) => _addSyntaxProcessor<InlineMacroProcessor>(
    'inline_macro',
    InlineMacroProcessor.new,
    processor,
    name,
    config,
    build,
  );

  /// Whether any [InlineMacroProcessor] extensions have been registered.
  bool get hasInlineMacros => _inlineMacroExtensions != null;

  /// The [Extension] proxy for the [InlineMacroProcessor] matching the
  /// macro [name], or `null` if no match is found.
  ProcessorExtension? registeredForInlineMacro(String name) =>
      _inlineMacroExtensions?[name];

  /// The [Extension] proxy for the [InlineMacroProcessor] registered to
  /// handle an inline macro with [name], or `null` if no match is found.
  ProcessorExtension? findInlineMacroExtension(String name) =>
      _inlineMacroExtensions?[name];

  /// The [Extension] proxies for all [InlineMacroProcessor] instances in
  /// this registry.
  List<ProcessorExtension> get inlineMacros =>
      (_inlineMacroExtensions ?? const <String, ProcessorExtension>{}).values
          .toList();

  /// Inserts the document processor [Extension] as the first processor of
  /// its kind in the registry.
  ///
  /// [first] is either a [ProcessorExtension] to move to the front or a
  /// document processor kind name (`'preprocessor'`, `'tree_processor'`,
  /// `'postprocessor'`, `'include_processor'` or `'docinfo_processor'`) to
  /// register through (with [processor], [config] and [build] forwarded to
  /// the corresponding registration method) before moving it to the front.
  /// Returns the [Extension] stored in the registry.
  ProcessorExtension prefer(
    Object first, {
    Object? processor,
    Map<String, Object?>? config,
    Function? build,
  }) {
    final ProcessorExtension extension;
    if (first is ProcessorExtension) {
      extension = first;
    } else if (first is String) {
      switch (first) {
        case 'preprocessor':
          extension = preprocessor(
            processor: processor,
            config: config,
            build: build as void Function(Preprocessor)?,
          );
        case 'tree_processor':
          extension = treeProcessor(
            processor: processor,
            config: config,
            build: build as void Function(TreeProcessor)?,
          );
        case 'postprocessor':
          extension = postprocessor(
            processor: processor,
            config: config,
            build: build as void Function(Postprocessor)?,
          );
        case 'include_processor':
          extension = includeProcessor(
            processor: processor,
            config: config,
            build: build as void Function(IncludeProcessor)?,
          );
        case 'docinfo_processor':
          extension = docinfoProcessor(
            processor: processor,
            config: config,
            build: build as void Function(DocinfoProcessor)?,
          );
        default:
          throw ArgumentError('Unknown processor kind: $first');
      }
    } else {
      throw ArgumentError('Invalid arguments for prefer: $first');
    }
    final store = _documentStoreOrNull(extension.kind);
    if (store == null || !store.remove(extension)) {
      throw StateError(
        'Cannot prefer ${extension.kind} extension: it is not registered '
        'in this registry',
      );
    }
    store.insert(0, extension);
    return extension;
  }

  /// Returns the live list store for document processor [kind], creating it
  /// on first use.
  List<ProcessorExtension> _documentStore(String kind) {
    switch (kind) {
      case 'preprocessor':
        return _preprocessorExtensions ??= <ProcessorExtension>[];
      case 'tree_processor':
        return _treeProcessorExtensions ??= <ProcessorExtension>[];
      case 'postprocessor':
        return _postprocessorExtensions ??= <ProcessorExtension>[];
      case 'include_processor':
        return _includeProcessorExtensions ??= <ProcessorExtension>[];
      case 'docinfo_processor':
        return _docinfoProcessorExtensions ??= <ProcessorExtension>[];
      default:
        throw ArgumentError('Unknown document processor kind: $kind');
    }
  }

  /// Returns the live list store for document processor [kind], or `null`
  /// for syntax kinds and kinds with no store yet.
  List<ProcessorExtension>? _documentStoreOrNull(String kind) {
    switch (kind) {
      case 'preprocessor':
        return _preprocessorExtensions;
      case 'tree_processor':
        return _treeProcessorExtensions;
      case 'postprocessor':
        return _postprocessorExtensions;
      case 'include_processor':
        return _includeProcessorExtensions;
      case 'docinfo_processor':
        return _docinfoProcessorExtensions;
      default:
        return null;
    }
  }

  /// Returns the live map store for syntax processor [kind], creating it on
  /// first use.
  Map<String, ProcessorExtension> _syntaxStore(String kind) {
    switch (kind) {
      case 'block':
        return _blockExtensions ??= <String, ProcessorExtension>{};
      case 'block_macro':
        return _blockMacroExtensions ??= <String, ProcessorExtension>{};
      case 'inline_macro':
        return _inlineMacroExtensions ??= <String, ProcessorExtension>{};
      default:
        throw ArgumentError('Unknown syntax processor kind: $kind');
    }
  }

  /// Registers a document processor of [kind].
  ///
  /// [create] builds a fresh family instance for the [build] form;
  /// otherwise [processorArg] is an instance, a factory taking the config
  /// map, or a [String] class name.
  ProcessorExtension _addDocumentProcessor<T extends Processor>(
    String kind,
    T Function(Map<String, Object?> config) create,
    Object? processorArg,
    Map<String, Object?>? configArg,
    void Function(T)? build,
  ) {
    final kindName = kind.replaceAll('_', ' ');
    final store = _documentStore(kind);
    late final Processor instance;
    if (build != null) {
      if (processorArg != null && processorArg is! Map) {
        throw ArgumentError(
          'Invalid arguments specified for registering $kindName extension: '
          '[$processorArg]',
        );
      }
      final config = <String, Object?>{
        if (processorArg is Map) ..._asConfig(processorArg),
        ...?configArg,
      };
      final processor = create(config);
      build(processor);
      if (processor.onProcess == null) {
        throw StateError('No block specified to process $kindName extension');
      }
      instance = processor;
    } else {
      final config = Map<String, Object?>.of(
        configArg ?? const <String, Object?>{},
      );
      final processor = processorArg;
      if (processor is T) {
        processor.updateConfig(config);
        instance = processor;
      } else if (processor is Processor Function(Map<String, Object?>)) {
        final created = processor(config);
        if (created is! T) {
          throw ArgumentError(
            'Invalid type for $kindName extension: $processorArg',
          );
        }
        instance = created;
      } else if (processor is String) {
        final factory = Extensions._processorFactories[processor];
        if (factory == null) {
          throw ArgumentError('Could not resolve class for name: $processor');
        }
        final created = factory(config);
        if (created is! T) {
          throw ArgumentError(
            'Invalid type for $kindName extension: $processor',
          );
        }
        instance = created;
      } else {
        throw ArgumentError(
          'Invalid arguments specified for registering $kindName extension: '
          '[$processorArg]',
        );
      }
    }
    final extension = ProcessorExtension(kind, instance);
    if (extension.config['position'] == '>>') {
      store.insert(0, extension);
    } else {
      store.add(extension);
    }
    return extension;
  }

  /// Registers a syntax processor of [kind].
  ///
  /// [create] builds a fresh family instance for the [build] form;
  /// otherwise [first] is an instance, a factory (taking the config map, or
  /// the name and the config map), or a [String] class name, and [second]
  /// carries the explicit name or config map.
  ProcessorExtension _addSyntaxProcessor<T extends NamedProcessor>(
    String kind,
    T Function(String? name, Map<String, Object?> config) create,
    Object? first,
    Object? second,
    Map<String, Object?>? configArg,
    void Function(T)? build,
  ) {
    final kindName = kind.replaceAll('_', ' ');
    final store = _syntaxStore(kind);
    late final T instance;
    String? name;
    if (build != null) {
      if (first != null && first is! Map) {
        throw ArgumentError(
          'Invalid arguments specified for registering $kindName extension: '
          '[$first]',
        );
      }
      if (second != null && second is! String && second is! Map) {
        throw ArgumentError(
          'Invalid arguments specified for registering $kindName extension: '
          '[$second]',
        );
      }
      final nameArg = second is String ? second : null;
      final config = <String, Object?>{
        if (first is Map) ..._asConfig(first),
        if (second is Map) ..._asConfig(second),
        ...?configArg,
      };
      final processor = create(nameArg, config);
      build(processor);
      // Reading the name validates it for block macros, exactly like Ruby.
      name = processor.name;
      if (name == null) {
        throw ArgumentError('No name specified for $kindName extension');
      }
      if (processor.onProcess == null) {
        throw StateError('No block specified to process $kindName extension');
      }
      instance = processor;
    } else {
      final config = <String, Object?>{};
      String? nameArg;
      if (second is String) {
        nameArg = second;
      } else if (second is Map) {
        // A config map in the name position (Ruby: trailing hash).
        config.addAll(_asConfig(second));
      }
      // Silently drop non-string, non-map extras, like Ruby's resolve_args.
      if (configArg != null) config.addAll(configArg);
      final processor = first;
      if (processor is T) {
        processor.updateConfig(config);
        if (nameArg != null) processor.name = nameArg;
        name = processor.name;
        if (name == null) {
          throw ArgumentError(
            'No name specified for $kindName extension: $processor',
          );
        }
        instance = processor;
      } else if (processor is T Function(String?, Map<String, Object?>)) {
        instance = processor(nameArg, config);
        name = instance.name;
        if (name == null) {
          throw ArgumentError(
            'No name specified for $kindName extension: $processor',
          );
        }
      } else if (processor is Processor Function(Map<String, Object?>)) {
        final created = processor(config);
        if (created is! T) {
          throw ArgumentError(
            'Class specified for $kindName extension does not inherit from '
            '${_kindClassName(kind)}: $processor',
          );
        }
        if (nameArg != null) created.name = nameArg;
        name = created.name;
        if (name == null) {
          throw ArgumentError(
            'No name specified for $kindName extension: $processor',
          );
        }
        instance = created;
      } else if (processor is String) {
        final factory = Extensions._processorFactories[processor];
        if (factory == null) {
          throw ArgumentError('Could not resolve class for name: $processor');
        }
        final created = factory(config);
        if (created is! T) {
          throw ArgumentError(
            'Class specified for $kindName extension does not inherit from '
            '${_kindClassName(kind)}: $processor',
          );
        }
        if (nameArg != null) created.name = nameArg;
        name = created.name;
        if (name == null) {
          throw ArgumentError(
            'No name specified for $kindName extension: $processor',
          );
        }
        instance = created;
      } else {
        throw ArgumentError(
          'Invalid arguments specified for registering $kindName extension: '
          '[$processor]',
        );
      }
    }
    final extension = ProcessorExtension(kind, instance);
    store[name] = extension;
    return extension;
  }

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

  /// The processor class name for syntax [kind], for error messages.
  static String _kindClassName(String kind) {
    switch (kind) {
      case 'block':
        return 'BlockProcessor';
      case 'block_macro':
        return 'BlockMacroProcessor';
      case 'inline_macro':
        return 'InlineMacroProcessor';
      default:
        return 'Processor';
    }
  }
}

/// Global entry point for the extension system: group registration and
/// standalone registry creation.
abstract final class Extensions {
  /// The statically-registered extension groups by name.
  static Map<String, Object?> get groups => _groups;
  static final Map<String, Object?> _groups = <String, Object?>{};

  static int _autoId = -1;

  /// Factories resolving [String] class names passed to [Registry]
  /// registration methods.
  static final Map<String, Processor Function(Map<String, Object?>)>
  _processorFactories = <String, Processor Function(Map<String, Object?>)>{};

  /// Factories resolving [String] class names passed to [register].
  static final Map<String, ExtensionGroup Function()> _groupFactories =
      <String, ExtensionGroup Function()>{};

  /// The next automatic extension group id.
  static int nextAutoId() => ++_autoId;

  /// Generates an automatic extension group name (`'extgrp0'`, ...).
  static String generateName() => 'extgrp${nextAutoId()}';

  /// Registers a factory resolving the processor class [name].
  ///
  /// Dart has no reflection by name, so processors registered by string
  /// resolve through this table instead of Ruby's constant lookup. A
  /// missing entry throws [ArgumentError] carrying Ruby's
  /// `Could not resolve class for name: ...` message.
  static void registerProcessorFactory(
    String name,
    Processor Function(Map<String, Object?> config) factory,
  ) {
    _processorFactories[name] = factory;
  }

  /// Registers a factory resolving the extension group class [name].
  ///
  /// See [registerProcessorFactory] for why a table replaces Ruby's
  /// constant lookup.
  static void registerGroupFactory(
    String name,
    ExtensionGroup Function() factory,
  ) {
    _groupFactories[name] = factory;
  }

  /// Creates a standalone registry that is not globally registered.
  ///
  /// When [build] is given, it is stored under [name] (or a generated
  /// name) and runs when the registry is activated.
  static Registry create({String? name, void Function(Registry)? build}) {
    if (build == null) return Registry();
    return Registry({name ?? generateName(): build});
  }

  /// Registers an extension [group] under [name].
  ///
  /// The group is an [ExtensionGroup] instance, an [ExtensionGroup]
  /// factory, a `void Function(Registry)` callback, or a [String] class
  /// name resolving through [registerGroupFactory]. Alternatively, [build]
  /// is the group callback. When [name] is omitted, one is generated
  /// (`'extgrp0'`, ...). Returns the stored group.
  static Object? register({
    String? name,
    Object? group,
    void Function(Registry)? build,
  }) {
    final stored = build ?? group;
    if (stored == null) {
      throw ArgumentError('Extension group to register not specified');
    }
    final key = name ?? generateName();
    final Object? resolved;
    if (stored is String) {
      final factory = _groupFactories[stored];
      if (factory == null) {
        throw ArgumentError('Could not resolve class for name: $stored');
      }
      resolved = factory;
    } else {
      resolved = stored;
    }
    _groups[key] = resolved;
    return resolved;
  }

  /// Unregisters all statically-registered extension groups.
  static void unregisterAll() {
    _groups.clear();
  }

  /// Unregisters the statically-registered extension groups in [names].
  static void unregister(Iterable<String> names) {
    names.forEach(_groups.remove);
  }
}
