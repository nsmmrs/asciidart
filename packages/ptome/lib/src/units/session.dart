/// Units read natively (ADR-0020): ptome's parser reads a document in units
/// as it reads any other, recording where each text's lines were read; at
/// the end of the parse, the session walks the document's tree in document
/// order, finds the units syntax in the text the parser read (section
/// titles, paragraphs, list items, description-list entries, verse blocks,
/// table cells) and runs the units engine over it: units, addresses, IDs,
/// notes and references, before anything is converted.
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/block.dart';
import 'package:ptome/src/cursor.dart';
import 'package:ptome/src/document.dart' as ptome;
import 'package:ptome/src/list.dart';
import 'package:ptome/src/load.dart';
import 'package:ptome/src/logging.dart';
import 'package:ptome/src/options.dart';
import 'package:ptome/src/section.dart';
import 'package:ptome/src/table.dart';
import 'package:ptome/src/units/citation.dart';
import 'package:ptome/src/units/document.dart';
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/include.dart';
import 'package:ptome/src/units/process.dart'
    show findIgnoringPoints, headerAttributes, resolveUnit, schemesDir;
import 'package:ptome/src/units/render.dart';
import 'package:ptome/src/units/scheme.dart';

/// A document's units, as its parse finds them.
final class UnitsSession {
  new _(this._document, this.config, this.docfile, {required this.active})
    : _scanner = InlineScanner(config.ranges.keys.toSet(), active: active);

  /// A session for [document], which names no schemes or works, for the
  /// includes in units it has (a parallel text).
  factory forIncludes(ptome.Document document) => UnitsSession._(
    document,
    Config.empty(),
    document.attributes['docfile'] ?? p.join(document.baseDir, 'document.adoc'),
    active: false,
  );

  /// The session for [document], whose header has just been parsed: one
  /// when the header names schemes (`:units:`) or works (`:works:`), the
  /// safe mode allows reading files, and `units!` is not set; `null` for
  /// any other document, which then reads exactly as before.
  static UnitsSession? start(ptome.Document document) {
    final attrs = document.attributes;
    // Milestone 1 reads units by default until the native reading renders
    // them (ADR-0020, phase 3).
    if (attrs['units-engine'] != 'native') return null;
    if (document.safe >= SafeMode.secure) return null;
    final units = attrs['units'];
    if (units == null && attrs['works'] == null) return null;
    final docfile =
        attrs['docfile'] ?? p.join(document.baseDir, 'document.adoc');
    Config config;
    if (units == null) {
      config = Config.empty();
    } else {
      final dir = schemesDir(docfile);
      if (dir == null) {
        LoggerManager.logger.error(
          'units: no schemes/ directory above $docfile',
        );
        return null;
      }
      try {
        config = Config.load(
          units.split(RegExp(r'[\s,]+')).where((s) => s.isNotEmpty).toList(),
          dir,
        );
      } on Exception catch (e) {
        LoggerManager.logger.error('units: $e');
        return null;
      }
    }
    return UnitsSession._(document, config, docfile, active: units != null);
  }

  final ptome.Document _document;

  /// What the document's scheme files declare.
  final Config config;

  /// The path of the document (where `schemes/`, works and layers are found
  /// from).
  final String docfile;

  /// Whether the document names schemes (markers are units); a document
  /// that only names works reads its quotations and references.
  final bool active;

  final InlineScanner _scanner;
  final Expando<List<LineOrigin>> _origins = Expando('units origins');

  /// The analysis, once [finish] has run.
  Analysis? analysis;

  /// What the units print, once [finish] has run.
  Rendering? rendering;

  /// What the substitutions of [node]'s [text] start from: its prepared
  /// text, if the renderer prepared one for that text, or [text].
  String prepare(AbstractNode node, String text) {
    final prepared = rendering?.prepared[node];
    return prepared != null && prepared.source == text ? prepared.text : text;
  }

  /// Records where the lines of [node]'s text were read.
  void recordOrigins(AbstractNode node, List<LineOrigin> origins) {
    if (origins.isNotEmpty) _origins[node] = origins;
  }

  /// The recorded origins of [node]'s text.
  List<LineOrigin>? originsOf(AbstractNode node) => _origins[node];

  /// Whether [line] starts a block of its own: it begins with a marker of a
  /// level whose units are blocks (a statute's provisions), or `@^`.
  bool breaksParagraph(String line) {
    if (!active || !line.startsWith('@')) return false;
    final tokens = _scanner.scan(line, _nowhere, 0);
    if (tokens.isEmpty || tokens.first is! Marker) return false;
    final marker = tokens.first as Marker;
    if (marker.loc.column != 0) return false;
    if (marker.op == MarkerOp.close) return true;
    for (final scheme in config.schemes) {
      final level = marker.op == MarkerOp.step
          ? _steppedLevel(scheme, marker.up)
          : _labelledLevel(scheme, marker.label);
      if (level?.breakMode == Break.block) return true;
    }
    return false;
  }

  static final SourceFile _scratch = SourceFile('', const ['']);
  static Loc _nowhere(int column) => Loc(_scratch, 0, column, 0);

  Level? _steppedLevel(Scheme scheme, int up) {
    final d = scheme.defaultLevel;
    if (d == null) return null;
    final depth = d.depth - up;
    return depth >= 0 ? scheme.levels[depth] : null;
  }

  Level? _labelledLevel(Scheme scheme, String label) {
    final parses = parseCompound(scheme, label);
    if (parses.isEmpty) return null;
    final deepest = parses.map((x) => x.end).reduce((a, b) => a > b ? a : b);
    return scheme.levels[deepest];
  }

  // The walk ---------------------------------------------------------------

  final List<SourceFile> _files = [];
  final List<Event> _events = [];

  /// The text each node's units were found in, by node.
  final Map<AbstractNode, SourceFile> textOf = Map.identity();
  var _order = 0;

  /// Walks the document and runs the engine (once).
  Analysis finish() {
    if (analysis case final a?) return a;
    _document.blocks.forEach(_walk);
    final works = _loadWorks();
    Analysis run() => Engine(
      Document(SourceFile(docfile, const []), _files, _events, {
        for (final MapEntry(:key, :value) in _document.attributes.entries)
          key: value,
      }, const {}),
      config,
      works: works,
      knownIds: _document.catalog.refs.keys.toSet(),
    ).run();
    var a = run();
    // Layers: notes kept in other files (a commentary), each on an address
    // and the words it quotes, woven in where those words are.
    final layers = (_document.attributes['layers'] ?? '')
        .split(RegExp(r'[\s,]+'))
        .where((s) => s.isNotEmpty)
        .map((l) => p.join(p.dirname(docfile), l))
        .toList();
    if (layers.isNotEmpty) {
      final problems = _weave(a, layers);
      a = run();
      problems.forEach(a.diagnostics.add);
    }
    for (final d in a.diagnostics) {
      final where = d.loc == null ? '' : '${d.loc}: ';
      if (d.error) {
        LoggerManager.logger.error('$where${d.message}');
      } else {
        LoggerManager.logger.warn('$where${d.message}');
      }
    }
    analysis = a;
    rendering = renderUnits(_document, a, textOf);
    _resolveIncludes();
    return a;
  }

  void _walk(AbstractBlock node) {
    switch (node) {
      case Section():
        _heading(
          node,
          node.sourceTitle ?? '',
          node.level ?? 0,
          discrete: false,
        );
        node.blocks.forEach(_walk);
      case ListBlock(context: BlockContext.dlist):
        for (final entry in node.entries) {
          final term = entry.terms.first.sourceText;
          final description = entry.description;
          _text(
            description ?? entry.terms.first,
            BlockKind.dlist,
            description?.sourceText ?? '',
            style: node.style,
            term: term,
          );
          description?.blocks.forEach(_walk);
        }
      case ListBlock():
        for (final item in node.items) {
          _text(item, BlockKind.item, item.sourceText ?? '', style: node.style);
          item.blocks.forEach(_walk);
        }
      case Table():
        for (final row in node.rows.bySection.expand((s) => s.$2)) {
          for (final cell in row) {
            final inner = cell.innerDocument;
            if (inner != null) {
              inner.blocks.forEach(_walk);
            } else {
              _text(cell, BlockKind.paragraph, cell.sourceText ?? '');
            }
          }
        }
      case Block(context: BlockContext.floatingTitle):
        _heading(node, node.sourceTitle ?? '', node.level ?? 0, discrete: true);
      case Block(contentModel: ContentModel.simple, :final lines)
          when lines.length == 1 && _includeRx.hasMatch(lines.first):
        _placeholders.add((
          node,
          int.parse(_includeRx.firstMatch(lines.first)![1]!),
        ));
      case Block(context: BlockContext.verse):
        _text(node, BlockKind.verse, node.lines.join('\n'));
      case Block(contentModel: ContentModel.simple):
        _text(node, BlockKind.paragraph, node.lines.join('\n'));
      case Block(contentModel: ContentModel.compound):
        node.blocks.forEach(_walk);
      default:
        break;
    }
  }

  /// The roles of [node] and of the blocks around it (a paragraph of a note
  /// is the note's).
  static List<String> _roles(AbstractNode node) => [
    ...node.roles,
    for (var p = node.parent; p is Block; p = p.parent) ...p.roles,
  ];

  String _path(AbstractNode node) => _origins[node]?.first.file ?? docfile;

  void _heading(
    AbstractBlock node,
    String title,
    int depth, {
    required bool discrete,
  }) {
    final origins = _origins[node];
    final file = SourceFile(_path(node), [title], origins: origins);
    _files.add(file);
    textOf[node] = file;
    final order = ++_order;
    final tokens = _scanner.scan(title, (col) => Loc(file, 0, col, order), 0);
    Marker? marker;
    var rest = title;
    if (tokens.isNotEmpty &&
        tokens.first is Marker &&
        tokens.first.loc.column == 0) {
      final m0 = tokens.first as Marker;
      marker = Marker(
        m0.loc,
        m0.end,
        m0.op,
        m0.label,
        m0.attrs,
        inHeading: true,
        up: m0.up,
      );
      rest = title.substring(m0.end).trimLeft();
    }
    _events.add(
      HeadingEvent(
        Loc(file, 0, 0, order),
        depth,
        rest,
        marker,
        node.style,
        discrete: discrete,
      ),
    );
    for (final t in tokens.skip(marker == null ? 0 : 1)) {
      _events.add(TokenEvent(t));
    }
  }

  void _text(
    AbstractNode node,
    BlockKind kind,
    String text, {
    String? style,
    String? term,
  }) {
    final lines = text.split('\n');
    final file = SourceFile(_path(node), lines, origins: _origins[node]);
    _files.add(file);
    textOf[node] = file;
    final block = BlockStart(
      Loc(file, 0, 0, _order + 1),
      kind,
      style ?? (node is AbstractBlock ? node.style : null),
      _roles(node),
      node.id,
    )..term = term;
    _events.add(block);
    var first = true;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final order = ++_order;
      // Blank lines of a verse block separate its stanzas.
      if (line.trim().isEmpty) continue;
      _events.add(LineStart(Loc(file, i, 0, order), kind, first: first));
      final tokens = _scanner.scan(line, (col) => Loc(file, i, col, order), 0);
      if (first) {
        // Leading markers: only whitespace and range openers before them.
        var at = 0;
        for (final t in tokens) {
          if (line.substring(at, t.loc.column).trim().isNotEmpty) break;
          if (t is Marker) {
            block.leading.add(t);
          } else if (t is! RangeOpen) {
            break;
          }
          at = t.end;
        }
      }
      for (final t in tokens) {
        _events.add(TokenEvent(t));
      }
      first = false;
    }
    _events.add(BlockEnd(Loc(file, lines.length, 0, _order)));
  }

  // Includes ---------------------------------------------------------------

  static final RegExp _includeRx = RegExp('^\u{E120}(\\d+)\u{E111}\$');

  final List<UnitsInclude> _includes = [];
  final List<(Block, int)> _placeholders = [];

  /// The line the reader puts where [include] was: a placeholder the
  /// include's blocks take the place of once the document is parsed.
  String includeLine(UnitsInclude include) {
    _includes.add(include);
    return '\u{E120}${_includes.length - 1}\u{E111}';
  }

  /// Whether [line] is an include's placeholder (a block of its own).
  bool isInclude(String line) => _includeRx.hasMatch(line);

  void _resolveIncludes() {
    for (final (node, k) in _placeholders) {
      final include = _includes[k];
      final parent = node.parent;
      if (parent is! AbstractBlock) continue;
      var level = 1;
      for (AbstractNode? n = parent; n != null; n = n.parent) {
        if (n is Section) {
          level = (n.level ?? 0) + 1;
          break;
        }
      }
      final includer = Includer(
        rendering!,
        parent,
        level + include.levelOffset,
      );
      final blocks = <AbstractBlock>[];
      if (include.parallel case final other?) {
        final left = _rendered(include.target);
        final right = _rendered(other);
        final table = left == null || right == null
            ? const <AbstractBlock>[]
            : includer.parallel(left, right);
        if (table.isEmpty) {
          LoggerManager.logger.error(
            '${include.where}: no units to set side by side: '
            '${include.target} and $other',
          );
        }
        blocks.addAll(table);
      } else if (include.repeat) {
        final id = include.target.substring(1);
        final block = _document.catalog.refs[id];
        final copy = block is AbstractBlock
            ? includer.repeat(block, rendering!)
            : null;
        if (copy == null) {
          LoggerManager.logger.warn(
            '${include.where}: no block #$id to repeat',
          );
        } else {
          blocks.add(copy);
        }
      } else {
        final work = _citedWork(include);
        final passage = work == null
            ? null
            : resolvePassage(work.analysis, include.unit!);
        if (work == null) {
          LoggerManager.logger.warn(
            '${include.where}: no document ${include.target} to include from',
          );
        } else if (passage == null) {
          LoggerManager.logger.warn(
            '${include.where}: no passage ${include.unit} in ${include.target}',
          );
        } else {
          final style = include.cite ?? 'default';
          if (style != 'none' &&
              style != 'default' &&
              !work.analysis.config.citations.containsKey(style)) {
            LoggerManager.logger.warn(
              '${include.where}: ${include.target} declares no citation '
              'style $style',
            );
          }
          blocks.addAll(
            includer.passage(
              work,
              passage,
              quote: style == 'none'
                  ? null
                  : citation(work.analysis, passage, style: style),
              unquoted: {
                ...?work.analysis.config.settings['unquoted']?.split(
                  RegExp(r'[\s,]+'),
                ),
              }..remove(''),
            ),
          );
        }
      }
      final at = parent.blocks.indexOf(node);
      if (at >= 0) parent.blocks.replaceRange(at, at + 1, blocks);
    }
  }

  /// The document [include] cites, read natively: a work the document
  /// names (`:works:`), or a path from the file the include is in.
  RenderedWork? _citedWork(UnitsInclude include) {
    String? path;
    for (final entry
        in (_document.attributes['works'] ?? '')
            .split(RegExp(r'\s*;\s*'))
            .where((s) => s.contains('='))) {
      final eq = entry.indexOf('=');
      if (entry
          .substring(0, eq)
          .split('|')
          .any((n) => n.trim() == include.target)) {
        path = p.join(p.dirname(docfile), entry.substring(eq + 1).trim());
      }
    }
    path ??= p.join(p.dirname(include.file), include.target);
    return _rendered(path);
  }

  /// The document at [path], read natively, with its units rendered.
  RenderedWork? _rendered(String path) {
    final doc = _workDocument(p.normalize(path), _document.safe);
    final session = doc?.unitsSession;
    final a = session?.analysis;
    final r = session?.rendering;
    if (session == null || a == null || r == null) return null;
    return RenderedWork(a, r, session.textOf.keys.toList());
  }

  // Layers -----------------------------------------------------------------

  /// Weaves the notes of [layers] into the events, as notes a layer wove
  /// in ([Note.woven]): each on the unit of [a] its address names, at the
  /// words it quotes (vowel points and punctuation aside), or at the end
  /// of the unit's first line. Returns the problems found.
  List<Diagnostic> _weave(Analysis a, List<String> layers) {
    final problems = <Diagnostic>[];
    // Where each woven note goes: by file and line, its column.
    final woven = <SourceFile, Map<int, List<Note>>>{};
    for (final layer in layers) {
      if (!p.isFile(layer)) {
        problems.add(Diagnostic(null, 'layer not found: $layer'));
        continue;
      }
      final stream = headerAttributes(layer)['layer-stream'] ?? 'footnote';
      // Where the last note of a unit went, so the next looks after it.
      final after = <Unit, (int, int)>{};
      for (final line in p.readLines(layer)) {
        final m = RegExp(r'^(\S+)(?:\s+"([^"]*)")?::\s+(.*)$').firstMatch(line);
        if (m == null) continue;
        final address = m[1]!;
        final lemma = m[2];
        final body = m[3]!;
        final unit = resolveUnit(a, address);
        if (unit == null) {
          problems.add(
            Diagnostic(null, '${p.basename(layer)}: $address not found'),
          );
          continue;
        }
        final file = unit.start.file;
        final first = unit.start.line;
        final last = unit.end != null && unit.end!.file == file
            ? unit.end!.line
            : file.lines.length - 1;
        void add(int line, int column, {int? lemmaStart, String? text}) {
          final order = _orderOf(file, line);
          final loc = Loc(file, line, column, order);
          final children = _scanner.scan(
            body,
            (col) => Loc(file, line, column + col, order),
            0,
          );
          ((woven[file] ??= {})[line] ??= []).add(
            Note(
              loc,
              column,
              stream,
              text ?? body,
              column,
              children,
              lemma: lemmaStart == null
                  ? null
                  : file.lines[line].substring(lemmaStart, column),
              lemmaStart: lemmaStart,
              woven: true,
            ),
          );
        }

        if (lemma == null || lemma.isEmpty) {
          add(first, file.lines[first].length);
          continue;
        }
        var placed = false;
        final from = after[unit] ?? (first, unit.start.column);
        for (var ln = from.$1; ln <= last && !placed; ln++) {
          final text = file.lines[ln];
          if (ln > first && text.trim().isEmpty) break;
          final hit = findIgnoringPoints(
            text,
            lemma,
            ln == from.$1 ? from.$2 : 0,
          );
          if (hit == null) continue;
          add(ln, hit.$2, lemmaStart: hit.$1);
          after[unit] = (ln, hit.$2);
          placed = true;
        }
        // Not found as quoted: at the end of the unit's first line, the
        // words it quotes in the note.
        if (!placed) {
          add(first, file.lines[first].length, text: '__${lemma}__ – $body');
        }
      }
    }
    // Into the events, after the line's tokens that come before them.
    for (var i = 0; i < _events.length; i++) {
      final e = _events[i];
      if (e is! LineStart) continue;
      final notes = woven[e.loc.file]?[e.loc.line];
      if (notes == null) continue;
      notes.sort((x, y) => x.loc.column.compareTo(y.loc.column));
      var j = i + 1;
      for (final note in notes) {
        while (j < _events.length) {
          final next = _events[j];
          if (next is! TokenEvent || next.token.loc.column > note.loc.column) {
            break;
          }
          j++;
        }
        _events.insert(j++, TokenEvent(note));
      }
      i = j - 1;
    }
    return problems;
  }

  /// The order of the line [line] of [file]'s events.
  int _orderOf(SourceFile file, int line) {
    for (final e in _events) {
      if (e is LineStart && e.loc.file == file && e.loc.line == line) {
        return e.loc.order;
      }
    }
    return 0;
  }

  // Works ------------------------------------------------------------------

  /// The works the document cites, read natively, by name.
  Map<String, Analysis> _loadWorks() {
    final works = <String, Analysis>{};
    for (final entry
        in (_document.attributes['works'] ?? '')
            .split(RegExp(r'\s*;\s*'))
            .where((s) => s.contains('='))) {
      final eq = entry.indexOf('=');
      final path = p.normalize(
        p.join(p.dirname(docfile), entry.substring(eq + 1).trim()),
      );
      final work = _workDocument(path, _document.safe)?.unitsSession?.analysis;
      if (work == null) {
        LoggerManager.logger.warn('units: work not found: $path');
        continue;
      }
      for (final name in entry.substring(0, eq).split('|')) {
        works[name.trim()] = work;
      }
    }
    return works;
  }

  /// Works read in this process, by path; `null` while one is being read
  /// (a cycle).
  static final Map<String, ptome.Document?> _workCache = {};

  static ptome.Document? _workDocument(String path, int safe) {
    final key = p.absolute(path);
    if (_workCache.containsKey(key)) return _workCache[key];
    if (!p.isFile(key)) return null;
    _workCache[key] = null;
    final doc = loadFile(
      key,
      options: AsciidoctorOptions(
        safe: safe,
        attributes: const {'units-engine': 'native'},
      ),
    );
    return _workCache[key] = doc;
  }
}
