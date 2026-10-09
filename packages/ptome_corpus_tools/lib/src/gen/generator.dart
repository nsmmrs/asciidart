/// Random documents: weighted construction over the model, with knobs for
/// pathological input (colliding marks, mismatched delimiters, odd
/// whitespace and scripts, boundary values).
///
/// `(generatorVersion, seed)` reproduces a document exactly.
library;

import 'model.dart';
import 'rng.dart';

/// Bumped whenever the same seed would produce a different document.
const generatorVersion = 1;

/// How big and how strange generated documents get.
final class GenConfig {
  const GenConfig({
    this.maxBlocks = 24,
    this.maxDepth = 4,
    this.pathology = 0.08,
    this.header = 0.6,
  });

  /// Upper bound on blocks in the whole document.
  final int maxBlocks;
  final int maxDepth;

  /// Probability of a pathological choice wherever one is possible.
  final double pathology;

  /// Probability of a document header.
  final double header;
}

/// A generated document with what the generator knows about it.
final class Generated {
  Generated(
    this.doc,
    this.seed,
    this.words,
    this.options, {
    this.pathological = false,
  });

  final Doc doc;
  final int seed;

  /// The unique prose words emitted where they should reach the output.
  final Set<String> words;

  /// API options for converting it: doctype, attributes.
  final GenOptions options;

  /// Whether any pathological choice was made (words may then legitimately
  /// vanish: a stray delimiter can comment out the rest).
  final bool pathological;

  /// Whether every tracked word must reach the html5 output.
  bool get contentChecked =>
      !pathological &&
      (options.doctype == null || options.doctype == 'book') &&
      !options.attributes.containsKey('attribute-missing');
}

final class GenOptions {
  GenOptions({
    this.doctype,
    Map<String, String>? attributes,
    this.standalone = false,
  }) : attributes = attributes ?? {};

  String? doctype;
  final Map<String, String> attributes;
  bool standalone;
}

Generated generate(int seed, {GenConfig config = const GenConfig()}) =>
    _Generator(Rng(seed), config).document(seed);

final class _Generator {
  _Generator(this.rng, this.config);

  final Rng rng;
  final GenConfig config;
  final Set<String> words = {};
  final List<String> ids = [];
  final Set<String> definedAttributes = {};
  int blocks = 0;
  int sectionLevel = 0;
  bool suppressWords = false;

  bool pathological = false;

  bool get weird {
    final w = rng.chance(config.pathology);
    if (w) pathological = true;
    return w;
  }

  Generated document(int seed) {
    final options = GenOptions();
    final doc = Doc();
    final doctype = rng.weighted({
      'article': 10,
      'book': 3,
      'manpage': 1,
      'inline': 1,
    });
    if (doctype != 'article') options.doctype = doctype;
    options.standalone = rng.chance(0.2);
    if (weird) doc.lineEnding = '\r\n';
    if (weird) doc.bom = true;
    for (final (name, value) in [
      if (rng.chance(0.15)) ('experimental', ''),
      if (rng.chance(0.1)) ('sectnums', ''),
      if (rng.chance(0.1)) ('icons', rng.pick(['font', 'image', ''])),
      if (rng.chance(0.08)) ('idprefix', rng.pick(['', 'x_', '-'])),
      if (rng.chance(0.08)) ('idseparator', rng.pick(['-', '', '.', '__'])),
      if (rng.chance(0.05))
        ('attribute-missing', rng.pick(['skip', 'drop', 'drop-line', 'warn'])),
      if (rng.chance(0.05)) ('hardbreaks-option', ''),
      if (rng.chance(0.05)) ('compat-mode', ''),
      if (rng.chance(0.05))
        ('source-highlighter', rng.pick(['highlight.js', 'prettify'])),
    ]) {
      options.attributes[name] = value;
    }
    if (doctype == 'manpage') {
      doc.header = Header(
        title: [Text('${_identifier()}(${rng.between(1, 8)})')],
      );
      doc.blocks.addAll([
        Section(
          level: 1,
          title: [Text('NAME')],
          blocks: [
            Paragraph([
              [Text('${_identifier()} - '), ..._inlines(6)],
            ]),
          ],
        ),
        Section(
          level: 1,
          title: [Text('SYNOPSIS')],
          blocks: [
            Paragraph([_inlines(5)]),
          ],
        ),
        Section(
          level: 1,
          title: [Text('DESCRIPTION')],
          blocks: _blocks(rng.between(1, 6), 1),
        ),
      ]);
      return Generated(doc, seed, words, options, pathological: pathological);
    }
    if (rng.chance(config.header)) {
      // Embedded output leaves the document title out (unless showtitle).
      final saved = suppressWords;
      suppressWords = !options.standalone;
      doc.header = _header();
      suppressWords = saved;
    }
    if (doctype == 'book') sectionLevel = -1;
    doc.blocks.addAll(
      _sectionBody(rng.between(1, config.maxBlocks), 0, top: true),
    );
    return Generated(doc, seed, words, options, pathological: pathological);
  }

  Header _header() {
    final header = Header(title: _inlines(rng.between(1, 6)));
    if (rng.chance(0.5)) {
      header.authors = [
        for (var i = rng.between(1, 3); i > 0; i--)
          '${_name()} ${_name()}${rng.chance(0.5) ? ' <${_identifier()}@example.org>' : ''}',
      ];
      if (rng.chance(0.4)) {
        header.revision =
            'v${rng.between(0, 9)}.${rng.between(0, 20)}'
            '${rng.chance(0.6) ? ', 2025-0${rng.between(1, 9)}-1${rng.between(0, 9)}' : ''}'
            '${rng.chance(0.4) ? ': ${_plain(3)}' : ''}';
      }
    }
    for (var i = rng.count(mean: 1.5, max: 8); i > 0; i--) {
      header.attributes.add(_attributeEntry());
    }
    if (rng.chance(0.25))
      header.attributes.add(
        AttributeEntry(
          'toc',
          rng.pick(['', 'left', 'right', 'preamble', 'macro']),
        ),
      );
    return header;
  }

  List<Block> _sectionBody(int count, int depth, {bool top = false}) {
    final out = <Block>[];
    while (out.length < count && blocks < config.maxBlocks) {
      if (depth < config.maxDepth && rng.chance(top ? 0.3 : 0.15)) {
        out.add(_section(depth));
      } else {
        out.add(_block(depth));
      }
    }
    return out;
  }

  Section _section(int depth) {
    blocks++;
    // Levels mostly step by one; sometimes they skip (out of sequence).
    var level = sectionLevel + 1;
    if (weird) level += rng.between(1, 3);
    if (level < 0) level = 0;
    if (level > 5) level = 5;
    final saved = sectionLevel;
    sectionLevel = level;
    final title = _inlines(rng.between(1, 5));
    final section = Section(
      level: level == 0 ? 1 : level,
      title: title,
      discrete: rng.chance(0.05),
      markdown: rng.chance(0.05),
    );
    if (rng.chance(0.3)) section.meta.id = _newId();
    if (rng.chance(0.08)) {
      section.meta.style = rng.pick([
        'appendix',
        'glossary',
        'bibliography',
        'index',
        'abstract',
        'preface',
        'colophon',
        'dedication',
        'partintro',
      ]);
    }
    final savedWords = suppressWords;
    if (section.meta.style == 'index') suppressWords = true;
    section.blocks.addAll(_sectionBody(rng.between(0, 5), depth + 1));
    suppressWords = savedWords;
    sectionLevel = saved;
    return section;
  }

  List<Block> _blocks(int count, int depth) => [
    for (var i = 0; i < count && blocks < config.maxBlocks; i++) _block(depth),
  ];

  Block _block(int depth) {
    blocks++;
    final kind = rng.weighted({
      'paragraph': 30,
      'list': 12,
      'delimited': 12,
      'table': 7,
      'admonition': 5,
      'attribute': 4,
      'conditional': 3,
      'macro': 3,
      'literal': 3,
      'comment': 2,
      'break': 1,
      'include': 1,
      'raw': 2,
    });
    final block = switch (kind) {
      'paragraph' => _paragraph(),
      'list' => _list(1, depth),
      'delimited' => _delimited(depth),
      'table' => _table(depth),
      'admonition' => _admonition(depth),
      'attribute' => _attributeEntry(),
      'conditional' => _conditional(depth),
      'macro' => _blockMacro(),
      'literal' => Paragraph([
        [Text(_plainUntracked(4))],
      ], indent: rng.between(1, 4)),
      'comment' => CommentLine(' ${_plainUntracked(3)}'),
      'break' => Break(page: rng.chance(0.5)),
      'include' => Include(
        rng.pick(['missing.adoc', '{nope}/x.adoc', 'missing.adoc']),
        attributes: rng.pick([
          '',
          'tags=a',
          'lines=1..2',
          'leveloffset=+1',
          'opts=optional',
        ]),
      ),
      _ => () {
        pathological = true;
        return Raw([_pathologicalLine()]);
      }(),
    };
    if (block is! AttributeEntry &&
        block is! Conditional &&
        block is! CommentLine &&
        block is! Raw &&
        block is! Include) {
      _decorate(block.meta);
    }
    return block;
  }

  void _decorate(Meta meta) {
    if (rng.chance(0.12)) meta.title = _inlines(rng.between(1, 4));
    if (rng.chance(0.1)) meta.id = _newId();
    if (rng.chance(0.08)) meta.roles = [_identifier()];
    if (rng.chance(0.03)) meta.reftext = _plainUntracked(2);
  }

  Paragraph _paragraph() => Paragraph([
    for (var i = rng.between(1, 4); i > 0; i--) _inlines(rng.between(1, 12)),
  ]);

  ListBlock _list(int depth, int blockDepth) {
    final kind = rng.weighted({
      ListKind.unordered: 5,
      ListKind.ordered: 4,
      ListKind.description: 3,
      ListKind.checklist: 1,
      ListKind.qanda: 1,
      ListKind.horizontal: 1,
    });
    final list = ListBlock(
      kind == ListKind.checklist ? ListKind.checklist : kind,
      [],
      depth: depth,
      separator: switch (kind) {
        ListKind.description => rng.pick(['::', ':::', '::::', ';;']),
        _ => '::',
      },
    );
    if (kind == ListKind.qanda) list.meta.style = 'qanda';
    if (kind == ListKind.horizontal) list.meta.style = 'horizontal';
    if (kind == ListKind.ordered && rng.chance(0.2))
      list.meta.named = {'start': '${rng.between(-2, 20)}'};
    if (kind == ListKind.ordered && rng.chance(0.1))
      list.meta.style = rng.pick([
        'loweralpha',
        'upperroman',
        'arabic',
        'lowergreek',
      ]);
    for (var i = rng.between(1, 5); i > 0; i--) {
      final item = ListItem(
        _inlines(rng.between(0, 8)),
        term:
            list.kind == ListKind.description ||
                list.kind == ListKind.qanda ||
                list.kind == ListKind.horizontal
            ? _inlines(rng.between(1, 3))
            : null,
        checked: list.kind == ListKind.checklist ? rng.chance(0.5) : null,
      );
      if (kind == ListKind.ordered && rng.chance(0.15)) {
        item.marker = rng.pick(['1.', '7.', 'a.', 'B.', 'iv)', 'X)']);
      }
      if (blockDepth < config.maxDepth && rng.chance(0.15)) {
        item.attached.add(
          rng.chance(0.5) ? _paragraph() : _delimited(blockDepth + 1),
        );
      }
      if (depth < 6 && blockDepth < config.maxDepth && rng.chance(0.2)) {
        item.nested.add(_list(depth + 1, blockDepth + 1));
      }
      list.items.add(item);
    }
    return list;
  }

  Block _delimited(int depth) {
    final kind = rng.weighted({
      BlockKind.listing: 4,
      BlockKind.literal: 2,
      BlockKind.example: 3,
      BlockKind.sidebar: 2,
      BlockKind.quote: 2,
      BlockKind.open: 2,
      BlockKind.passthrough: 1,
      BlockKind.comment: 1,
      BlockKind.fenced: 1,
    });
    final block = Delimited(
      kind,
      length: switch (kind) {
        BlockKind.open => 2,
        BlockKind.fenced => 3,
        _ => weird ? rng.between(4, 9) : 4,
      },
    );
    if (weird && kind != BlockKind.open && kind != BlockKind.fenced)
      block.closeLength = block.length + 1;
    if (rng.chance(config.pathology / 4)) block.unterminated = true;
    if (kind.verbatim) {
      block.lines = _verbatimLines(kind);
      if (kind == BlockKind.listing && rng.chance(0.4)) {
        block.meta.style = 'source';
        block.meta.named = {};
        final language = rng.pick([
          'ruby',
          'java',
          'python',
          'js',
          'c',
          'text',
          'xml',
        ]);
        block.meta.style = 'source,$language';
      }
    } else {
      if (kind == BlockKind.quote && rng.chance(0.4)) {
        block.meta.style =
            '${rng.pick(['quote', 'verse'])},${_plain(2)},${_plain(2)}';
      }
      if (kind == BlockKind.open && rng.chance(0.2)) {
        block.meta.style = rng.pick([
          'abstract',
          'partintro',
          'source',
          'sidebar',
          'example',
          'quote',
          'comment',
          'pass',
        ]);
      }
      if (depth < config.maxDepth) {
        final saved = suppressWords;
        if (block.meta.style == 'comment') suppressWords = true;
        block.blocks.addAll(_blocks(rng.between(0, 3), depth + 1));
        suppressWords = saved;
      }
    }
    return block;
  }

  List<String> _verbatimLines(BlockKind kind) {
    final lines = <String>[];
    for (var i = rng.between(0, 6); i > 0; i--) {
      final line = StringBuffer(_plainUntracked(rng.between(1, 6)));
      if (rng.chance(0.15)) line.write(' <${rng.between(1, 4)}>');
      if (weird)
        line.write(
          rng.pick([
            '\t',
            '  ',
            ' \\',
            ' +',
            '{nope}',
            '<b>&amp;</b>',
            '`x`',
            '*y*',
          ]),
        );
      lines.add(
        kind == BlockKind.passthrough
            ? '<p>${line.toString()}</p>'
            : line.toString(),
      );
    }
    return lines;
  }

  Table _table(int depth) {
    final format = rng.weighted({
      TableFormat.psv: 8,
      TableFormat.csv: 2,
      TableFormat.dsv: 1,
    });
    final columns = rng.between(1, weird ? 12 : 4);
    final table = Table([], format: format, nested: false);
    if (rng.chance(0.5)) {
      table.cols = weird
          ? rng.pick([
              '0',
              '$columns*',
              '${columns + 1}',
              '1,,2',
              '~,~',
              '3*^.^',
              'a,e,h',
              '${columns}*<m',
              '',
            ])
          : [
              for (var c = 0; c < columns; c++)
                rng.pick([
                  '1',
                  '2',
                  '<',
                  '^',
                  '>',
                  'a',
                  'm',
                  's',
                  'h',
                  'e',
                  'l',
                  '~',
                  '25%',
                ]),
            ].join(',');
    }
    table.header = rng.chance(0.4);
    table.footer = rng.chance(0.1);
    final options = [
      if (table.header && rng.chance(0.5)) 'header',
      if (table.footer) 'footer',
      if (rng.chance(0.1)) 'autowidth',
      if (rng.chance(0.05)) 'noheader',
    ];
    table.meta.options = options;
    if (table.cols != null) table.meta.named = {'cols': table.cols!};
    if (rng.chance(0.1))
      table.meta.named = {
        ...table.meta.named,
        'frame': rng.pick(['all', 'ends', 'sides', 'none']),
        'grid': rng.pick(['all', 'rows', 'cols', 'none']),
      };
    if (format != TableFormat.psv)
      table.meta.named = {...table.meta.named, 'format': format.name};
    for (var r = rng.between(1, 5); r > 0; r--) {
      final row = <Cell>[];
      for (var c = 0; c < columns; c++) {
        final spec = weird
            ? rng.pick([
                '2+',
                '.2+',
                '2.2+',
                '${columns + 2}+',
                '3*',
                '^.^',
                '>s',
                'h',
                'e',
                'l',
                'm',
                '0+',
              ])
            : rng.chance(0.1)
            ? rng.pick(['2+', '.2+', '^', '>', 'h', 's', 'e'])
            : '';
        if (format == TableFormat.psv &&
            depth < config.maxDepth &&
            rng.chance(0.06)) {
          row.add(
            Cell(
              const [],
              spec: spec,
              blocks: _blocks(rng.between(1, 2), depth + 1),
            ),
          );
        } else {
          row.add(
            Cell(
              _inlines(rng.between(0, 4)),
              spec: format == TableFormat.psv ? spec : '',
            ),
          );
        }
      }
      table.rows.add(row);
    }
    return table;
  }

  Admonition _admonition(int depth) {
    final kind = rng.pick(AdmonitionKind.values);
    return Admonition(
      kind,
      rng.chance(0.7) ? _paragraph() : _delimited(depth + 1),
    );
  }

  AttributeEntry _attributeEntry() {
    final name = rng.chance(0.3)
        ? rng.pick([
            'toc',
            'sectnums',
            'icons',
            'experimental',
            'idprefix',
            'idseparator',
            'hardbreaks-option',
            'linkattrs',
            'showtitle',
            'notitle',
            'nofooter',
            'sectanchors',
            'sectlinks',
            'table-caption',
            'figure-caption',
            'example-caption',
            'xrefstyle',
            'leveloffset',
            'imagesdir',
            'source-highlighter',
            'stem',
          ])
        : _identifier();
    definedAttributes.add(name);
    if (rng.chance(0.1)) return AttributeEntry(name, '', unset: true);
    final value = switch (name) {
      'xrefstyle' => rng.pick(['full', 'short', 'basic', 'bogus']),
      'leveloffset' => rng.pick(['+1', '-1', '0', '7', 'x']),
      'stem' => rng.pick(['', 'latexmath', 'asciimath']),
      _ => rng.chance(0.3) ? '' : _plainUntracked(rng.between(1, 3)),
    };
    return AttributeEntry(
      name,
      weird ? '$value {${rng.chance(0.5) ? name : _identifier()}}' : value,
      continuation: rng.chance(0.05) ? [_plainUntracked(2)] : const [],
    );
  }

  Conditional _conditional(int depth) {
    final directive = rng.pick(['ifdef', 'ifndef', 'ifeval']);
    final expression = switch (directive) {
      'ifeval' => rng.pick([
        '{x} > 1',
        '"{backend}" == "html5"',
        '1 == 1',
        '{nope} == ""',
        "'a' < 'b'",
        '2.0 >= 1',
        'bogus',
      ]),
      _ => [
        for (var i = rng.between(1, 2); i > 0; i--)
          definedAttributes.isNotEmpty && rng.chance(0.5)
              ? rng.pick(definedAttributes.toList())
              : rng.pick([
                  'backend-html5',
                  'doctype-book',
                  'nope',
                  'env',
                  'basebackend-docbook',
                ]),
      ].join(rng.pick([',', '+'])),
    };
    if (directive != 'ifeval' && rng.chance(0.2)) {
      return Conditional(directive, expression, singleLine: _plainUntracked(3));
    }
    final saved = suppressWords;
    suppressWords = true; // the body may be left out
    final body = depth < config.maxDepth
        ? _blocks(rng.between(1, 2), depth + 1)
        : <Block>[];
    suppressWords = saved;
    return Conditional(directive, expression, blocks: body);
  }

  BlockMacro _blockMacro() => switch (rng.pick([
    'image',
    'image',
    'video',
    'audio',
    'toc',
  ])) {
    'image' => BlockMacro(
      'image',
      rng.pick(['a.png', 'b.svg', 'https://example.org/c.jpg', '']),
      attributes: [
        if (rng.chance(0.5)) _plain(2),
        if (rng.chance(0.3)) '${rng.between(1, 400)}',
        if (rng.chance(0.2)) 'link=https://example.org',
        if (rng.chance(0.1)) 'opts=inline',
        if (rng.chance(0.1)) 'align=${rng.pick(['left', 'center', 'right'])}',
      ].join(','),
    ),
    'video' => BlockMacro(
      'video',
      rng.pick(['v.mp4', 'abcdef', '12345']),
      attributes: rng.pick(['', 'youtube', 'vimeo', 'wistia', 'opts=autoplay']),
    ),
    'audio' => BlockMacro(
      'audio',
      'a.mp3',
      attributes: rng.pick(['', 'opts=loop']),
    ),
    _ => BlockMacro('toc', ''),
  };

  String _pathologicalLine() => rng.pick([
    '|===',
    '----',
    '....',
    '====',
    '++++',
    '////',
    '****',
    '____',
    '--',
    '+',
    '[]',
    '[[]]',
    '[#]',
    '[.]',
    ':',
    '::',
    ':!:',
    '= ',
    '== ',
    '.',
    '. ',
    '* ',
    '<1>',
    "'''",
    '<<<',
    'include::[]',
    'ifdef::[]',
    'endif::[]',
    'endif::nope[]',
    'image::[]',
    r'\',
    '{',
    '}',
    '{{}}',
    '[source',
    'NOTE:',
    ' ',
    '​',
    '\t\t',
    '  +',
    '[quote,]',
    '[cols=]',
    '|',
    '!',
    'a|',
  ]);

  /// Inline content of about [n] words.
  List<Inline> _inlines(int n) {
    final out = <Inline>[];
    for (var i = 0; i < n; i++) {
      if (i > 0)
        out.add(Text(weird ? rng.pick([' ', '\t', '  ', ' ', ' ']) : ' '));
      out.add(_inline(0));
    }
    return out;
  }

  Inline _inline(int depth) {
    if (depth > 3) return Text(_word());
    final kind = rng.weighted({
      'word': 60,
      'formatted': 10,
      'symbol': 5,
      'passthrough': 2,
      'attribute': 3,
      'macro': 4,
      'xref': 2,
      'anchor': 1,
      'index': 1,
      'unicode': 2,
    });
    switch (kind) {
      case 'formatted':
        final mark = rng.pick(Mark.values);
        return Formatted(
          mark,
          [
            for (var i = rng.between(1, 3); i > 0; i--) ...[
              if (i > 0) Text(' '),
              _inline(depth + 1),
            ],
          ]..removeAt(0),
          constrained: !rng.chance(0.3),
          role: rng.chance(0.1) ? _identifier() : null,
          unbalanced: weird,
        );
      case 'symbol':
        return Symbol(
          rng.pick([
            '--',
            ' -- ',
            '...',
            '(C)',
            '(R)',
            '(TM)',
            '->',
            '=>',
            '<-',
            '<=',
            '&',
            '<',
            '>',
            '&amp;',
            '&#169;',
            r'\*',
            r'\_',
            r'\{x}',
            '"`',
            '`"',
            "'`",
            "`'",
            "'",
            " +",
            ' +\n',
            '’',
            '\\',
            '`',
            '#',
            '^',
            '~',
          ]),
        );
      case 'passthrough':
        return Passthrough(
          rng.pick(['+', '++', '+++', r'$$', 'pass', 'passq']),
          rng.pick(['<b>x</b>', '*y*', '{a}', 'z', '']),
        );
      case 'attribute':
        final defined = definedAttributes.isNotEmpty && rng.chance(0.6);
        return AttributeReference(
          defined
              ? rng.pick(definedAttributes.toList())
              : rng.pick([
                  'nope',
                  'backend',
                  'doctitle',
                  'counter:n',
                  'set:a:b',
                  'counter2:m',
                  'zwsp',
                  'nbsp',
                  'empty',
                  'sp',
                  'two-colons',
                ]),
          escaped: weird,
        );
      case 'macro':
        return switch (rng.pick([
          'link',
          'url',
          'footnote',
          'image',
          'kbd',
          'btn',
          'menu',
          'stem',
          'mailto',
          'icon',
          'indexterm',
          'anchor',
        ])) {
          'link' => Macro(
            'link',
            rng.pick(['https://example.org', 'other.html', '#frag', '']),
            rng.pick([_plain(2), '', '${_plain(1)},window=_blank', '^']),
          ),
          'url' => Macro(
            'https://',
            'example.org/${_identifier()}',
            rng.pick([_plain(1), '', 'role=x']),
          ),
          'footnote' => Macro(
            'footnote',
            rng.chance(0.3) ? _identifier() : '',
            _plain(rng.between(0, 4)),
          ),
          'image' => Macro(
            'image',
            rng.pick(['a.png', 'b.svg']),
            rng.pick(['', _plain(1), '16,16']),
          ),
          'kbd' => Macro(
            'kbd',
            '',
            rng.pick(['Ctrl+T', 'F11', 'Ctrl+Shift+N', ',', '+', '']),
          ),
          'btn' => Macro('btn', '', _plain(1)),
          'menu' => Macro('menu', _identifier(), '${_plain(1)} > ${_plain(1)}'),
          'stem' => Macro(
            'stem',
            '',
            rng.pick(['x^2', 'sqrt(4)', r'\alpha', ']', '']),
          ),
          'mailto' => Macro(
            'mailto',
            'a@example.org',
            rng.pick(['', _plain(1), '${_plain(1)},Subject']),
          ),
          'icon' => Macro(
            'icon',
            rng.pick(['heart', 'fire', '']),
            rng.pick(['', '2x', 'title=x']),
          ),
          'indexterm' => Macro(
            'indexterm',
            '',
            '${_plainUntracked(1)},${_plainUntracked(1)}',
          ),
          _ => Macro('anchor', _newId(), rng.pick(['', _plainUntracked(1)])),
        };
      case 'xref':
        final target = ids.isNotEmpty && rng.chance(0.7)
            ? rng.pick(ids)
            : rng.pick(['missing', 'other.adoc#x', 'other.adoc', '_x']);
        return Xref(
          target,
          text: rng.chance(0.4) ? _inlines(rng.between(1, 2)) : null,
        );
      case 'anchor':
        return InlineAnchor(
          _newId(),
          reftext: rng.chance(0.3) ? _plain(1) : null,
        );
      case 'index':
        return IndexTerm([
          _plain(1),
          if (rng.chance(0.5)) _plain(1),
        ], visible: rng.chance(0.5));
      case 'unicode':
        return Text(
          rng.pick([
            'naïve',
            'Straße',
            'İstanbul',
            'ﬁne',
            '日本語',
            'Ωμέγα',
            'Привет',
            'שלום',
            'مرحبا',
            'é',
            '👍🏽',
            'a‍b',
          ]),
        );
      default:
        return Text(_word());
    }
  }

  /// A unique prose word, recorded for the content oracle.
  String _word() {
    final w = _identifier(min: 4);
    if (!suppressWords) words.add(w);
    return w;
  }

  String _plain(int n) => [for (var i = 0; i < n; i++) _word()].join(' ');

  /// Words that are not tracked (their placement may hide them).
  String _plainUntracked(int n) =>
      [for (var i = 0; i < n; i++) _identifier()].join(' ');

  String _name() {
    final w = _identifier(min: 3);
    return '${w[0].toUpperCase()}${w.substring(1)}';
  }

  String _identifier({int min = 2}) {
    final length = rng.between(min, min + 6);
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.writeCharCode(0x61 + rng.below(26));
    }
    return buffer.toString();
  }

  String _newId() {
    final id = rng.chance(0.1) && ids.isNotEmpty
        ? rng.pick(ids)
        : '_${_identifier()}';
    ids.add(id);
    return id;
  }
}
