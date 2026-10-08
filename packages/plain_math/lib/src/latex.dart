/// LaTeX math to MathML (ADR-0014): the commands of LaTeX's and amsmath's
/// math mode that documents use (KaTeX's and MathJax's common set), as
/// Presentation MathML for the PDF's math layout.
///
/// What it reads: groups, scripts and primes; `\frac`, `\dfrac`,
/// `\tfrac`, `\binom`, `\sqrt[n]`; `\left`, `\middle`, `\right`; Greek
/// letters, operators, relations, arrows and other symbols; large
/// operators with `\limits` and `\nolimits`; function names and
/// `\operatorname`; accents, `\overline`, `\underline`, braces with their
/// labels, `\overset`, `\underset`, `\stackrel`; `\text`, the `\math...`
/// alphabets, `\boldsymbol`; `\color`, `\textcolor`; `\boxed`, `\cancel`;
/// spaces; the `matrix` environments, `cases`, `array`, `aligned`,
/// `gathered`. A command it doesn't know is shown as its name.
library;

/// The MathML of the LaTeX math [tex] (a `math` element, in display
/// style when [display]). The commands it doesn't know are added to
/// [unknown], when given.
String latexToMathml(String tex, {bool display = false, Set<String>? unknown}) {
  final parser = _Parser(tex, unknown ?? <String>{});
  final body = parser.parseUntil(const {});
  final attrs = display ? ' display="block"' : '';
  return '<math xmlns="http://www.w3.org/1998/Math/MathML"$attrs>'
      '${_row(body)}</math>';
}

/// A parsed piece: its MathML, and how scripts attach to it.
final class _Node {
  const new(this.xml, {this.limits = false, this.movable = false});

  final String xml;

  /// Scripts go under and over it (a large operator, `lim`).
  final bool limits;

  /// Its limits become scripts outside display style.
  final bool movable;
}

String _row(List<_Node> nodes) => nodes.length == 1
    ? nodes.single.xml
    : '<mrow>${nodes.map((n) => n.xml).join()}</mrow>';

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;');

_Node _mi(String text, {String? variant}) => _Node(
  '<mi${variant == null ? '' : ' mathvariant="$variant"'}>'
  '${_escape(text)}</mi>',
);

_Node _mo(
  String text, {
  bool? stretchy,
  bool fence = false,
  bool limits = false,
  bool movable = false,
  String? form,
}) => _Node(
  '<mo'
  '${stretchy == null ? '' : ' stretchy="$stretchy"'}'
  '${fence ? ' fence="true"' : ''}'
  '${form == null ? '' : ' form="$form"'}'
  '${movable ? ' movablelimits="true"' : ''}'
  '>${_escape(text)}</mo>',
  limits: limits,
  movable: movable,
);

final RegExp _letter = RegExp(r'^[\p{L}\p{N}]', unicode: true);

final class _Parser {
  new(this.source, this.unknown);

  final String source;
  final Set<String> unknown;
  int at = 0;

  bool get done => at >= source.length;

  void skipSpace() {
    while (!done) {
      final c = source[at];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        at++;
      } else if (c == '%') {
        while (!done && source[at] != '\n') {
          at++;
        }
      } else {
        break;
      }
    }
  }

  /// The next token without consuming it: a command (`\name`, or `\` and
  /// one character), or one character (a code point: a surrogate pair is
  /// one); null at the end.
  String? peek() {
    skipSpace();
    if (done) return null;
    final c = source[at];
    if (c != r'\') {
      final unit = source.codeUnitAt(at);
      return unit >= 0xd800 &&
              unit < 0xdc00 &&
              at + 1 < source.length &&
              (source.codeUnitAt(at + 1) & 0xfc00) == 0xdc00
          ? source.substring(at, at + 2)
          : c;
    }
    if (at + 1 >= source.length) return r'\';
    final m = RegExp('[a-zA-Z]+').matchAsPrefix(source, at + 1);
    if (m != null) return '\\${m[0]}';
    return '\\${source[at + 1]}';
  }

  String? next() {
    final token = peek();
    if (token != null) at += token.length;
    return token;
  }

  /// Pieces up to (not consuming) one of [stops] or the end; a `}` ends
  /// any group.
  List<_Node> parseUntil(Set<String> stops) {
    final nodes = <_Node>[];
    while (true) {
      final token = peek();
      if (token == null || stops.contains(token) || token == '}') break;
      // \color{c}: the rest of the group in that color.
      if (token == r'\color') {
        next();
        final color = _rawArgument();
        final rest = parseUntil(stops);
        nodes.add(
          _Node('<mstyle mathcolor="${_escape(color)}">${_row(rest)}</mstyle>'),
        );
        break;
      }
      if (token == r'\displaystyle' || token == r'\textstyle') {
        next();
        final rest = parseUntil(stops);
        nodes.add(
          _Node(
            '<mstyle displaystyle="${token == r'\displaystyle'}">'
            '${_row(rest)}</mstyle>',
          ),
        );
        break;
      }
      final atom = parseAtom();
      if (atom == null) continue;
      nodes.add(_scripts(atom));
    }
    return nodes;
  }

  /// [base] with the scripts and primes that follow it.
  _Node _scripts(_Node base) {
    var limits = base.limits;
    String? sub;
    String? sup;
    var primes = 0;
    while (true) {
      final token = peek();
      if (token == r'\limits') {
        next();
        limits = true;
      } else if (token == r'\nolimits') {
        next();
        limits = false;
      } else if (token == "'") {
        next();
        primes++;
      } else if (token == '^' && sup == null) {
        next();
        sup = _argument();
      } else if (token == '_' && sub == null) {
        next();
        sub = _argument();
      } else {
        break;
      }
    }
    if (primes > 0) {
      final prime = '<mo>${'\u2032' * primes}</mo>';
      sup = sup == null ? prime : '<mrow>$prime$sup</mrow>';
    }
    if (sub == null && sup == null) return base;
    final tag = limits
        ? (sub != null && sup != null
              ? 'munderover'
              : sub != null
              ? 'munder'
              : 'mover')
        : (sub != null && sup != null
              ? 'msubsup'
              : sub != null
              ? 'msub'
              : 'msup');
    return _Node('<$tag>${base.xml}${sub ?? ''}${sup ?? ''}</$tag>');
  }

  /// A command's or a script's argument: a group, or a single piece.
  String _argument() {
    final token = peek();
    if (token == '{') {
      next();
      final nodes = parseUntil(const {});
      if (peek() == '}') next();
      return _row(nodes);
    }
    // As TeX takes it: one character (a digit of a number alone).
    if (token != null && RegExp('[0-9]').hasMatch(token)) {
      next();
      return '<mn>$token</mn>';
    }
    final atom = parseAtom();
    return atom?.xml ?? '<mrow></mrow>';
  }

  /// The text of a `{...}` argument as written (a color, an environment's
  /// name, `\text`'s text).
  String _rawArgument() {
    skipSpace();
    if (done) return '';
    if (source[at] != '{') {
      final token = next() ?? '';
      return token;
    }
    var depth = 0;
    final start = at + 1;
    for (; at < source.length; at++) {
      final c = source[at];
      if (c == r'\') {
        at++;
        continue;
      }
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) {
          return source.substring(start, at++);
        }
      }
    }
    return source.substring(start);
  }

  /// The text of an optional `[...]` argument as written.
  String _rawOptional() {
    next(); // [
    final end = source.indexOf(']', at);
    final text = source.substring(at, end < 0 ? source.length : end);
    at = end < 0 ? source.length : end + 1;
    return text;
  }

  /// An optional `[...]` argument, parsed.
  String? _optional() {
    if (peek() != '[') return null;
    next();
    final nodes = parseUntil(const {']'});
    if (peek() == ']') next();
    return _row(nodes);
  }

  _Node? parseAtom() {
    final token = next();
    if (token == null) return null;
    if (token == '{') {
      final nodes = parseUntil(const {});
      if (peek() == '}') next();
      return _Node(_row(nodes));
    }
    if (token.startsWith(r'\') && token.length > 1) return _command(token);
    if (RegExp('[0-9]').hasMatch(token)) {
      final m = RegExp(r'[0-9]*(?:\.[0-9]+)?').matchAsPrefix(source, at);
      final digits = token + (m?[0] ?? '');
      at += (m?[0] ?? '').length;
      return _Node('<mn>$digits</mn>');
    }
    // Letters of any script, and digits other than ASCII's (`𝟎`).
    if (_letter.hasMatch(token)) return _mi(token);
    return switch (token) {
      '(' || '[' => _mo(token, stretchy: false),
      ')' || ']' => _mo(token, stretchy: false, form: 'postfix'),
      '|' => _mo('|', stretchy: false),
      '-' => _mo('\u2212'),
      '*' => _mo('\u2217'),
      '~' => const _Node('<mspace width="0.333em"/>'),
      '&' || '^' || '_' => null,
      _ => _mo(token),
    };
  }

  _Node? _command(String command) {
    final name = command.substring(1);
    if (name == 'dots') {
      // amsmath's: centered before an operator (`\dots +`, `\dots \int`),
      // on the line otherwise.
      final after = peek();
      final centered = switch (after) {
        '+' || '-' || '=' || '<' || '>' || '*' => true,
        final String c when c.startsWith(r'\') && c.length > 2 =>
          _largeOperators.containsKey(c.substring(1)) ||
              _symbols[c.substring(1)]?.$2 == _Kind.operator,
        _ => false,
      };
      return _mo(centered ? '\u22ef' : '\u2026');
    }
    if (_symbols[name] case final symbol?) {
      return _symbolNode(symbol);
    }
    if (_functions.contains(name)) return _mi(name);
    if (_limitFunctions[name] case final text?) {
      return _mo(text, limits: true, movable: true);
    }
    if (_largeOperators[name] case final op?) {
      final integral = _integrals.contains(name);
      return _mo(op, limits: !integral, movable: !integral);
    }
    if (_spaces[name] case final width?) {
      return _Node('<mspace width="$width"/>');
    }
    if (_variants[name] case final variant?) {
      final text = name.startsWith('text') || name == 'mbox';
      if (text) return _text(_rawArgument(), variant: variant);
      return _Node('<mstyle mathvariant="$variant">${_argument()}</mstyle>');
    }
    if (_accents[name] case (final accent, final over)?) {
      final base = _argument();
      return over
          ? _Node('<mover accent="true">$base<mo>$accent</mo></mover>')
          : _Node('<munder accentunder="true">$base<mo>$accent</mo></munder>');
    }
    switch (name) {
      case 'frac' || 'dfrac' || 'tfrac' || 'cfrac':
        final num = _argument();
        final den = _argument();
        final frac = '<mfrac>$num$den</mfrac>';
        return _Node(switch (name) {
          'dfrac' || 'cfrac' => '<mstyle displaystyle="true">$frac</mstyle>',
          'tfrac' => '<mstyle displaystyle="false">$frac</mstyle>',
          _ => frac,
        });
      case 'binom' || 'dbinom' || 'tbinom':
        final n = _argument();
        final k = _argument();
        return _Node(
          '<mrow><mo>(</mo><mfrac linethickness="0">$n$k</mfrac>'
          '<mo>)</mo></mrow>',
        );
      case 'sqrt':
        final index = _optional();
        final radicand = _argument();
        return _Node(
          index == null
              ? '<msqrt>$radicand</msqrt>'
              : '<mroot>$radicand$index</mroot>',
        );
      case 'left':
        return _fenced();
      case 'right' || 'middle':
        // Unbalanced: the delimiter alone.
        return _delimiter(stretchy: true);
      case 'big' ||
          'Big' ||
          'bigg' ||
          'Bigg' ||
          'bigl' ||
          'bigr' ||
          'Bigl' ||
          'Bigr' ||
          'biggl' ||
          'biggr' ||
          'Biggl' ||
          'Biggr' ||
          'bigm' ||
          'Bigm':
        return _delimiter(stretchy: false);
      case 'text' || 'textrm' || 'mbox' || 'textnormal' || 'hbox':
        return _text(_rawArgument());
      case 'operatorname':
        // \operatorname*: limits under and over.
        final star = peek() == '*';
        if (star) next();
        final text = _rawArgument()
            .replaceAllMapped(
              RegExp(r'\\([a-zA-Z]+)'),
              (m) => _symbols[m[1]]?.$1 ?? _unknown(m[0]!),
            )
            .replaceAll(RegExp(r'\s'), '');
        return star ? _mo(text, limits: true, movable: true) : _mi(text);
      case 'mathop':
        return _mo(_rawArgument(), limits: true, movable: true);
      case 'overset' || 'stackrel':
        final over = _argument();
        final base = _argument();
        return _Node('<mover>$base$over</mover>', limits: true);
      case 'underset':
        final under = _argument();
        final base = _argument();
        return _Node('<munder>$base$under</munder>', limits: true);
      case 'overbrace' || 'underbrace':
        final base = _argument();
        final over = name == 'overbrace';
        final brace = over ? '\u23de' : '\u23df';
        return _Node(
          over
              ? '<mover accent="true">$base<mo>$brace</mo></mover>'
              : '<munder accentunder="true">$base<mo>$brace</mo></munder>',
          limits: true,
        );
      case 'textcolor':
        final color = _rawArgument();
        return _Node(
          '<mstyle mathcolor="${_escape(color)}">${_argument()}</mstyle>',
        );
      case 'boxed' || 'fbox':
        return _Node('<menclose notation="box">${_argument()}</menclose>');
      case 'cancel' || 'bcancel' || 'xcancel' || 'sout':
        final notation = switch (name) {
          'bcancel' => 'downdiagonalstrike',
          'xcancel' => 'updiagonalstrike downdiagonalstrike',
          'sout' => 'horizontalstrike',
          _ => 'updiagonalstrike',
        };
        return _Node(
          '<menclose notation="$notation">${_argument()}</menclose>',
        );
      case 'not':
        final negated = parseAtom();
        if (negated == null) return null;
        // A letter struck through (`\not x`).
        if (RegExp(r'^<mi>(.)</mi>$').firstMatch(negated.xml) case final mi?) {
          return _mi('${mi[1]}\u0338');
        }
        final m = RegExp('<mo>(.*?)</mo>').firstMatch(negated.xml);
        if (m == null) return negated;
        final text = m[1]!
            .replaceAll('&lt;', '<')
            .replaceAll('&gt;', '>')
            .replaceAll('&amp;', '&');
        final combined = _negations[text] ?? '$text\u0338';
        return _mo(combined);
      case 'begin':
        return _environment(_rawArgument());
      case 'end':
        _rawArgument();
        return null;
      case 'limits' ||
          'nolimits' ||
          'displaystyle' ||
          'textstyle' ||
          'scriptstyle' ||
          'scriptscriptstyle' ||
          'nonumber' ||
          'notag' ||
          'label' ||
          'tag':
        if (name == 'label' || name == 'tag') _rawArgument();
        return null;
      case r'\':
        return null;
    }
    // A single character escaped: \{ \} \| \_ \# \% \& \$.
    if (name.length == 1) {
      return switch (name) {
        '{' => _mo('{', stretchy: false),
        '}' => _mo('}', stretchy: false, form: 'postfix'),
        '|' => _mo('\u2016', stretchy: false),
        _ => _mo(name),
      };
    }
    return _Node('<mtext>${_escape(_unknown(command))}</mtext>');
  }

  /// [command], noted as unknown.
  String _unknown(String command) {
    unknown.add(command);
    return command;
  }

  _Node _symbolNode((String, _Kind) symbol) {
    final (text, kind) = symbol;
    return switch (kind) {
      _Kind.identifier => _mi(text),
      _Kind.upright => _mi(text, variant: 'normal'),
      _Kind.operator => _mo(text),
      _Kind.open => _mo(text, stretchy: false),
      _Kind.close => _mo(text, stretchy: false, form: 'postfix'),
    };
  }

  /// [raw], a `\text` argument, in text mode: `mtext` (in [variant]),
  /// with groups, `~` and `\ `, escaped characters, accents (`\"o`), the
  /// text style commands (their style aside), TeX's ligatures (```` `` ````,
  /// `''`, `--`, `---`) and runs of spaces read as TeX does, and math in
  /// it (`$...$`) set as math. Other commands are noted as unknown.
  _Node _text(String raw, {String? variant}) {
    final parts = <String>[];
    final run = StringBuffer();
    void flush() {
      if (run.isEmpty) return;
      final attrs = variant == null ? '' : ' mathvariant="$variant"';
      parts.add('<mtext$attrs>${_escape('$run')}</mtext>');
      run.clear();
    }

    void space() {
      if (run.isEmpty || !'$run'.endsWith(' ')) run.write(' ');
    }

    var i = 0;

    /// The code point at [i] (a surrogate pair whole), consumed.
    String char() {
      final unit = raw.codeUnitAt(i);
      final pair = (unit & 0xfc00) == 0xd800 && i + 1 < raw.length;
      return raw.substring(i, i += pair ? 2 : 1);
    }

    while (i < raw.length) {
      final c = raw[i];
      if (c == '{' || c == '}') {
        i++;
      } else if (c == '~') {
        run.write('\u00a0');
        i++;
      } else if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        space();
        i++;
      } else if (c == r'$') {
        final end = _closingDollar(raw, i + 1);
        flush();
        final math = _Parser(raw.substring(i + 1, end), unknown);
        parts.add(_row(math.parseUntil(const {})));
        i = end + 1;
      } else if (c == r'\' && i + 1 < raw.length) {
        final word = RegExp('[a-zA-Z]+').matchAsPrefix(raw, i + 1);
        final name = word?[0] ?? raw[i + 1];
        i += 1 + name.length;
        if (_textAccents[name] case final mark?) {
          while (i < raw.length && (raw[i] == ' ' || raw[i] == '{')) {
            i++;
          }
          if (raw.startsWith(r'\i', i) || raw.startsWith(r'\j', i)) {
            run.write(raw[i + 1] == 'i' ? '\u0131' : '\u0237');
            i += 2;
          } else if (i < raw.length) {
            run.write(char());
          }
          run.write(mark);
          if (i < raw.length && raw[i] == '}') i++;
        } else if (_textSymbols[name] case final text?) {
          run.write(text);
        } else if (name == ' ') {
          space();
        } else if (word == null) {
          run.write(name); // \$ \{ \} \& \% \# \_
        } else if (!_textStyles.contains(name)) {
          run.write(_unknown('\\$name'));
        }
        // A control word ends at the spaces after it.
        if (word != null) {
          while (i < raw.length && raw[i] == ' ') {
            i++;
          }
        }
      } else {
        final ligature = _textLigatures.entries
            .where((l) => raw.startsWith(l.key, i))
            .firstOrNull;
        if (ligature != null) {
          run.write(ligature.value);
          i += ligature.key.length;
        } else {
          run.write(char());
        }
      }
    }
    flush();
    if (parts.isEmpty) return const _Node('<mtext></mtext>');
    return _Node(
      parts.length == 1 ? parts.single : '<mrow>${parts.join()}</mrow>',
    );
  }

  /// The delimiter after `\left`, `\middle`, `\right` or `\big`
  /// (nothing for `.`).
  _Node _delimiter({required bool stretchy, String? form}) {
    final token = next();
    final text = switch (token) {
      null || '.' => '',
      r'\{' || r'\lbrace' => '{',
      r'\}' || r'\rbrace' => '}',
      r'\|' || r'\Vert' || r'\lVert' || r'\rVert' => '\u2016',
      r'\vert' || r'\lvert' || r'\rvert' || r'\mid' => '|',
      r'\langle' || r'\lang' => '\u27e8',
      r'\rangle' || r'\rang' => '\u27e9',
      r'\lfloor' => '\u230a',
      r'\rfloor' => '\u230b',
      r'\lceil' => '\u2308',
      r'\rceil' => '\u2309',
      r'\uparrow' => '\u2191',
      r'\downarrow' => '\u2193',
      r'\updownarrow' => '\u2195',
      r'\backslash' => r'\',
      '/' => '/',
      final command when command.startsWith(r'\') && command.length > 2 =>
        _symbols[command.substring(1)]?.$1 ?? _unknown(command),
      _ => token,
    };
    if (text.isEmpty) return const _Node('');
    return _mo(text, stretchy: stretchy, fence: stretchy, form: form);
  }

  /// `\left` ... `\middle` ... `\right`: a row with stretchy delimiters.
  _Node _fenced() {
    final parts = <String>[_delimiter(stretchy: true).xml];
    while (true) {
      final inner = parseUntil(const {r'\right', r'\middle'});
      parts.add(_row(inner));
      final token = next();
      if (token == r'\middle') {
        parts.add(_delimiter(stretchy: true).xml);
        continue;
      }
      if (token == r'\right') {
        parts.add(_delimiter(stretchy: true, form: 'postfix').xml);
      }
      break;
    }
    return _Node('<mrow>${parts.join()}</mrow>');
  }

  /// The environment [name] up to its `\end`.
  _Node? _environment(String name) {
    final bare = name.replaceAll('*', '');
    if (!_environments.contains(bare)) _unknown('\\begin{$name}');
    String? columns;
    if (bare == 'array' || bare == 'subarray') {
      columns = _rawArgument();
    } else if (bare == 'alignat' || bare == 'alignedat') {
      _rawArgument(); // the number of column pairs
    } else if (name.endsWith('matrix*') && peek() == '[') {
      columns = _rawOptional(); // its columns' alignment: l, c or r
    }
    final rows = <List<String>>[[]];
    while (true) {
      final cell = parseUntil(const {'&', r'\\', r'\end', r'\cr'});
      rows.last.add(_row(cell));
      final token = next();
      if (token == '&') continue;
      if (token == r'\\' || token == r'\cr') {
        _optional(); // \\[2pt]
        rows.add([]);
        continue;
      }
      if (token == r'\end') _rawArgument();
      break;
    }
    if (rows.length > 1 &&
        rows.last.length == 1 &&
        rows.last.single == '<mrow></mrow>') {
      rows.removeLast();
    }
    final align = switch (bare) {
      'cases' || 'dcases' || 'rcases' => 'left left',
      'aligned' ||
      'align' ||
      'alignat' ||
      'alignedat' ||
      'split' ||
      'eqnarray' => 'right left',
      // array's columns, or a starred matrix's alignment.
      _ when columns != null => [
        for (final c in columns.split(''))
          if (c == 'l')
            'left'
          else if (c == 'r')
            'right'
          else if (c == 'c')
            'center',
      ].join(' '),
      _ => null,
    };
    final display = switch (bare) {
      'aligned' ||
      'align' ||
      'alignat' ||
      'alignedat' ||
      'gathered' ||
      'gather' ||
      'split' ||
      'eqnarray' ||
      'multline' ||
      'dcases' => true,
      _ => false,
    };
    final alignAttr = align == null || align.isEmpty
        ? ''
        : ' columnalign="$align"';
    final body = [
      for (final row in rows)
        '<mtr>${[for (final cell in row) '<mtd>$cell</mtd>'].join()}</mtr>',
    ].join();
    final table = '<mtable$alignAttr>$body</mtable>';
    final styled = display
        ? '<mstyle displaystyle="true">$table</mstyle>'
        : table;
    final (open, close) = switch (bare) {
      'pmatrix' => ('(', ')'),
      'bmatrix' => ('[', ']'),
      'Bmatrix' => ('{', '}'),
      'vmatrix' => ('|', '|'),
      'Vmatrix' => ('\u2016', '\u2016'),
      'cases' || 'dcases' => ('{', ''),
      'rcases' => ('', '}'),
      _ => ('', ''),
    };
    if (open.isEmpty && close.isEmpty) return _Node(styled);
    const stretchy = 'fence="true" stretchy="true"';
    final before = open.isEmpty ? '' : '<mo $stretchy>$open</mo>';
    final after = close.isEmpty
        ? ''
        : '<mo $stretchy form="postfix">$close</mo>';
    return _Node('<mrow>$before$styled$after</mrow>');
  }
}

enum _Kind { identifier, upright, operator, open, close }

/// The index of the `$` that closes math opened before [from] in [text]
/// (one in braces or after a backslash doesn't), or the text's end.
int _closingDollar(String text, int from) {
  var depth = 0;
  for (var j = from; j < text.length; j++) {
    switch (text[j]) {
      case r'\':
        j++;
      case '{':
        depth++;
      case '}':
        depth--;
      case r'$' when depth == 0:
        return j;
    }
  }
  return text.length;
}

/// Text mode's accent commands: the combining mark each puts on the
/// character after it.
const Map<String, String> _textAccents = {
  "'": '\u0301',
  '`': '\u0300',
  '"': '\u0308',
  '^': '\u0302',
  '~': '\u0303',
  '=': '\u0304',
  '.': '\u0307',
  'u': '\u0306',
  'v': '\u030c',
  'H': '\u030b',
  'r': '\u030a',
  'c': '\u0327',
};

/// Text mode's symbol commands.
const Map<String, String> _textSymbols = {
  'i': '\u0131',
  'j': '\u0237',
  'TeX': 'TeX',
  'LaTeX': 'LaTeX',
  'ldots': '\u2026',
  'dots': '\u2026',
  'textendash': '\u2013',
  'textemdash': '\u2014',
  'textbackslash': r'\',
  'ss': '\u00df',
  'ae': '\u00e6',
  'AE': '\u00c6',
  'o': '\u00f8',
  'O': '\u00d8',
  'aa': '\u00e5',
  'AA': '\u00c5',
  'l': '\u0142',
  'L': '\u0141',
};

/// Text mode's style commands, whose argument is read as text (their
/// style aside).
const Set<String> _textStyles = {
  'text',
  'textrm',
  'textnormal',
  'textbf',
  'textit',
  'textsf',
  'texttt',
  'textup',
  'emph',
  'mbox',
  'hbox',
};

/// TeX's text ligatures, longest first.
const Map<String, String> _textLigatures = {
  '---': '\u2014',
  '--': '\u2013',
  '``': '\u201c',
  "''": '\u201d',
  '`': '\u2018',
  "'": '\u2019',
};

/// The environments read (`*` forms too).
const Set<String> _environments = {
  'matrix',
  'pmatrix',
  'bmatrix',
  'Bmatrix',
  'vmatrix',
  'Vmatrix',
  'smallmatrix',
  'cases',
  'dcases',
  'rcases',
  'array',
  'subarray',
  'aligned',
  'align',
  'alignat',
  'alignedat',
  'gathered',
  'gather',
  'split',
  'eqnarray',
  'multline',
  'equation',
};

const Map<String, (String, _Kind)> _symbols = {
  // Greek.
  'alpha': ('\u03b1', _Kind.identifier),
  'beta': ('\u03b2', _Kind.identifier),
  'gamma': ('\u03b3', _Kind.identifier),
  'delta': ('\u03b4', _Kind.identifier),
  'epsilon': ('\u03f5', _Kind.identifier),
  'varepsilon': ('\u03b5', _Kind.identifier),
  'zeta': ('\u03b6', _Kind.identifier),
  'eta': ('\u03b7', _Kind.identifier),
  'theta': ('\u03b8', _Kind.identifier),
  'vartheta': ('\u03d1', _Kind.identifier),
  'iota': ('\u03b9', _Kind.identifier),
  'kappa': ('\u03ba', _Kind.identifier),
  'lambda': ('\u03bb', _Kind.identifier),
  'mu': ('\u03bc', _Kind.identifier),
  'nu': ('\u03bd', _Kind.identifier),
  'xi': ('\u03be', _Kind.identifier),
  'omicron': ('\u03bf', _Kind.identifier),
  'pi': ('\u03c0', _Kind.identifier),
  'varpi': ('\u03d6', _Kind.identifier),
  'rho': ('\u03c1', _Kind.identifier),
  'varrho': ('\u03f1', _Kind.identifier),
  'sigma': ('\u03c3', _Kind.identifier),
  'varsigma': ('\u03c2', _Kind.identifier),
  'tau': ('\u03c4', _Kind.identifier),
  'upsilon': ('\u03c5', _Kind.identifier),
  'phi': ('\u03d5', _Kind.identifier),
  'varphi': ('\u03c6', _Kind.identifier),
  'chi': ('\u03c7', _Kind.identifier),
  'psi': ('\u03c8', _Kind.identifier),
  'omega': ('\u03c9', _Kind.identifier),
  'Gamma': ('\u0393', _Kind.upright),
  'Delta': ('\u0394', _Kind.upright),
  'Theta': ('\u0398', _Kind.upright),
  'Lambda': ('\u039b', _Kind.upright),
  'Xi': ('\u039e', _Kind.upright),
  'Pi': ('\u03a0', _Kind.upright),
  'Sigma': ('\u03a3', _Kind.upright),
  'Upsilon': ('\u03a5', _Kind.upright),
  'Phi': ('\u03a6', _Kind.upright),
  'Psi': ('\u03a8', _Kind.upright),
  'Omega': ('\u03a9', _Kind.upright),
  // Letter-like.
  'infty': ('\u221e', _Kind.upright),
  'partial': ('\u2202', _Kind.upright),
  'nabla': ('\u2207', _Kind.upright),
  'hbar': ('\u210f', _Kind.identifier),
  'ell': ('\u2113', _Kind.identifier),
  'imath': ('\u0131', _Kind.identifier),
  'jmath': ('\u0237', _Kind.identifier),
  'Re': ('\u211c', _Kind.upright),
  'Im': ('\u2111', _Kind.upright),
  'aleph': ('\u2135', _Kind.upright),
  'wp': ('\u2118', _Kind.upright),
  'emptyset': ('\u2205', _Kind.upright),
  'varnothing': ('\u2205', _Kind.upright),
  'forall': ('\u2200', _Kind.operator),
  'exists': ('\u2203', _Kind.operator),
  'nexists': ('\u2204', _Kind.operator),
  'neg': ('\u00ac', _Kind.operator),
  'lnot': ('\u00ac', _Kind.operator),
  'top': ('\u22a4', _Kind.upright),
  'bot': ('\u22a5', _Kind.upright),
  'angle': ('\u2220', _Kind.upright),
  'triangle': ('\u25b3', _Kind.upright),
  'prime': ('\u2032', _Kind.operator),
  'degree': ('\u00b0', _Kind.upright),
  'dagger': ('\u2020', _Kind.operator),
  'ddagger': ('\u2021', _Kind.operator),
  'dots': ('\u2026', _Kind.operator),
  'ldots': ('\u2026', _Kind.operator),
  'cdots': ('\u22ef', _Kind.operator),
  'vdots': ('\u22ee', _Kind.operator),
  'ddots': ('\u22f1', _Kind.operator),
  // Binary operators.
  'pm': ('\u00b1', _Kind.operator),
  'mp': ('\u2213', _Kind.operator),
  'times': ('\u00d7', _Kind.operator),
  'div': ('\u00f7', _Kind.operator),
  'cdot': ('\u22c5', _Kind.operator),
  'ast': ('\u2217', _Kind.operator),
  'star': ('\u22c6', _Kind.operator),
  'circ': ('\u2218', _Kind.operator),
  'bullet': ('\u2219', _Kind.operator),
  'cap': ('\u2229', _Kind.operator),
  'cup': ('\u222a', _Kind.operator),
  'wedge': ('\u2227', _Kind.operator),
  'land': ('\u2227', _Kind.operator),
  'vee': ('\u2228', _Kind.operator),
  'lor': ('\u2228', _Kind.operator),
  'oplus': ('\u2295', _Kind.operator),
  'ominus': ('\u2296', _Kind.operator),
  'otimes': ('\u2297', _Kind.operator),
  'odot': ('\u2299', _Kind.operator),
  'setminus': ('\u2216', _Kind.operator),
  'backslash': (r'\', _Kind.operator),
  'uplus': ('\u228e', _Kind.operator),
  'sqcup': ('\u2294', _Kind.operator),
  'sqcap': ('\u2293', _Kind.operator),
  'wr': ('\u2240', _Kind.operator),
  'diamond': ('\u22c4', _Kind.operator),
  // Relations.
  'leq': ('\u2264', _Kind.operator),
  'le': ('\u2264', _Kind.operator),
  'geq': ('\u2265', _Kind.operator),
  'ge': ('\u2265', _Kind.operator),
  'neq': ('\u2260', _Kind.operator),
  'ne': ('\u2260', _Kind.operator),
  'leqslant': ('\u2a7d', _Kind.operator),
  'geqslant': ('\u2a7e', _Kind.operator),
  'll': ('\u226a', _Kind.operator),
  'gg': ('\u226b', _Kind.operator),
  'approx': ('\u2248', _Kind.operator),
  'equiv': ('\u2261', _Kind.operator),
  'sim': ('\u223c', _Kind.operator),
  'simeq': ('\u2243', _Kind.operator),
  'cong': ('\u2245', _Kind.operator),
  'propto': ('\u221d', _Kind.operator),
  'in': ('\u2208', _Kind.operator),
  'notin': ('\u2209', _Kind.operator),
  'ni': ('\u220b', _Kind.operator),
  'subset': ('\u2282', _Kind.operator),
  'supset': ('\u2283', _Kind.operator),
  'subseteq': ('\u2286', _Kind.operator),
  'supseteq': ('\u2287', _Kind.operator),
  'subsetneq': ('\u228a', _Kind.operator),
  'supsetneq': ('\u228b', _Kind.operator),
  'prec': ('\u227a', _Kind.operator),
  'succ': ('\u227b', _Kind.operator),
  'preceq': ('\u2aaf', _Kind.operator),
  'succeq': ('\u2ab0', _Kind.operator),
  'perp': ('\u22a5', _Kind.operator),
  'parallel': ('\u2225', _Kind.operator),
  'mid': ('\u2223', _Kind.operator),
  'nmid': ('\u2224', _Kind.operator),
  'vdash': ('\u22a2', _Kind.operator),
  'dashv': ('\u22a3', _Kind.operator),
  'models': ('\u22a8', _Kind.operator),
  'doteq': ('\u2250', _Kind.operator),
  'asymp': ('\u224d', _Kind.operator),
  'colon': (':', _Kind.operator),
  'coloneqq': ('\u2254', _Kind.operator),
  // Arrows.
  'to': ('\u2192', _Kind.operator),
  'rightarrow': ('\u2192', _Kind.operator),
  'leftarrow': ('\u2190', _Kind.operator),
  'gets': ('\u2190', _Kind.operator),
  'leftrightarrow': ('\u2194', _Kind.operator),
  'Rightarrow': ('\u21d2', _Kind.operator),
  'Leftarrow': ('\u21d0', _Kind.operator),
  'Leftrightarrow': ('\u21d4', _Kind.operator),
  'implies': ('\u27f9', _Kind.operator),
  'impliedby': ('\u27f8', _Kind.operator),
  'iff': ('\u27fa', _Kind.operator),
  'longrightarrow': ('\u27f6', _Kind.operator),
  'longleftarrow': ('\u27f5', _Kind.operator),
  'Longrightarrow': ('\u27f9', _Kind.operator),
  'Longleftarrow': ('\u27f8', _Kind.operator),
  'longleftrightarrow': ('\u27f7', _Kind.operator),
  'Longleftrightarrow': ('\u27fa', _Kind.operator),
  'mapsto': ('\u21a6', _Kind.operator),
  'longmapsto': ('\u27fc', _Kind.operator),
  'uparrow': ('\u2191', _Kind.operator),
  'downarrow': ('\u2193', _Kind.operator),
  'updownarrow': ('\u2195', _Kind.operator),
  'Uparrow': ('\u21d1', _Kind.operator),
  'Downarrow': ('\u21d3', _Kind.operator),
  'nearrow': ('\u2197', _Kind.operator),
  'searrow': ('\u2198', _Kind.operator),
  'nwarrow': ('\u2196', _Kind.operator),
  'swarrow': ('\u2199', _Kind.operator),
  'hookrightarrow': ('\u21aa', _Kind.operator),
  'hookleftarrow': ('\u21a9', _Kind.operator),
  'rightleftharpoons': ('\u21cc', _Kind.operator),
  // Delimiters.
  'langle': ('\u27e8', _Kind.open),
  'rangle': ('\u27e9', _Kind.close),
  'lfloor': ('\u230a', _Kind.open),
  'rfloor': ('\u230b', _Kind.close),
  'lceil': ('\u2308', _Kind.open),
  'rceil': ('\u2309', _Kind.close),
  'lbrace': ('{', _Kind.open),
  'rbrace': ('}', _Kind.close),
  'lvert': ('|', _Kind.open),
  'rvert': ('|', _Kind.close),
  'vert': ('|', _Kind.operator),
  'lVert': ('\u2016', _Kind.open),
  'rVert': ('\u2016', _Kind.close),
  'Vert': ('\u2016', _Kind.operator),
};

const Set<String> _functions = {
  'sin',
  'cos',
  'tan',
  'cot',
  'sec',
  'csc',
  'arcsin',
  'arccos',
  'arctan',
  'sinh',
  'cosh',
  'tanh',
  'coth',
  'log',
  'ln',
  'lg',
  'exp',
  'dim',
  'ker',
  'deg',
  'arg',
  'hom',
};

const Map<String, String> _limitFunctions = {
  'lim': 'lim',
  'liminf': 'lim inf',
  'limsup': 'lim sup',
  'max': 'max',
  'min': 'min',
  'sup': 'sup',
  'inf': 'inf',
  'det': 'det',
  'gcd': 'gcd',
  'Pr': 'Pr',
  'argmax': 'arg max',
  'argmin': 'arg min',
};

const Map<String, String> _largeOperators = {
  'sum': '\u2211',
  'prod': '\u220f',
  'coprod': '\u2210',
  'int': '\u222b',
  'iint': '\u222c',
  'iiint': '\u222d',
  'oint': '\u222e',
  'bigcup': '\u22c3',
  'bigcap': '\u22c2',
  'bigvee': '\u22c1',
  'bigwedge': '\u22c0',
  'bigoplus': '\u2a01',
  'bigotimes': '\u2a02',
  'bigodot': '\u2a00',
  'biguplus': '\u2a04',
  'bigsqcup': '\u2a06',
};

const Set<String> _integrals = {'int', 'iint', 'iiint', 'oint'};

const Map<String, String> _spaces = {
  ',': '0.1667em',
  'thinspace': '0.1667em',
  ':': '0.2222em',
  '>': '0.2222em',
  'medspace': '0.2222em',
  ';': '0.2778em',
  'thickspace': '0.2778em',
  '!': '-0.1667em',
  'negthinspace': '-0.1667em',
  ' ': '0.333em',
  'quad': '1em',
  'qquad': '2em',
  'enspace': '0.5em',
};

const Map<String, String> _variants = {
  'mathrm': 'normal',
  'mathup': 'normal',
  'mathbf': 'bold',
  'mathit': 'italic',
  'boldsymbol': 'bold-italic',
  'bm': 'bold-italic',
  'mathbb': 'double-struck',
  'mathcal': 'script',
  'mathscr': 'script',
  'mathfrak': 'fraktur',
  'mathsf': 'sans-serif',
  'mathtt': 'monospace',
  'textbf': 'bold',
  'textit': 'italic',
  'textsf': 'sans-serif',
  'texttt': 'monospace',
};

/// Accents: the character, and whether it goes over.
const Map<String, (String, bool)> _accents = {
  'hat': ('^', true),
  'widehat': ('^', true),
  'check': ('\u02c7', true),
  'tilde': ('~', true),
  'widetilde': ('~', true),
  'acute': ('\u00b4', true),
  'grave': ('`', true),
  'dot': ('\u02d9', true),
  'ddot': ('\u00a8', true),
  'breve': ('\u02d8', true),
  'bar': ('\u00af', true),
  'overline': ('\u00af', true),
  'vec': ('\u2192', true),
  'overrightarrow': ('\u2192', true),
  'overleftarrow': ('\u2190', true),
  'overleftrightarrow': ('\u2194', true),
  'underline': ('_', false),
  'underrightarrow': ('\u2192', false),
  'underleftarrow': ('\u2190', false),
};

/// The negated forms of relations (`\not`).
const Map<String, String> _negations = {
  '=': '\u2260',
  '\u2208': '\u2209',
  '<': '\u226e',
  '>': '\u226f',
  '\u2264': '\u2270',
  '\u2265': '\u2271',
  '\u2261': '\u2262',
  '\u223c': '\u2241',
  '\u2248': '\u2249',
  '\u2282': '\u2284',
  '\u2283': '\u2285',
  '\u2286': '\u2288',
  '\u2287': '\u2289',
  '\u2223': '\u2224',
  '\u2225': '\u2226',
};
