part of 'api.dart';

/// Overrides the HTML of some nodes: returns the HTML for [node], using
/// [defaults] for Ptome's own HTML.
///
/// The override is called for every node converted to HTML (the document,
/// blocks, list items, table cells, inline elements); return
/// `defaults.render(node)` for the nodes it leaves alone.
typedef HtmlOverride = String Function(Node node, HtmlDefaults defaults);

/// Ptome's own HTML, for an [HtmlOverride].
final class HtmlDefaults {
  new _(this._base, this._node, this._transform, this._opts);

  final impl.Converter _base;
  final impl.AbstractNode _node;
  final String? _transform;
  final impl.ConvertOptions? _opts;

  /// Ptome's HTML for [node].
  String render(Node node) => identical(node._node, _node)
      ? _base.convert(_node, _transform, _opts) ?? ''
      : _base.convert(node._node) ?? '';

  /// The HTML of what is inside [block]: its converted text, or its child
  /// blocks (converted with the override in effect).
  String content(Block block) => block._block.content() ?? '';
}

/// The HTML converter with an [HtmlOverride] in front.
final class _OverrideConverter extends impl.Converter {
  new(this._base, this._override) : super(_base.backend, _base.opts) {
    final traits = _base.backendTraits;
    backendTraits = impl.BackendTraits(
      basebackend: traits.basebackend,
      filetype: traits.filetype,
      outfilesuffix: traits.outfilesuffix,
      htmlsyntax: traits.htmlsyntax,
    );
  }

  final impl.Converter _base;
  final HtmlOverride _override;

  @override
  String? convert(
    impl.AbstractNode node, [
    String? transform,
    impl.ConvertOptions? opts,
  ]) => _override(_view(node), HtmlDefaults._(_base, node, transform, opts));

  @override
  bool handles(String transform) => _base.handles(transform);
}

/// A converter factory putting [override] in front of the HTML converter
/// (including its templates, if any).
impl.ConverterFactory _overrideFactory(HtmlOverride override) {
  impl.Converter create(String backend, impl.ConverterOptions opts) {
    impl.Html5Converter.registerFor();
    final base = impl.Converter.create(backend, opts);
    if (base == null) {
      throw PtomeException._('missing converter for backend $backend');
    }
    return _OverrideConverter(base, override);
  }

  return impl.DefaultFactoryProxy({'html5': create});
}
