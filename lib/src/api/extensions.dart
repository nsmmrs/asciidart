part of 'api.dart';

/// An extension: code that adds syntax to AsciiDoc or changes how documents
/// are processed. Pass extensions to [Ptome.new].
sealed class Extension {
  const new _();

  void _register(impl.Registry registry, _Includes includes);
}

/// Edits the source lines of a document before it is parsed.
///
/// [process] receives the lines (preprocessor directives such as `include::`
/// not yet applied) and returns the lines to parse.
final class Preprocessor extends Extension {
  /// A preprocessor running [process].
  const new(this.process) : super._();

  /// Returns the lines to parse.
  final List<String> Function(List<String> lines, Document document) process;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.preprocessor(
      build: (p) => p.onProcess = (document, reader) {
        final lines = process(reader.lines, _view(document) as Document);
        return impl.PreprocessorReader(
          document,
          lines,
          cursor: reader.cursor(),
        );
      },
    );
  }
}

/// Inspects or changes the parsed document before it is converted.
final class TreeProcessor extends Extension {
  /// A tree processor running [process].
  const new(this.process) : super._();

  /// Inspects or changes the document.
  final void Function(Document document) process;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.treeProcessor(
      build: (p) => p.onProcess = (document) {
        process(_view(document) as Document);
        return null;
      },
    );
  }
}

/// Edits the converted output of a document.
final class Postprocessor extends Extension {
  /// A postprocessor running [process].
  const new(this.process) : super._();

  /// Returns the edited output.
  final String Function(String output, Document document) process;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.postprocessor(
      build: (p) =>
          p.onProcess = (document, output) =>
              process(output, _view(document) as Document),
    );
  }
}

/// Where [Docinfo] content goes.
enum DocinfoLocation {
  /// At the end of the HTML `<head>` (or the DocBook `<info>`).
  head,

  /// At the end of the document body.
  footer,
}

/// Adds content to the document head or footer (the `docinfo` slots).
final class Docinfo extends Extension {
  /// Adds what [content] returns at [location].
  const new(this.content, {this.location = DocinfoLocation.head}) : super._();

  /// The content to add, or `null` for none.
  final String? Function(Document document) content;

  /// Where the content goes.
  final DocinfoLocation location;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.docinfoProcessor(
      build: (p) {
        p.config.location = location.name;
        p.onProcess = (document) => content(_view(document) as Document);
      },
    );
  }
}

/// What an [IncludeResolver] is asked for.
final class IncludeRequest {
  const new _(this.target, this.document);

  /// The include target as written (`include::target[]`), with attribute
  /// references resolved.
  final String target;

  /// The document being parsed.
  final Document document;
}

/// Supplies the content of `include::` directives.
///
/// [resolve] returns the content to include, or `null` to let Ptome
/// read the target as usual. It may return a `Future`; then use the
/// asynchronous methods ([Ptome.parseAsync], [Ptome.convertAsync]),
/// which wait for it.
final class IncludeResolver extends Extension {
  /// An include resolver running [resolve].
  const new(this.resolve) : super._();

  /// The content for [IncludeRequest.target], or `null`.
  final FutureOr<String?> Function(IncludeRequest request) resolve;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.includeProcessor(
      build: (p) {
        String? content;
        p
          ..onHandles = (_, target) {
            content = includes.resolve(
              this,
              target,
              () => IncludeRequest._(
                target,
                _view(registry.document!) as Document,
              ),
            );
            return content != null;
          }
          ..onProcess = (document, reader, target, attributes) {
            reader.pushInclude(content ?? '', target, target, 1, attributes);
          };
      },
    );
  }
}

/// The content [IncludeResolver]s supplied, and the ones still pending,
/// for one parse (or one series of discovery passes).
final class _Includes {
  new({required this.async});

  /// Whether a resolver may return a future.
  final bool async;

  final Map<(IncludeResolver, String), String?> _resolved = {};
  final Map<(IncludeResolver, String), Future<String?>> _pending = {};

  String? resolve(
    IncludeResolver resolver,
    String target,
    IncludeRequest Function() request,
  ) {
    final key = (resolver, target);
    if (_resolved.containsKey(key)) return _resolved[key];
    if (_pending.containsKey(key)) return '';
    final result = resolver.resolve(request());
    if (result is Future<String?>) {
      if (!async) {
        throw PtomeException._(
          'the include resolver returned a Future for $target; '
          'use parseAsync or convertAsync',
        );
      }
      _pending[key] = result;
      return '';
    }
    return _resolved[key] = result;
  }

  bool get hasPending => _pending.isNotEmpty;

  /// Waits for the pending content.
  Future<void> settle() async {
    final pending = Map.of(_pending);
    _pending.clear();
    for (final MapEntry(:key, :value) in pending.entries) {
      _resolved[key] = await value;
    }
  }
}

/// The block kinds a [CustomBlock] can handle.
enum BlockKind {
  /// A paragraph.
  paragraph,

  /// A listing block (`----`).
  listing,

  /// A literal block (`....`).
  literal,

  /// An open block (`--`).
  open,

  /// An example block (`====`).
  example,

  /// A sidebar (`****`).
  sidebar,

  /// A quote block (`____`).
  quote,

  /// A passthrough block (`++++`).
  passthrough;

  String get _context => switch (this) {
    passthrough => 'pass',
    _ => name,
  };
}

/// Creates blocks for an extension, inside [_parent].
mixin _BlockFactory {
  impl.AbstractBlock get _parent;
  impl.Processor get _processor;

  /// A paragraph with [text] (AsciiDoc inline markup is applied).
  Block paragraph(String text, {Map<String, String> attributes = const {}}) =>
      _blockView(_processor.createParagraph(_parent, text, {...attributes}));

  /// A passthrough block: [html] goes to the output as is.
  Block html(String html) =>
      _blockView(_processor.createPassBlock(_parent, html, {}));

  /// A listing block with [source]; a source block when [language] is
  /// given.
  Block listing(String source, {String? language}) => _blockView(
    _processor.createListingBlock(_parent, source, {
      if (language != null) ...{'style': 'source', 'language': language},
    }),
  );

  /// An image block showing [target].
  Block image(String target, {String? alt, String? title}) => _blockView(
    _processor.createImageBlock(_parent, {
      'target': target,
      'alt': ?alt,
      'title': ?title,
    }),
  );

  /// An open block containing [source] parsed as AsciiDoc.
  Block asciidoc(String source) {
    final block = _processor.createOpenBlock(_parent, null, {});
    _processor.parseContent(block, impl.Reader.fromString(source));
    return _blockView(block);
  }
}

/// What a [BlockMacro] receives: the target and attributes of the macro,
/// and ways to create the block that replaces it.
final class BlockMacroContext with _BlockFactory {
  new _(this._parent, this._processor, this.target, this._attrs);

  @override
  final impl.AbstractBlock _parent;

  @override
  final impl.Processor _processor;

  final Map<String, String> _attrs;

  /// The macro target (`name::target[]`).
  final String target;

  /// The attributes in the brackets: positional ones under `1`, `2`, ...,
  /// named ones under their names.
  Attributes get attributes => Attributes._(_attrs);

  /// The block containing the macro.
  Block get parent => _blockView(_parent);

  /// The document being parsed.
  Document get document => parent.document;
}

/// Handles a block macro (`name::target[attributes]` on a line of its own).
final class BlockMacro extends Extension {
  /// Handles `name::` macros with [process], which returns the block to put
  /// in the macro's place (or `null` to drop it).
  const new(this.name, this.process) : super._();

  /// The macro name.
  final String name;

  /// Returns the block that replaces the macro.
  final Block? Function(BlockMacroContext macro) process;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.blockMacro(
      name: name,
      build: (p) =>
          p.onProcess = (parent, target, attributes) =>
              process(BlockMacroContext._(parent, p, target, attributes))
                  ?._block,
    );
  }
}

/// What an [InlineMacro] receives: the target and attributes of the macro,
/// and ways to create the inline element that replaces it.
final class InlineMacroContext {
  new _(this._parent, this._processor, this.target, this._attrs);

  final impl.AbstractBlock _parent;
  final impl.Processor _processor;
  final Map<String, String> _attrs;

  /// The macro target (`name:target[]`).
  final String target;

  /// The attributes in the brackets: positional ones under `1`, `2`, ...,
  /// named ones under their names.
  Attributes get attributes => Attributes._(_attrs);

  /// The text in the brackets, when the macro has no named attributes.
  String? get text => _attrs['text'] ?? _attrs['1'];

  /// The block containing the macro.
  Block get parent => _blockView(_parent);

  /// The document being parsed.
  Document get document => parent.document;

  /// A link to [url], showing [text] (default: the URL).
  Inline link(String url, {String? text}) => _view(
    _processor.createInline(
      _parent,
      impl.InlineContext.anchor,
      text ?? url,
      type: 'link',
      target: url,
    ),
  ) as Inline;

  /// [html], output as is.
  Inline html(String html) => _view(
    _processor.createInline(
      _parent,
      impl.InlineContext.quoted,
      html,
      type: 'unquoted',
    ),
  ) as Inline;

  /// [text] (already converted HTML) with [kind] formatting.
  Inline formatted(String text, FormattedKind kind) => _view(
    _processor.createInline(
      _parent,
      impl.InlineContext.quoted,
      text,
      type: switch (kind) {
        FormattedKind.monospace => 'monospaced',
        FormattedKind.doubleQuoted => 'double',
        FormattedKind.singleQuoted => 'single',
        _ => kind.name,
      },
    ),
  ) as Inline;
}

/// Handles an inline macro (`name:target[attributes]` within text).
final class InlineMacro extends Extension {
  /// Handles `name:` macros with [process], which returns the inline element
  /// to put in the macro's place (or `null` to drop it).
  const new(this.name, this.process) : super._();

  /// The macro name.
  final String name;

  /// Returns the inline element that replaces the macro.
  final Inline? Function(InlineMacroContext macro) process;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.inlineMacro(
      name: name,
      build: (p) =>
          p.onProcess = (parent, target, attributes) =>
              process(InlineMacroContext._(parent, p, target, attributes))
                  ?._inline,
    );
  }
}

/// What a [CustomBlock] receives: the block's content and attributes, and
/// ways to create the block that replaces it.
final class CustomBlockContext with _BlockFactory {
  new _(this._parent, this._processor, this.lines, this._attrs);

  @override
  final impl.AbstractBlock _parent;

  @override
  final impl.Processor _processor;

  final Map<String, String> _attrs;

  /// The lines of the block's content.
  final List<String> lines;

  /// The block's content.
  String get source => lines.join('\n');

  /// The block's attributes.
  Attributes get attributes => Attributes._(_attrs);

  /// The block containing this one.
  Block get parent => _blockView(_parent);

  /// The document being parsed.
  Document get document => parent.document;
}

/// Handles blocks with a custom style (`[name]` above a paragraph or a
/// delimited block).
final class CustomBlock extends Extension {
  /// Handles `[name]` blocks of the kinds in [on] with [process], which
  /// returns the block to put in their place (or `null` to drop it).
  const new(
    this.name,
    this.process, {
    this.on = const {BlockKind.open, BlockKind.paragraph},
  }) : super._();

  /// The style name.
  final String name;

  /// The block kinds handled.
  final Set<BlockKind> on;

  /// Returns the block that replaces the custom block.
  final Block? Function(CustomBlockContext block) process;

  @override
  void _register(impl.Registry registry, _Includes includes) {
    registry.block(
      name: name,
      build: (p) {
        p
          ..contexts([for (final kind in on) kind._context])
          ..onProcess = (parent, reader, attributes) => process(
            CustomBlockContext._(parent, p, reader.readLines(), attributes),
          )?._block;
      },
    );
  }
}
