// A frozen copy of lib/src/mathml.dart's reader at 17001e86 (the tree's
// classes are the package's), the oracle of the equivalence tests
// (test/equivalence_test.dart). Don't edit.
// ignore_for_file: type=lint
library;

import 'package:plain_math/plain_math.dart';

/// The formula of the MathML in [text] (a `math` element, its elements
/// with or without a namespace prefix).
MathNode frozenParseMathML(String text) => _node(_XmlReader(text).document());

List<_Element> _children(_Element element) => element.elements;

MathNode _row(List<_Element> elements) => elements.length == 1
    ? _node(elements.single)
    : MathRow([for (final e in elements) _node(e)]);

bool? _bool(String? value) => switch (value) {
  'true' => true,
  'false' => false,
  _ => null,
};

MathNode _node(_Element element) {
  final name = element.name;
  final children = _children(element);
  MathNode child(int i) =>
      i < children.length ? _node(children[i]) : const MathRow([]);
  final node = switch (name) {
    'mi' => MathToken(
      MathTokenKind.identifier,
      element.innerText.trim(),
      variant: element.attribute('mathvariant'),
    ),
    'mn' => MathToken(
      MathTokenKind.number,
      element.innerText.trim(),
      variant: element.attribute('mathvariant'),
    ),
    'mo' => MathToken(
      MathTokenKind.operator,
      element.innerText.trim(),
      variant: element.attribute('mathvariant'),
      stretchy: _bool(element.attribute('stretchy')),
      largeOperator: _bool(element.attribute('largeop')),
      movableLimits: _bool(element.attribute('movablelimits')),
      fence: _bool(element.attribute('fence')),
      form: element.attribute('form'),
    ),
    'mtext' || 'ms' => MathToken(
      MathTokenKind.text,
      element.innerText,
      variant: element.attribute('mathvariant'),
    ),
    'msub' => MathScripts(child(0), sub: child(1)),
    'msup' => MathScripts(child(0), sup: child(1)),
    'msubsup' => MathScripts(child(0), sub: child(1), sup: child(2)),
    'munder' => MathUnderOver(
      child(0),
      under: child(1),
      accentUnder: _bool(element.attribute('accentunder')) ?? false,
    ),
    'mover' => MathUnderOver(
      child(0),
      over: child(1),
      accent: _bool(element.attribute('accent')) ?? false,
    ),
    'munderover' => MathUnderOver(
      child(0),
      under: child(1),
      over: child(2),
      accent: _bool(element.attribute('accent')) ?? false,
      accentUnder: _bool(element.attribute('accentunder')) ?? false,
    ),
    'mfrac' => MathFraction(
      child(0),
      child(1),
      lineThickness: element.attribute('linethickness'),
    ),
    'msqrt' => MathRadical(_row(children)),
    'mroot' => MathRadical(child(0), index: child(1)),
    'mtable' => MathTable([
      for (final row in children)
        if (row.name == 'mtr' || row.name == 'mlabeledtr')
          [
            for (final cell in _children(row))
              if (cell.name == 'mtd') _row(_children(cell)),
          ],
    ], columnAlign: element.attribute('columnalign')),
    'menclose' => MathEnclose(
      _row(children),
      (element.attribute('notation') ?? 'longdiv')
          .split(RegExp(r'\s+'))
          .where((n) => n.isNotEmpty)
          .toList(),
    ),
    'mspace' => MathSpace(element.attribute('width')),
    'mfenced' => MathRow([
      MathToken(
        MathTokenKind.operator,
        element.attribute('open') ?? '(',
        fence: true,
        stretchy: true,
      ),
      for (final (i, c) in children.indexed) ...[
        if (i > 0)
          MathToken(
            MathTokenKind.operator,
            (element.attribute('separators') ?? ',').trim().isEmpty
                ? ''
                : (element.attribute('separators') ?? ',').trim()[0],
          ),
        _node(c),
      ],
      MathToken(
        MathTokenKind.operator,
        element.attribute('close') ?? ')',
        fence: true,
        stretchy: true,
      ),
    ]),
    'semantics' => child(0),
    'annotation' ||
    'annotation-xml' ||
    'none' ||
    'mprescripts' => const MathRow([]),
    // math, mrow, mstyle, mpadded, mphantom, merror, and the unknown.
    _ => _row(children),
  };
  final display = switch (element.attribute('displaystyle')) {
    final v? => _bool(v),
    null when name == 'math' =>
      element.attribute('display') == 'block' ? true : null,
    null => null,
  };
  final scriptLevel = element.attribute('scriptlevel');
  final color = element.attribute('mathcolor');
  final variant = name == 'mstyle' ? element.attribute('mathvariant') : null;
  if (display == null &&
      scriptLevel == null &&
      color == null &&
      variant == null) {
    return node;
  }
  return MathStyled(
    node,
    display: display,
    scriptLevel: scriptLevel,
    color: color,
    variant: variant,
  );
}

/// An element of a MathML document: its local name (without a namespace
/// prefix), attributes and children (elements and text).
final class _Element {
  new(this.name, this.attributes);

  final String name;
  final Map<String, String> attributes;
  final List<Object> children = [];

  String? attribute(String name) => attributes[name];

  List<_Element> get elements => children.whereType<_Element>().toList();

  String get innerText {
    final out = StringBuffer();
    void collect(_Element e) {
      for (final child in e.children) {
        if (child is String) {
          out.write(child);
        } else {
          collect(child as _Element);
        }
      }
    }

    collect(this);
    return out.toString();
  }
}

/// Reads well-formed XML: elements, attributes, text, character and the
/// five predefined entity references, CDATA sections, comments,
/// processing instructions and a document type declaration (skipped).
final class _XmlReader {
  new(this._text);

  final String _text;
  int _at = 0;

  Never _fail(String message) =>
      throw MathMLException('$message at offset $_at');

  _Element document() {
    _misc();
    if (!_text.startsWith('<', _at)) _fail('no root element');
    final root = _element();
    _misc();
    if (_at < _text.length) _fail('content after the root element');
    return root;
  }

  /// Skips whitespace, comments, processing instructions and a doctype.
  void _misc() {
    for (;;) {
      while (_at < _text.length && _isSpace(_text.codeUnitAt(_at))) {
        _at++;
      }
      if (_text.startsWith('<!--', _at)) {
        _skipPast('-->');
      } else if (_text.startsWith('<?', _at)) {
        _skipPast('?>');
      } else if (_text.startsWith('<!DOCTYPE', _at)) {
        _skipPast('>');
      } else {
        return;
      }
    }
  }

  void _skipPast(String end) {
    final i = _text.indexOf(end, _at);
    if (i < 0) _fail('unterminated markup');
    _at = i + end.length;
  }

  static bool _isSpace(int c) => c == 0x20 || c == 0x9 || c == 0xa || c == 0xd;

  static bool _isNameChar(int c) =>
      !_isSpace(c) && c != 0x3e && c != 0x2f && c != 0x3d && c != 0x3c;

  String _name() {
    final start = _at;
    while (_at < _text.length && _isNameChar(_text.codeUnitAt(_at))) {
      _at++;
    }
    if (_at == start) _fail('a name expected');
    return _text.substring(start, _at);
  }

  static String _local(String name) => name.substring(name.indexOf(':') + 1);

  _Element _element() {
    _at++; // <
    final qname = _name();
    final attributes = <String, String>{};
    for (;;) {
      while (_at < _text.length && _isSpace(_text.codeUnitAt(_at))) {
        _at++;
      }
      if (_at >= _text.length) _fail('unterminated start tag');
      if (_text.startsWith('/>', _at)) {
        _at += 2;
        return _Element(_local(qname), attributes);
      }
      if (_text.codeUnitAt(_at) == 0x3e) {
        _at++;
        break;
      }
      final name = _name();
      while (_at < _text.length && _isSpace(_text.codeUnitAt(_at))) {
        _at++;
      }
      if (_at >= _text.length || _text.codeUnitAt(_at) != 0x3d) {
        _fail('= expected');
      }
      _at++;
      while (_at < _text.length && _isSpace(_text.codeUnitAt(_at))) {
        _at++;
      }
      if (_at >= _text.length) _fail('attribute value expected');
      final quote = _text[_at];
      if (quote != '"' && quote != "'") _fail('quoted value expected');
      final end = _text.indexOf(quote, _at + 1);
      if (end < 0) _fail('unterminated attribute value');
      attributes[_local(name)] = _decode(_text.substring(_at + 1, end));
      _at = end + 1;
    }
    final element = _Element(_local(qname), attributes);
    final text = StringBuffer();
    void flush() {
      if (text.isNotEmpty) {
        element.children.add(_decode(text.toString()));
        text.clear();
      }
    }

    for (;;) {
      if (_at >= _text.length) _fail('unterminated element <$qname>');
      if (_text.startsWith('</', _at)) {
        flush();
        _at += 2;
        final close = _name();
        if (close != qname) _fail('</$close> closes <$qname>');
        while (_at < _text.length && _isSpace(_text.codeUnitAt(_at))) {
          _at++;
        }
        if (_at >= _text.length || _text.codeUnitAt(_at) != 0x3e) {
          _fail('> expected');
        }
        _at++;
        return element;
      }
      if (_text.startsWith('<![CDATA[', _at)) {
        final end = _text.indexOf(']]>', _at);
        if (end < 0) _fail('unterminated CDATA section');
        flush();
        element.children.add(_text.substring(_at + 9, end));
        _at = end + 3;
      } else if (_text.startsWith('<!--', _at)) {
        _skipPast('-->');
      } else if (_text.startsWith('<?', _at)) {
        _skipPast('?>');
      } else if (_text.codeUnitAt(_at) == 0x3c) {
        flush();
        element.children.add(_element());
      } else {
        final next = _text.indexOf('<', _at);
        final end = next < 0 ? _text.length : next;
        text.write(_text.substring(_at, end));
        _at = end;
      }
    }
  }

  /// [raw] with its character and entity references replaced; an unknown
  /// named entity is kept as it is.
  static String _decode(String raw) {
    if (!raw.contains('&')) return raw;
    return raw.replaceAllMapped(
      RegExp('&(#x[0-9a-fA-F]+|#[0-9]+|[A-Za-z][A-Za-z0-9]*);'),
      (m) {
        final ref = m[1]!;
        if (ref.startsWith('#x')) {
          return String.fromCharCode(int.parse(ref.substring(2), radix: 16));
        }
        if (ref.startsWith('#')) {
          return String.fromCharCode(int.parse(ref.substring(1)));
        }
        return switch (ref) {
          'lt' => '<',
          'gt' => '>',
          'amp' => '&',
          'quot' => '"',
          'apos' => "'",
          _ => m[0]!,
        };
      },
    );
  }
}
