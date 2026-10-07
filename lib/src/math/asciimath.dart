/// AsciiMath to MathML: a port of the `asciimath` gem 2.0.6 (MIT,
/// Pepijn Van Eeckhoudt), the converter Asciidoctor's DocBook backend and
/// asciidoctor-epub3 use when it is installed (ADR-0014). The parser, the
/// tree and the MathML are the gem's, byte for byte, including how the
/// tree's nodes move between parents (a node added to a new parent leaves
/// its old one, with every node equal to it).
library;

/// [asciimath] as MathML: `<{prefix}math{attrs}>...</{prefix}math>`
/// (`toMathml(text, prefix: 'mml:')` as the gem's
/// `AsciiMath.parse(text).to_mathml('mml:')`).
String asciimathToMathml(
  String asciimath, {
  String prefix = '',
  Map<String, String> attributes = const {},
}) {
  final ast = _Parser(_parserSymbols).parse(asciimath);
  return (_MathmlBuilder(prefix)..appendExpression(ast, attributes)).toString();
}

// The symbol tables.

/// An entry of a symbol table: the symbol's name (or display value), its
/// type, and the gem's extra keys.
final class _Entry {
  const new(
    this.value,
    this.type, {
    this.underover = false,
    this.position,
    this.lparen,
    this.rparen,
    this.convertsToColor = false,
  });

  final String? value;
  final String type;
  final bool underover;
  final String? position;
  final String? lparen;
  final String? rparen;
  final bool convertsToColor;
}

final class _TableBuilder {
  final Map<String, _Entry> table = {};

  void add(
    List<String> names,
    String? value,
    String type, {
    bool underover = false,
    String? position,
    String? lparen,
    String? rparen,
    bool convertsToColor = false,
  }) {
    final entry = _Entry(
      value,
      type,
      underover: underover,
      position: position,
      lparen: lparen,
      rparen: rparen,
      convertsToColor: convertsToColor,
    );
    for (final name in names) {
      table[name] = entry;
    }
  }
}

final Map<String, _Entry> _parserSymbols = () {
  final b = _TableBuilder();
  void s(List<String> names, String? value, [String type = 'symbol']) =>
      b.add(names, value, type);
  // Operation symbols
  s(['+'], 'plus');
  s(['-'], 'minus');
  s(['*', 'cdot'], 'cdot');
  s(['**', 'ast'], 'ast');
  s(['***', 'star'], 'star');
  s(['//'], 'slash');
  s([r'\\', 'backslash'], 'backslash');
  s(['setminus'], 'setminus');
  s(['xx', 'times'], 'times');
  s(['|><', 'ltimes'], 'ltimes');
  s(['><|', 'rtimes'], 'rtimes');
  s(['|><|', 'bowtie'], 'bowtie');
  s(['-:', 'div', 'divide'], 'div');
  s(['@', 'circ'], 'circ');
  s(['o+', 'oplus'], 'oplus');
  s(['ox', 'otimes'], 'otimes');
  s(['o.', 'odot'], 'odot');
  s(['sum'], 'sum');
  s(['prod'], 'prod');
  s(['^^', 'wedge'], 'wedge');
  s(['^^^', 'bigwedge'], 'bigwedge');
  s(['vv', 'vee'], 'vee');
  s(['vvv', 'bigvee'], 'bigvee');
  s(['nn', 'cap'], 'cap');
  s(['nnn', 'bigcap'], 'bigcap');
  s(['uu', 'cup'], 'cup');
  s(['uuu', 'bigcup'], 'bigcup');
  // Relation symbols
  s(['='], 'eq');
  s(['!=', 'ne'], 'ne');
  s([':='], 'assign');
  s(['<', 'lt'], 'lt');
  s(['mlt', 'll'], 'mlt');
  s(['>', 'gt'], 'gt');
  s(['mgt', 'gg'], 'mgt');
  s(['<=', 'le'], 'le');
  s(['>=', 'ge'], 'ge');
  s(['-<', '-lt', 'prec'], 'prec');
  s(['>-', 'succ'], 'succ');
  s(['-<=', 'preceq'], 'preceq');
  s(['>-=', 'succeq'], 'succeq');
  s(['in'], 'in');
  s(['!in', 'notin'], 'notin');
  s(['sub', 'subset'], 'subset');
  s(['sup', 'supset'], 'supset');
  s(['sube', 'subseteq'], 'subseteq');
  s(['supe', 'supseteq'], 'supseteq');
  s(['-=', 'equiv'], 'equiv');
  s(['~', 'sim'], 'sim');
  s(['~=', 'cong'], 'cong');
  s(['~~', 'approx'], 'approx');
  s(['prop', 'propto'], 'propto');
  // Logical symbols
  s(['and'], 'and');
  s(['or'], 'or');
  s(['not', 'neg'], 'not');
  s(['=>', 'implies'], 'implies');
  s(['if'], 'if');
  s(['<=>', 'iff'], 'iff');
  s(['AA', 'forall'], 'forall');
  s(['EE', 'exists'], 'exists');
  s(['_|_', 'bot'], 'bot');
  s(['TT', 'top'], 'top');
  s(['|--', 'vdash'], 'vdash');
  s(['|==', 'models'], 'models');
  // Grouping brackets
  s(['(', 'left('], 'lparen', 'lparen');
  s([')', 'right)'], 'rparen', 'rparen');
  s(['[', 'left['], 'lbracket', 'lparen');
  s([']', 'right]'], 'rbracket', 'rparen');
  s(['{'], 'lbrace', 'lparen');
  s(['}'], 'rbrace', 'rparen');
  s(['|'], 'vbar', 'lrparen');
  s([':|:'], 'vbar');
  s(['|:'], 'vbar', 'lparen');
  s([':|'], 'vbar', 'rparen');
  s(['(:', '<<', 'langle'], 'langle', 'lparen');
  s([':)', '>>', 'rangle'], 'rangle', 'rparen');
  s(['{:'], null, 'lparen');
  s([':}'], null, 'rparen');
  // Miscellaneous symbols
  s(['int'], 'integral');
  s(['dx'], 'dx');
  s(['dy'], 'dy');
  s(['dz'], 'dz');
  s(['dt'], 'dt');
  s(['oint'], 'contourintegral');
  s(['del', 'partial'], 'partial');
  s(['grad', 'nabla'], 'nabla');
  s(['+-', 'pm'], 'pm');
  s(['-+', 'mp'], 'mp');
  s(['O/', 'emptyset'], 'emptyset');
  s(['oo', 'infty'], 'infty');
  s(['aleph'], 'aleph');
  s(['...', 'ldots'], 'ellipsis');
  s([':.', 'therefore'], 'therefore');
  s([":'", 'because'], 'because');
  s(['/_', 'angle'], 'angle');
  s([r'/_\', 'triangle'], 'triangle');
  s(["'", 'prime'], 'prime');
  s(['tilde'], 'tilde', 'unary');
  s([r'\ '], 'nbsp');
  s(['frown'], 'frown');
  s(['quad'], 'quad');
  s(['qquad'], 'qquad');
  s(['cdots'], 'cdots');
  s(['vdots'], 'vdots');
  s(['ddots'], 'ddots');
  s(['diamond'], 'diamond');
  s(['square'], 'square');
  s(['|__', 'lfloor'], 'lfloor');
  s(['__|', 'rfloor'], 'rfloor');
  s(['|~', 'lceiling'], 'lceiling');
  s(['~|', 'rceiling'], 'rceiling');
  s(['CC'], 'dstruck_captial_c');
  s(['NN'], 'dstruck_captial_n');
  s(['QQ'], 'dstruck_captial_q');
  s(['RR'], 'dstruck_captial_r');
  s(['ZZ'], 'dstruck_captial_z');
  s(['f'], 'f');
  s(['g'], 'g');
  // Standard functions
  for (final name in [
    'lim', 'Lim', 'min', 'max', 'sin', 'Sin', 'cos', 'Cos', 'tan', 'Tan', //
    'sinh', 'Sinh', 'cosh', 'Cosh', 'tanh', 'Tanh', 'cot', 'Cot', 'sec',
    'Sec', 'csc', 'Csc', 'arcsin', 'arccos', 'arctan', 'coth', 'sech',
    'csch', 'exp',
  ]) {
    s([name], name);
  }
  s(['abs'], 'abs', 'unary');
  s(['Abs'], 'abs', 'unary');
  s(['norm'], 'norm', 'unary');
  s(['floor'], 'floor', 'unary');
  s(['ceil'], 'ceil', 'unary');
  for (final name in [
    'log', 'Log', 'ln', 'Ln', 'det', 'dim', 'ker', 'mod', 'gcd', 'lcm', //
    'lub', 'glb',
  ]) {
    s([name], name);
  }
  // Arrows
  s(['uarr', 'uparrow'], 'uparrow');
  s(['darr', 'downarrow'], 'downarrow');
  s(['rarr', 'rightarrow'], 'rightarrow');
  s(['->', 'to'], 'to');
  s(['>->', 'rightarrowtail'], 'rightarrowtail');
  s(['->>', 'twoheadrightarrow'], 'twoheadrightarrow');
  s(['>->>', 'twoheadrightarrowtail'], 'twoheadrightarrowtail');
  s(['|->', 'mapsto'], 'mapsto');
  s(['larr', 'leftarrow'], 'leftarrow');
  s(['harr', 'leftrightarrow'], 'leftrightarrow');
  s(['rArr', 'Rightarrow'], 'Rightarrow');
  s(['lArr', 'Leftarrow'], 'Leftarrow');
  s(['hArr', 'Leftrightarrow'], 'Leftrightarrow');
  // Other
  s(['sqrt'], 'sqrt', 'unary');
  s(['root'], 'root', 'binary');
  s(['frac'], 'frac', 'binary');
  s(['/'], 'frac', 'infix');
  s(['stackrel'], 'stackrel', 'binary');
  s(['overset'], 'overset', 'binary');
  s(['underset'], 'underset', 'binary');
  b.add(['color'], 'color', 'binary', convertsToColor: true);
  s(['_'], 'sub', 'infix');
  s(['^'], 'sup', 'infix');
  s(['hat'], 'hat', 'unary');
  s(['bar'], 'overline', 'unary');
  s(['vec'], 'vec', 'unary');
  s(['dot'], 'dot', 'unary');
  s(['ddot'], 'ddot', 'unary');
  s(['overarc', 'overparen'], 'overarc', 'unary');
  s(['ul', 'underline'], 'underline', 'unary');
  s(['ubrace', 'underbrace'], 'underbrace', 'unary');
  s(['obrace', 'overbrace'], 'overbrace', 'unary');
  s(['cancel'], 'cancel', 'unary');
  s(['bb', 'mathbf'], 'bold', 'unary');
  s(['bbb', 'mathbb'], 'double_struck', 'unary');
  s(['ii'], 'italic', 'unary');
  s(['bii'], 'bold_italic', 'unary');
  s(['cc', 'mathcal'], 'script', 'unary');
  s(['bcc'], 'bold_script', 'unary');
  s(['tt', 'mathtt'], 'monospace', 'unary');
  s(['fr', 'mathfrak'], 'fraktur', 'unary');
  s(['bfr'], 'bold_fraktur', 'unary');
  s(['sf', 'mathsf'], 'sans_serif', 'unary');
  s(['bsf'], 'bold_sans_serif', 'unary');
  s(['sfi'], 'sans_serif_italic', 'unary');
  s(['sfbi'], 'sans_serif_bold_italic', 'unary');
  s(['rm'], 'roman', 'unary');
  // Greek letters
  for (final name in [
    'alpha', 'Alpha', 'beta', 'Beta', 'gamma', 'Gamma', 'delta', 'Delta', //
  ]) {
    s([name], name);
  }
  s(['epsi', 'epsilon'], 'epsilon');
  for (final name in [
    'Epsilon', 'varepsilon', 'zeta', 'Zeta', 'eta', 'Eta', 'theta', //
    'Theta', 'vartheta', 'iota', 'Iota', 'kappa', 'Kappa', 'lambda',
    'Lambda', 'mu', 'Mu', 'nu', 'Nu', 'xi', 'Xi', 'omicron', 'Omicron', 'pi',
    'Pi', 'rho', 'Rho', 'sigma', 'Sigma', 'tau', 'Tau', 'upsilon', 'Upsilon',
    'phi', 'Phi', 'varphi', 'chi', 'Chi', 'psi', 'Psi', 'omega', 'Omega',
  ]) {
    s([name], name);
  }
  return b.table;
}();

const Map<String, (int, int, int)> _colors = {
  'aqua': (0, 255, 255),
  'black': (0, 0, 0),
  'blue': (0, 0, 255),
  'fuchsia': (255, 0, 255),
  'gray': (128, 128, 128),
  'green': (0, 128, 0),
  'lime': (0, 255, 0),
  'maroon': (128, 0, 0),
  'navy': (0, 0, 128),
  'olive': (128, 128, 0),
  'purple': (128, 0, 128),
  'red': (255, 0, 0),
  'silver': (192, 192, 192),
  'teal': (0, 128, 128),
  'white': (255, 255, 255),
  'yellow': (255, 255, 0),
};

/// The display table of the MathML builder (`fix_phi: true`, the gem's
/// default).
final Map<String, _Entry> _displaySymbols = () {
  final b = _TableBuilder();
  void d(
    String name,
    String? value,
    String type, {
    bool underover = false,
    String? position,
    String? lparen,
    String? rparen,
  }) => b.add(
    [name],
    value,
    type,
    underover: underover,
    position: position,
    lparen: lparen,
    rparen: rparen,
  );
  void op(String name, String value, {bool underover = false}) =>
      d(name, value, 'operator', underover: underover);
  void id(String name, String value) => d(name, value, 'identifier');
  // Operation symbols
  op('plus', '+');
  op('minus', '−');
  op('cdot', '⋅');
  op('ast', '*');
  op('star', '⋆');
  op('slash', '/');
  op('backslash', r'\');
  op('setminus', r'\');
  op('times', '×');
  op('ltimes', '⋉');
  op('rtimes', '⋊');
  op('bowtie', '⋈');
  op('div', '÷');
  op('circ', '⚬');
  op('oplus', '⊕');
  op('otimes', '⊗');
  op('odot', '⊙');
  op('sum', '∑', underover: true);
  op('prod', '∏', underover: true);
  op('wedge', '∧');
  op('bigwedge', '⋀', underover: true);
  op('vee', '∨');
  op('bigvee', '⋁', underover: true);
  op('cap', '∩');
  op('bigcap', '⋂', underover: true);
  op('cup', '∪');
  op('bigcup', '⋃', underover: true);
  // Relation symbols
  op('eq', '=');
  op('ne', '≠');
  op('assign', '≔');
  op('lt', '<');
  op('mlt', '≪');
  op('gt', '>');
  op('mgt', '≫');
  op('le', '≤');
  op('ge', '≥');
  op('prec', '≺');
  op('succ', '≻');
  op('preceq', '⪯');
  op('succeq', '⪰');
  op('in', '∈');
  op('notin', '∉');
  op('subset', '⊂');
  op('supset', '⊃');
  op('subseteq', '⊆');
  op('supseteq', '⊇');
  op('equiv', '≡');
  op('sim', '∼');
  op('cong', '≅');
  op('approx', '≈');
  op('propto', '∝');
  // Logical symbols
  d('and', 'and', 'text');
  d('or', 'or', 'text');
  op('not', '¬');
  op('implies', '⇒');
  op('if', 'if');
  op('iff', '⇔');
  op('forall', '∀');
  op('exists', '∃');
  op('bot', '⊥');
  op('top', '⊤');
  op('vdash', '⊢');
  op('models', '⊨');
  // Grouping brackets
  d('lparen', '(', 'lparen');
  d('rparen', ')', 'rparen');
  d('lbracket', '[', 'lparen');
  d('rbracket', ']', 'rparen');
  d('lbrace', '{', 'lparen');
  d('rbrace', '}', 'rparen');
  d('vbar', '|', 'lrparen');
  d('langle', '〈', 'lparen');
  d('rangle', '〉', 'rparen');
  d('parallel', '∥', 'lrparen');
  // Miscellaneous symbols
  op('integral', '∫');
  id('dx', 'dx');
  id('dy', 'dy');
  id('dz', 'dz');
  id('dt', 'dt');
  op('contourintegral', '∮');
  op('partial', '∂');
  op('nabla', '∇');
  op('pm', '±');
  op('mp', '∓');
  op('emptyset', '∅');
  op('infty', '∞');
  op('aleph', 'ℵ');
  op('ellipsis', '…');
  op('therefore', '∴');
  op('because', '∵');
  op('angle', '∠');
  op('triangle', '△');
  op('prime', '′');
  d('tilde', '~', 'accent', position: 'over');
  op('nbsp', ' ');
  op('frown', '⌢');
  op('quad', '  ');
  op('qquad', '    ');
  op('cdots', '⋯');
  op('vdots', '⋮');
  op('ddots', '⋱');
  op('diamond', '⋄');
  op('square', '□');
  op('lfloor', '⌊');
  op('rfloor', '⌋');
  op('lceiling', '⌈');
  op('rceiling', '⌉');
  op('dstruck_captial_c', 'ℂ');
  op('dstruck_captial_n', 'ℕ');
  op('dstruck_captial_q', 'ℚ');
  op('dstruck_captial_r', 'ℝ');
  op('dstruck_captial_z', 'ℤ');
  id('f', 'f');
  id('g', 'g');
  // Standard functions
  op('lim', 'lim', underover: true);
  op('Lim', 'Lim', underover: true);
  op('min', 'min', underover: true);
  op('max', 'max', underover: true);
  for (final name in [
    'sin', 'Sin', 'cos', 'Cos', 'tan', 'Tan', 'sinh', 'Sinh', 'cosh', //
    'Cosh', 'tanh', 'Tanh', 'cot', 'Cot', 'sec', 'Sec', 'csc', 'Csc',
    'arcsin', 'arccos', 'arctan', 'coth', 'sech', 'csch', 'exp',
  ]) {
    id(name, name);
  }
  d('abs', 'abs', 'wrap', lparen: '|', rparen: '|');
  d('norm', 'norm', 'wrap', lparen: '∥', rparen: '∥');
  d('floor', 'floor', 'wrap', lparen: '⌊', rparen: '⌋');
  d('ceil', 'ceil', 'wrap', lparen: '⌈', rparen: '⌉');
  for (final name in [
    'log', 'Log', 'ln', 'Ln', 'det', 'dim', 'ker', 'mod', 'gcd', 'lcm', //
    'lub', 'glb',
  ]) {
    id(name, name);
  }
  // Arrows
  op('uparrow', '↑');
  op('downarrow', '↓');
  op('rightarrow', '→');
  op('to', '→');
  op('rightarrowtail', '↣');
  op('twoheadrightarrow', '↠');
  op('twoheadrightarrowtail', '⤖');
  op('mapsto', '↦');
  op('leftarrow', '←');
  op('leftrightarrow', '↔');
  op('Rightarrow', '⇒');
  op('Leftarrow', '⇐');
  op('Leftrightarrow', '⇔');
  // Unary tags
  d('sqrt', 'sqrt', 'sqrt');
  d('cancel', 'cancel', 'cancel');
  // Binary tags
  d('root', 'root', 'root');
  d('frac', 'frac', 'frac');
  d('stackrel', 'stackrel', 'over');
  d('overset', 'overset', 'over');
  d('underset', 'underset', 'under');
  d('color', 'color', 'color');
  op('sub', '_');
  op('sup', '^');
  d('hat', '^', 'accent', position: 'over');
  d('overline', '¯', 'accent', position: 'over');
  d('vec', '→', 'accent', position: 'over');
  d('dot', '.', 'accent', position: 'over');
  d('ddot', '..', 'accent', position: 'over');
  d('overarc', '⏜', 'accent', position: 'over');
  d('underline', '_', 'accent', position: 'under');
  d('underbrace', '⏟', 'accent', position: 'under', underover: true);
  d('overbrace', '⏞', 'accent', position: 'over', underover: true);
  for (final name in [
    'bold', 'double_struck', 'italic', 'bold_italic', 'script', //
    'bold_script', 'monospace', 'fraktur', 'bold_fraktur', 'sans_serif',
    'bold_sans_serif', 'sans_serif_italic', 'sans_serif_bold_italic',
  ]) {
    d(name, name, 'font');
  }
  d('roman', 'normal', 'font');
  // Greek letters
  id('alpha', 'α');
  id('Alpha', 'Α');
  id('beta', 'β');
  id('Beta', 'Β');
  id('gamma', 'γ');
  op('Gamma', 'Γ');
  id('delta', 'δ');
  op('Delta', 'Δ');
  id('epsilon', 'ε');
  id('Epsilon', 'Ε');
  id('varepsilon', 'ɛ');
  id('zeta', 'ζ');
  id('Zeta', 'Ζ');
  id('eta', 'η');
  id('Eta', 'Η');
  id('theta', 'θ');
  op('Theta', 'Θ');
  id('vartheta', 'ϑ');
  id('iota', 'ι');
  id('Iota', 'Ι');
  id('kappa', 'κ');
  id('Kappa', 'Κ');
  id('lambda', 'λ');
  op('Lambda', 'Λ');
  id('mu', 'μ');
  id('Mu', 'Μ');
  id('nu', 'ν');
  id('Nu', 'Ν');
  id('xi', 'ξ');
  op('Xi', 'Ξ');
  id('omicron', 'ο');
  id('Omicron', 'Ο');
  id('pi', 'π');
  op('Pi', 'Π');
  id('rho', 'ρ');
  id('Rho', 'Ρ');
  id('sigma', 'σ');
  op('Sigma', 'Σ');
  id('tau', 'τ');
  id('Tau', 'Τ');
  id('upsilon', 'υ');
  id('Upsilon', 'Υ');
  id('phi', 'ϕ');
  id('varphi', 'φ');
  id('Phi', 'Φ');
  id('chi', 'χ');
  id('Chi', 'Χ');
  id('psi', 'ψ');
  id('Psi', 'Ψ');
  id('omega', 'ω');
  op('Omega', 'Ω');
  return b.table;
}();

// The tokenizer.

/// A token: its value (a symbol's name, a text, a number, an identifier),
/// its type, the symbol's text and table entry.
final class _Token {
  const new(this.value, this.type, {this.text, this.entry});

  final String? value;
  final String type;
  final String? text;
  final _Entry? entry;
}

const _eof = _Token(null, 'eof');

/// The length in characters of the longest of [keys].
int _longest(Iterable<String> keys) =>
    keys.map((k) => k.runes.length).reduce((a, b) => a > b ? a : b);

final class _Tokenizer {
  new(this._input, this._symbols)
    : _symbolRx = RegExp(
        r'((?:\\[ \t\r\n\f\v0-9]|[^ \t\r\n\f\v0-9])'
        '{1,${_longest(_symbols.keys)}})',
        unicode: true,
      );

  final String _input;
  final Map<String, _Entry> _symbols;
  final RegExp _symbolRx;
  int _pos = 0;
  _Token? _pushedBack;

  static final _whitespace = RegExp(r'[ \t\r\n\f\v]+');
  static final _number = RegExp(r'[0-9]+(?:\.[0-9]+)?');
  static final _quotedText = RegExp('"[^"]*"');
  static final _texText = RegExp(r'text\([^)]*\)');

  _Token next() {
    if (_pushedBack case final token?) {
      _pushedBack = null;
      return token;
    }
    _scan(_whitespace);
    if (_pos >= _input.length) return _eof;
    final c = _input[_pos];
    if (c == '"') return _readQuotedText() ?? _readSymbol();
    if (c == 't' && _input.startsWith('text(', _pos)) {
      return _readTexText() ?? _readSymbol();
    }
    if (c == '-' || (c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39)) {
      return _readNumber() ?? _readSymbol();
    }
    return _readSymbol();
  }

  void pushBack(_Token token) {
    if (token.type != 'eof') _pushedBack = token;
  }

  String? _scan(RegExp rx) {
    final match = rx.matchAsPrefix(_input, _pos);
    if (match == null) return null;
    _pos = match.end;
    return match[0];
  }

  _Token? _readQuotedText() => switch (_scan(_quotedText)) {
    final text? => _Token(text.substring(1, text.length - 1), 'text'),
    null => null,
  };

  _Token? _readTexText() => switch (_scan(_texText)) {
    final text? => _Token(text.substring(5, text.length - 1), 'text'),
    null => null,
  };

  _Token? _readNumber() => switch (_scan(_number)) {
    final number? => _Token(number, 'number'),
    null => null,
  };

  /// The longest symbol at the position (the gem's: the longest run the
  /// table's keys may have, shortened a character at a time), else its
  /// first character as an identifier.
  _Token _readSymbol() {
    final position = _pos;
    final matched = _scan(_symbolRx) ?? _input.substring(_pos, _pos + 1);
    var runes = matched.runes.toList();
    var s = String.fromCharCodes(runes);
    while (runes.length > 1 && !_symbols.containsKey(s)) {
      runes = runes.sublist(0, runes.length - 1);
      s = String.fromCharCodes(runes);
    }
    _pos = position + s.length;
    if (_symbols[s] case final entry?) {
      return _Token(entry.value, entry.type, text: s, entry: entry);
    }
    return _Token(s, 'identifier');
  }
}

// The tree.

sealed class _Node {
  _Inner? parent;

  /// Whether [other] is equal to this (the gem's `==`, structural).
  bool eq(_Node? other);
}

/// A node with children, which leave their old parent when added (with
/// every node equal to them: Ruby's `Array#delete`).
abstract class _Inner extends _Node {
  final List<_Node> children = [];

  void add(_Node node) {
    node.parent?.remove(node);
    node.parent = this;
    children.add(node);
  }

  void remove(_Node node) {
    node.parent = null;
    children.removeWhere(node.eq);
  }

  bool _sameChildren(_Inner other) {
    if (other.children.length != children.length) return false;
    for (var i = 0; i < children.length; i++) {
      if (!children[i].eq(other.children[i])) return false;
    }
    return true;
  }
}

bool _eqNullable(_Node? a, _Node? b) => a == null ? b == null : a.eq(b);

final class _Sequence extends _Inner {
  new(List<_Node> nodes) {
    nodes.forEach(add);
  }

  @override
  bool eq(_Node? other) => other is _Sequence && other._sameChildren(this);
}

final class _Paren extends _Inner {
  new(this.lparen, _Node? e, this.rparen) {
    if (e != null) add(e);
  }

  final _Symbol? lparen;
  final _Symbol? rparen;

  _Node? get expression => children.isEmpty ? null : children[0];

  @override
  bool eq(_Node? other) =>
      other is _Paren &&
      _eqNullable(other.lparen, lparen) &&
      _eqNullable(other.expression, expression) &&
      _eqNullable(other.rparen, rparen);
}

final class _Group extends _Inner {
  new(this.lparen, _Node? e, this.rparen) {
    if (e != null) add(e);
  }

  final _Symbol? lparen;
  final _Symbol? rparen;

  _Node? get expression => children.isEmpty ? null : children[0];

  @override
  bool eq(_Node? other) =>
      other is _Group &&
      _eqNullable(other.lparen, lparen) &&
      _eqNullable(other.expression, expression) &&
      _eqNullable(other.rparen, rparen);
}

final class _SubSup extends _Inner {
  new(_Node e, _Node? sub, _Node? sup) {
    add(e);
    add(sub ?? _Empty());
    add(sup ?? _Empty());
  }

  _Node get base => children[0];
  _Node? get sub => children[1] is _Empty ? null : children[1];
  _Node? get sup => children[2] is _Empty ? null : children[2];

  @override
  bool eq(_Node? other) =>
      other is _SubSup &&
      other.base.eq(base) &&
      _eqNullable(other.sub, sub) &&
      _eqNullable(other.sup, sup);
}

final class _Unary extends _Inner {
  new(_Node operator, _Node e) {
    add(operator);
    add(e);
  }

  _Node get operator => children[0];
  _Node get operand => children[1];

  @override
  bool eq(_Node? other) =>
      other is _Unary &&
      other.operator.eq(operator) &&
      other.operand.eq(operand);
}

final class _Binary extends _Inner {
  new(_Node operator, _Node e1, _Node e2) {
    add(operator);
    add(e1);
    add(e2);
  }

  _Node get operator => children[0];
  _Node get operand1 => children[1];
  _Node get operand2 => children[2];

  @override
  bool eq(_Node? other) =>
      other is _Binary &&
      other.operator.eq(operator) &&
      other.operand1.eq(operand1) &&
      other.operand2.eq(operand2);
}

final class _Infix extends _Inner {
  new(_Node operator, _Node e1, _Node e2) {
    add(operator);
    add(e1);
    add(e2);
  }

  _Node get operator => children[0];
  _Node get operand1 => children[1];
  _Node get operand2 => children[2];

  @override
  bool eq(_Node? other) =>
      other is _Infix &&
      other.operator.eq(operator) &&
      other.operand1.eq(operand1) &&
      other.operand2.eq(operand2);
}

final class _Text extends _Node {
  new(this.value);

  final String value;

  @override
  bool eq(_Node? other) => other is _Text && other.value == value;
}

final class _Number extends _Node {
  new(this.value);

  final String value;

  @override
  bool eq(_Node? other) => other is _Number && other.value == value;
}

final class _Symbol extends _Node {
  new(this.value, this.text, this.type);

  final String? value;
  final String text;
  final String type;

  @override
  bool eq(_Node? other) =>
      other is _Symbol &&
      other.value == value &&
      other.text == text &&
      other.type == type;
}

final class _Identifier extends _Node {
  new(this.value);

  final String value;

  @override
  bool eq(_Node? other) => other is _Identifier && other.value == value;
}

final class _Color extends _Node {
  new(this.r, this.g, this.b, this.text);

  final int r;
  final int g;
  final int b;
  final String text;

  String get hexRgb =>
      '#${[r, g, b].map((c) => c.toRadixString(16).padLeft(2, '0')).join()}';

  @override
  bool eq(_Node? other) =>
      other is _Color &&
      other.r == r &&
      other.g == g &&
      other.b == b &&
      other.text == text;
}

final class _Matrix extends _Inner {
  new(this.lparen, List<List<_Node?>> rows, this.rparen) {
    rows.map(_MatrixRow.new).toList().forEach(add);
  }

  final _Symbol? lparen;
  final _Symbol? rparen;

  @override
  bool eq(_Node? other) =>
      other is _Matrix &&
      _eqNullable(other.lparen, lparen) &&
      other._sameChildren(this) &&
      _eqNullable(other.rparen, rparen);
}

final class _MatrixRow extends _Inner {
  new(List<_Node?> nodes) {
    for (final node in nodes) {
      add(node ?? _Empty());
    }
  }

  @override
  bool eq(_Node? other) => other is _MatrixRow && other._sameChildren(this);
}

final class _Empty extends _Node {
  @override
  bool eq(_Node? other) => other is _Empty;
}

/// The gem's `expression(*e)`: nothing, the one node, or a sequence.
_Node? _expression(List<_Node> nodes) => switch (nodes.length) {
  0 => null,
  1 => nodes[0],
  _ => _Sequence(nodes),
};

// The parser.

final class _Parser {
  new(this._symbols);

  final Map<String, _Entry> _symbols;

  _Node? parse(String input) =>
      _expressionOf(_Tokenizer(input, _symbols), null);

  _Node? _expressionOf(_Tokenizer tok, String? closeParenType) {
    _Node? e;
    while (true) {
      final i1 = _intermediate(tok, closeParenType);
      if (i1 == null) break;
      final t1 = tok.next();
      if (t1.type == 'infix' && t1.value == 'frac') {
        final i2 = _intermediate(tok, closeParenType);
        if (i2 != null) {
          e = _concat(
            e,
            _Infix(_symbolOf(t1), _unwrapParen(i1)!, _unwrapParen(i2)!),
          );
        } else {
          e = _concat(e, i1);
        }
      } else if (t1.type == 'eof') {
        e = _concat(e, i1);
        break;
      } else {
        e = _concat(e, i1);
        tok.pushBack(t1);
        if (t1.type == closeParenType) break;
      }
    }
    return e;
  }

  _Node? _intermediate(_Tokenizer tok, String? closeParenType) {
    final s = _simple(tok, closeParenType);
    _Node? sub;
    _Node? sup;
    final t1 = tok.next();
    if (t1.type == 'infix' && t1.value == 'sub') {
      sub = _simple(tok, closeParenType);
      if (sub != null) {
        final t2 = tok.next();
        if (t2.type == 'infix' && t2.value == 'sup') {
          sup = _simple(tok, closeParenType);
        } else {
          tok.pushBack(t2);
        }
      }
    } else if (t1.type == 'infix' && t1.value == 'sup') {
      sup = _simple(tok, closeParenType);
    } else {
      tok.pushBack(t1);
    }
    // (A script on nothing: the gem's SubSup with a nil base, which its
    // own `add` can't take; it doesn't occur in the gem's grammar but at
    // the start of a group, where the base is the empty expression.)
    if (sub != null && sup != null) {
      return _SubSup(s ?? _Empty(), _unwrapParen(sub), _unwrapParen(sup));
    } else if (sub != null) {
      return _SubSup(s ?? _Empty(), _unwrapParen(sub), null);
    } else if (sup != null) {
      return _SubSup(s ?? _Empty(), null, _unwrapParen(sup));
    }
    return s;
  }

  _Node? _simple(_Tokenizer tok, String? closeParenType) {
    final t1 = tok.next();
    switch (t1.type) {
      case 'lparen' || 'lrparen':
        final closeWith = t1.type == 'lparen' ? 'rparen' : 'lrparen';
        var t2 = tok.next();
        if (t2.type == closeWith) {
          return _Paren(_symbolOf(t1), null, _symbolOf(t2));
        }
        tok.pushBack(t2);
        final e = _expressionOf(tok, closeWith);
        t2 = tok.next();
        if (t2.type == closeWith) {
          return _toMatrix(_Paren(_symbolOf(t1), e, _symbolOf(t2)));
        }
        tok.pushBack(t2);
        if (t1.type == 'lrparen') return _concat(_symbolOf(t1), e);
        return _Paren(_symbolOf(t1), e, null);
      case 'rparen':
        if (closeParenType == null) return _symbolOf(t1);
        tok.pushBack(t1);
        return null;
      case 'unary':
        var s = _unwrapParen(_simple(tok, closeParenType));
        s ??= _Identifier('');
        return _Unary(_symbolOf(t1), s);
      case 'binary':
        var s1 = _unwrapParen(_simple(tok, closeParenType));
        s1 ??= _Identifier('');
        var s2 = _unwrapParen(_simple(tok, closeParenType));
        s2 ??= _Identifier('');
        if (t1.entry?.convertsToColor ?? false) s1 = _toColor(s1);
        return _Binary(_symbolOf(t1), s1, s2);
      case 'eof':
        return null;
      case 'number':
        return _Number(t1.value!);
      case 'text':
        return _Text(t1.value!);
      case 'identifier':
        return _Identifier(t1.value!);
      default:
        return _symbolOf(t1);
    }
  }

  _Node? _concat(_Node? e1, _Node? e2) {
    if (e1 is _Sequence) {
      if (e2 is _Sequence) {
        return _expression([...e1.children, ...e2.children]);
      }
      return e2 == null ? e1 : _expression([...e1.children, e2]);
    }
    if (e1 == null) return e2;
    if (e2 is _Sequence) return _expression([e1, ...e2.children]);
    return e2 == null ? e1 : _expression([e1, e2]);
  }

  _Symbol _symbolOf(_Token t) => _Symbol(t.value, t.text ?? '', t.type);

  _Node? _unwrapParen(_Node? node) {
    if (node is _Paren &&
        (node.lparen == null || node.lparen!.type == 'lparen') &&
        (node.rparen == null || node.rparen!.type == 'rparen')) {
      return _Group(node.lparen, node.expression, node.rparen);
    }
    return node;
  }

  bool _isSeparator(_Node node) => node is _Identifier && node.value == ',';

  _Node _toMatrix(_Paren node) {
    final List<_Node> rows;
    final List<_Node> separators;
    switch (node.expression) {
      case final _Sequence sequence:
        rows = [
          for (final (i, n) in sequence.children.indexed)
            if (i.isEven) n,
        ];
        separators = [
          for (final (i, n) in sequence.children.indexed)
            if (i.isOdd) n,
        ];
      case final _Paren paren:
        rows = [paren];
        separators = [];
      default:
        return node;
    }
    bool paren(_Node row, String l, String lt, String r, String rt) =>
        row is _Paren &&
        _eqNullable(row.lparen, _Symbol(l, lt, 'lparen')) &&
        _eqNullable(row.rparen, _Symbol(r, rt, 'rparen'));
    if (!(rows.isNotEmpty &&
        rows.length > separators.length &&
        separators.every(_isSeparator) &&
        (rows.every((r) => paren(r, 'lparen', '(', 'rparen', ')')) ||
            rows.every((r) => paren(r, 'lbracket', '[', 'rbracket', ']'))))) {
      return node;
    }
    final cells = [
      for (final row in rows)
        () {
          final content = (row as _Paren).expression;
          if (content is! _Sequence) {
            return <_Node?>[
              _expression([?content]),
            ];
          }
          final chunks = <List<_Node>>[];
          var current = <_Node>[];
          for (final item in [...content.children]) {
            if (_isSeparator(item)) {
              chunks.add(current);
              current = [];
            } else {
              current.add(item);
            }
          }
          chunks.add(current);
          return <_Node?>[
            for (final c in chunks)
              if (c.length == 1) c[0] else _expression(c),
          ];
        }(),
    ];
    if (!cells.every((row) => row.length == cells[0].length)) return node;
    return _Matrix(node.lparen, cells, node.rparen);
  }

  _Color _toColor(_Node expression) {
    final s = StringBuffer();
    _colorText(s, expression);
    final text = s.toString();
    final six = RegExp(
      '#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})',
      caseSensitive: false,
    ).firstMatch(text);
    if (six != null) {
      return _Color(
        int.parse(six[1]!, radix: 16),
        int.parse(six[2]!, radix: 16),
        int.parse(six[3]!, radix: 16),
        text,
      );
    }
    final three = RegExp(
      '#([0-9a-f])([0-9a-f])([0-9a-f])',
      caseSensitive: false,
    ).firstMatch(text);
    if (three != null) {
      int twice(String h) => int.parse('$h$h', radix: 16);
      return _Color(twice(three[1]!), twice(three[2]!), twice(three[3]!), text);
    }
    final (r, g, b) = _colors[text.toLowerCase()] ?? (0, 0, 0);
    return _Color(r, g, b, text);
  }

  void _colorText(StringBuffer s, _Node? node) {
    switch (node) {
      case _Sequence(:final children):
        for (final n in children) {
          _colorText(s, n);
        }
      case _Number(:final value) || _Identifier(:final value):
        s.write(value);
      case _Text(:final value):
        s.write(value);
      case _Symbol(:final text):
        s.write(text);
      case _Group(:final expression):
        _colorText(s, expression);
      case _Paren(:final lparen, :final expression, :final rparen):
        _colorText(s, lparen);
        _colorText(s, expression);
        _colorText(s, rparen);
      case final _SubSup sub:
        // (The gem's: the base, then `operator` and `operand2`, which a
        // SubSup hasn't: Ruby raises; nothing more here.)
        _colorText(s, sub.base);
      case _Unary(:final operator, :final operand):
        _colorText(s, operator);
        _colorText(s, operand);
      case _Binary(:final operator, :final operand1, :final operand2):
        _colorText(s, operator);
        _colorText(s, operand1);
        _colorText(s, operand2);
      case _Infix(:final operator, :final operand1, :final operand2):
        _colorText(s, operand1);
        _colorText(s, operator);
        _colorText(s, operand2);
      default:
        break;
    }
  }
}

// The MathML.

final class _MathmlBuilder {
  new(this._prefix);

  final String _prefix;
  final StringBuffer _out = StringBuffer();
  static const _Row _rowMode = _Row.avoid;

  @override
  String toString() => _out.toString();

  void appendExpression(_Node? expression, Map<String, String> attrs) =>
      _tag('math', attrs: attrs, body: () => _append(expression, _Row.omit));

  void _append(_Node? node, [_Row row = _Row.avoid]) {
    switch (node) {
      case final _Sequence sequence:
        if ((sequence.children.length <= 1 && row == _Row.avoid) ||
            row == _Row.omit) {
          [...sequence.children].forEach(_append);
        } else {
          _tag('mrow', body: () => [...sequence.children].forEach(_append));
        }
      case _Group(:final expression):
        _append(expression);
      case _Text(:final value):
        _tag('mtext', text: value);
      case _Number(:final value):
        _tag('mn', text: value);
      case _Identifier(:final value):
        _identifierOrOperator(value);
      case final _Symbol symbol:
        if (_resolve(symbol) case final entry?) {
          switch (entry.type) {
            case 'operator' || 'accent' || 'lparen' || 'rparen' || 'lrparen':
              _tag('mo', text: entry.value);
            default:
              _tag('mi', text: entry.value);
          }
        } else {
          _identifierOrOperator(symbol.value ?? '');
        }
      case _Paren(:final lparen, :final expression, :final rparen):
        _paren(_resolveParen(lparen), expression, _resolveParen(rparen));
      case final _SubSup subsup:
        if (_isUnderover(subsup.base)) {
          _underover(subsup.base, subsup.sub, subsup.sup);
        } else {
          _subsup(subsup.base, subsup.sub, subsup.sup);
        }
      case final _Unary unary:
        final entry = _resolve(unary.operator);
        if (entry == null) break;
        switch (entry.type) {
          case 'identifier':
            _tag(
              'mrow',
              body: () {
                _tag('mi', text: entry.value);
                _append(unary.operand);
              },
            );
          case 'operator':
            _tag(
              'mrow',
              body: () {
                _tag('mo', text: entry.value);
                _append(unary.operand);
              },
            );
          case 'wrap':
            _paren(
              _resolveParenText(entry.lparen),
              unary.operand,
              _resolveParenText(entry.rparen),
            );
          case 'accent':
            if (entry.position == 'over') {
              _underover(unary.operand, null, unary.operator);
            } else {
              _underover(unary.operand, unary.operator, null);
            }
          case 'font':
            _tag(
              'mstyle',
              attrs: {'mathvariant': entry.value!.replaceAll('_', '-')},
              body: () => _append(unary.operand),
            );
          case 'cancel':
            _tag(
              'menclose',
              attrs: {'notation': 'updiagonalstrike'},
              body: () => _append(unary.operand, _Row.omit),
            );
          case 'sqrt':
            _tag('msqrt', body: () => _append(unary.operand));
        }
      case final _Binary binary:
        final entry = _resolve(binary.operator);
        if (entry == null) break;
        switch (entry.type) {
          case 'over':
            _underover(binary.operand2, null, binary.operand1);
          case 'under':
            _underover(binary.operand2, binary.operand1, null);
          case 'root':
            _tag(
              'mroot',
              body: () {
                _append(binary.operand2);
                _append(binary.operand1);
              },
            );
          case 'color':
            final color = binary.operand1;
            _tag(
              'mstyle',
              attrs: {'mathcolor': color is _Color ? color.hexRgb : ''},
              body: () => _append(binary.operand2),
            );
          case 'frac':
            _fraction(binary.operand1, binary.operand2);
        }
      case final _Infix infix:
        if (_resolve(infix.operator)?.type == 'frac') {
          _fraction(infix.operand1, infix.operand2);
        }
      case final _Matrix matrix:
        _fenced(_resolveParen(matrix.lparen), _resolveParen(matrix.rparen), () {
          _tag(
            'mtable',
            body: () {
              for (final row in [...matrix.children]) {
                _tag(
                  'mtr',
                  body: () {
                    for (final col in [...(row as _Inner).children]) {
                      _tag('mtd', body: () => _append(col));
                    }
                  },
                );
              }
            },
          );
        });
      default:
        break;
    }
  }

  void _fraction(_Node numerator, _Node denominator) => _tag(
    'mfrac',
    body: () {
      _append(numerator);
      _append(denominator);
    },
  );

  void _paren(String? lparen, _Node? e, String? rparen) =>
      _fenced(lparen, rparen, () => _append(e));

  void _subsup(_Node base, _Node? sub, _Node? sup) {
    if (sub != null && sup != null) {
      _tag(
        'msubsup',
        body: () {
          _append(base);
          _append(sub);
          _append(sup);
        },
      );
    } else if (sub != null) {
      _tag(
        'msub',
        body: () {
          _append(base);
          _append(sub);
        },
      );
    } else if (sup != null) {
      _tag(
        'msup',
        body: () {
          _append(base);
          _append(sup);
        },
      );
    } else {
      _append(base);
    }
  }

  void _underover(_Node base, _Node? sub, _Node? sup) {
    final attrs = <String, String>{};
    var subRow = _rowMode;
    if (_isAccent(sub)) {
      attrs['accentunder'] = 'true';
      subRow = _Row.avoid;
    }
    var supRow = _rowMode;
    if (_isAccent(sup)) {
      attrs['accent'] = 'true';
      supRow = _Row.avoid;
    }
    if (sub != null && sup != null) {
      _tag(
        'munderover',
        attrs: attrs,
        body: () {
          _append(base);
          _append(sub, subRow);
          _append(sup, supRow);
        },
      );
    } else if (sub != null) {
      _tag(
        'munder',
        attrs: attrs,
        body: () {
          _append(base);
          _append(sub, subRow);
        },
      );
    } else if (sup != null) {
      _tag(
        'mover',
        attrs: attrs,
        body: () {
          _append(base);
          _append(sup, supRow);
        },
      );
    } else {
      _append(base);
    }
  }

  void _fenced(String? lparen, String? rparen, void Function() body) {
    if (lparen != null || rparen != null) {
      _tag(
        'mrow',
        body: () {
          if (lparen != null) _tag('mo', text: lparen);
          body();
          if (rparen != null) _tag('mo', text: rparen);
        },
      );
    } else {
      body();
    }
  }

  void _identifierOrOperator(String value) {
    if (value.isEmpty ||
        RegExp(r'[\p{Alphabetic}\p{Nd}]', unicode: true).hasMatch(value)) {
      _tag('mi', text: value);
    } else {
      _tag('mo', text: value);
    }
  }

  _Entry? _resolve(_Node? node) =>
      node is _Symbol ? _displaySymbols[node.value] : null;

  String? _resolveParen(_Symbol? paren) {
    if (paren == null) return null;
    return _resolve(paren)?.value ?? paren.value;
  }

  /// A wrap's parenthesis (a string: the gem's `resolve_symbol` finds no
  /// entry for a String, so it is the string itself).
  String? _resolveParenText(String? paren) => paren;

  bool _isAccent(_Node? node) => _resolve(node)?.type == 'accent';

  bool _isUnderover(_Node node) =>
      _resolve(node is _Unary ? node.operator : node)?.underover ?? false;

  void _tag(
    String name, {
    Map<String, String> attrs = const {},
    String? text,
    void Function()? body,
  }) {
    _out
      ..write('<')
      ..write(_prefix)
      ..write(name);
    for (final MapEntry(:key, :value) in attrs.entries) {
      _out.write(' $key="');
      _escaped(value);
      _out.write('"');
    }
    // (Always an end tag: the gem's text defaults to '', which Ruby takes
    // as true.)
    _out.write('>');
    _escaped(text ?? '');
    body?.call();
    _out
      ..write('</')
      ..write(_prefix)
      ..write(name)
      ..write('>');
  }

  void _escaped(String text) {
    for (final cp in text.runes) {
      if (cp == 38) {
        _out.write('&amp;');
      } else if (cp == 60) {
        _out.write('&lt;');
      } else if (cp == 62) {
        _out.write('&gt;');
      } else if (cp > 127) {
        _out.write('&#x${cp.toRadixString(16).toUpperCase()};');
      } else {
        _out.writeCharCode(cp);
      }
    }
  }
}

enum _Row { avoid, omit }
