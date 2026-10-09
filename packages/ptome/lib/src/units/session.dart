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
import 'package:ptome/src/units/document.dart';
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/process.dart' show schemesDir;
import 'package:ptome/src/units/render.dart';
import 'package:ptome/src/units/scheme.dart';

/// A document's units, as its parse finds them.
final class UnitsSession {
  new _(this._document, this.config, this.docfile, {required this.active})
    : _scanner = InlineScanner(config.ranges.keys.toSet(), active: active);

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
    final doc = Document(SourceFile(docfile, const []), _files, _events, {
      for (final MapEntry(:key, :value) in _document.attributes.entries)
        key: value,
    }, const {});
    final a = Engine(
      doc,
      config,
      works: _loadWorks(),
      knownIds: _document.catalog.refs.keys.toSet(),
    ).run();
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
      final work = _work(path, _document.safe);
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
  static final Map<String, Analysis?> _workCache = {};

  static Analysis? _work(String path, int safe) {
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
    final analysis = doc.unitsSession?.finish();
    _workCache[key] = analysis;
    return analysis;
  }
}
