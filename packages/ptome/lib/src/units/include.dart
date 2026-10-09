/// Includes in units (ADR-0020): a passage of another document by its
/// address (`include::psalter.adoc[unit=95]`, `include::kjv[unit="Ps
/// 23:1-3"]`) and a block of this one again by its ID
/// (`include::#gloria[]`). The reader leaves a placeholder where the
/// directive was; once the document is parsed and its units rendered, the
/// placeholder gives way to blocks made from the cited document's own
/// parsed and rendered text, cut where the passage's units start and end:
/// spliced as they are (`cite=none`: labels, anchors, notes, headings as
/// discrete headings), or quoted in a block that cites the passage
/// (labels as the citation style keeps them; no anchors, notes or
/// headings).
library;

import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/abstract_node.dart';
import 'package:ptome/src/block.dart';
import 'package:ptome/src/list.dart';
import 'package:ptome/src/section.dart';
import 'package:ptome/src/table.dart';
import 'package:ptome/src/units/citation.dart';
import 'package:ptome/src/units/engine.dart';
import 'package:ptome/src/units/files.dart' as p;
import 'package:ptome/src/units/presentation.dart';
import 'package:ptome/src/units/render.dart';

/// An include directive in units the reader found.
final class UnitsInclude {
  /// An include of [target] (a work's name, a path, or `#id`), at [unit]
  /// (an address) and cited as [cite], found in [file] at [line].
  const new(
    this.target,
    this.unit,
    this.cite,
    this.file,
    this.line, {
    this.parallel,
    this.levelOffset = 0,
  });

  /// What the directive names.
  final String target;

  /// The passage's address, for an include by address.
  final String? unit;

  /// The citation style (`none`: spliced), if given.
  final String? cite;

  /// The file the directive is in.
  final String file;

  /// Its line there (1-based).
  final int line;

  /// The document to set beside the included one (`parallel=`), a path.
  final String? parallel;

  /// How much deeper its headings go (`leveloffset=+1`).
  final int levelOffset;

  /// Whether it repeats a block of this document by its ID.
  bool get repeat => target.startsWith('#');

  /// Where it is, for messages.
  String get where => '${p.basename(file)}: line $line';
}

/// A document's rendered units, as a cited document gives them.
final class RenderedWork {
  /// The [analysis] and [rendering] of a document whose texts, in document
  /// order, are [order].
  const new(this.analysis, this.rendering, this.order);

  /// Its units.
  final Analysis analysis;

  /// Its prepared texts.
  final Rendering rendering;

  /// Its texts (headings, paragraphs, items, cells), in document order.
  final List<AbstractNode> order;
}

/// Makes the blocks an include gives, into a document whose units are
/// [into], under [parent].
final class Includer {
  /// An includer adding atoms to [into], for blocks under [parent], whose
  /// discrete headings start at [level].
  new(this.into, this.parent, this.level);

  /// The including document's rendering.
  final Rendering into;

  /// The block the included blocks go in.
  final AbstractBlock parent;

  /// The level of a passage's first heading.
  final int level;

  /// The blocks of [passage] of [work]: spliced ([quote] null), or quoted
  /// as [quote] gives, with [unquoted] roles' blocks left out.
  List<AbstractBlock> passage(
    RenderedWork work,
    Passage passage, {
    (String, String, String, QuoteLabels)? quote,
    Set<String> unquoted = const {},
  }) {
    // Which of a unit's labels a quotation keeps.
    bool keepsLabel(Unit? unit) => switch (quote?.$4) {
      null || QuoteLabels.all => true,
      QuoteLabels.none => false,
      QuoteLabels.inner => !(passage.single && identical(unit, passage.start)),
    };
    UnitAtom? keep(UnitAtom atom) => quote == null
        ? atom
        : switch (atom) {
            AnchorAtom() || FootnoteAtom() || UnitStartAtom() => null,
            NoteCallAtom() || NoteEntryAtom() => null,
            UnitMarkAtom(:final unit, :final start) =>
              start && !keepsLabel(unit)
                  ? null
                  : atom.copyWith(anchored: false),
            PartAtom(kind: PartKind.overlay || PartKind.entry) => null,
            PartAtom(kind: PartKind.label, :final unit) =>
              keepsLabel(unit) ? atom : null,
            _ => atom,
          };
    // A quotation's blocks go in its block (a verse's lines in its own).
    final container = quote != null && quote.$3 != 'verse'
        ? (Block(
            parent,
            BlockContext.quote,
            contentModel: ContentModel.compound,
          )..style = 'quote')
        : null;
    final under = container ?? parent;
    final out = <AbstractBlock>[];
    int? firstDepth;
    ListBlock? listSource;
    ListBlock? list;
    for (final (:node, :text, :heading) in _slices(work, passage, keep)) {
      if (heading) {
        listSource = null;
        if (quote != null) continue;
        final depth = (node as AbstractBlock).level ?? 0;
        firstDepth ??= depth;
        final title =
            Block(
                under,
                BlockContext.floatingTitle,
                contentModel: ContentModel.empty,
              )
              ..title = text
              ..level = level + depth - firstDepth
              ..id = node.id
              ..style = 'discrete';
        node.roles.forEach(title.addRole);
        out.add(title);
        continue;
      }
      final roles = _rolesOf(node);
      if (quote != null && roles.any(unquoted.contains)) continue;
      // List items stay items, of a list like theirs (a dialogue's
      // speakers, a statute's points).
      if (_listOf(node) case final source?) {
        if (!identical(source, listSource)) {
          listSource = source;
          list = ListBlock(under, source.context)..style = source.style;
          source.roles.forEach(list.addRole);
          out.add(list);
        }
        final target = list!;
        final item = ListItem(target, text);
        if (source.context == BlockContext.dlist) {
          final entry = source.entries.firstWhere(
            (e) => identical(e.description, node),
            orElse: () => DlistEntry([node as ListItem]),
          );
          final term = identical(entry.terms.first, node)
              ? item
              : ListItem(target, entry.terms.first.sourceText);
          target.entries.add(
            DlistEntry([term], identical(term, item) ? null : item),
          );
        } else {
          target.blocks.add(item);
        }
        continue;
      }
      listSource = null;
      out.add(_block(node, text, roles, under));
    }
    if (quote == null) return out;
    final (attribution, title, _, _) = quote;
    final block =
        container ??
        (Block(
          parent,
          BlockContext.verse,
          contentModel: ContentModel.simple,
          lines: [
            for (final (i, b) in out.indexed) ...[
              if (i > 0) '',
              ...(b as Block).lines,
            ],
          ],
        )..style = 'verse');
    if (container != null) container.blocks.addAll(out);
    if (attribution.isNotEmpty) block.attributes['attribution'] = attribution;
    if (title.isNotEmpty) block.attributes['citetitle'] = title;
    return [block..commitSubs()];
  }

  /// The texts of [passage] of [work], in order, with the atoms [keep]
  /// keeps: its headings' titles and its blocks' texts, cut where its
  /// first unit starts and where the next unit of its last unit's level
  /// or above starts.
  Iterable<({AbstractNode node, String text, bool heading})> _slices(
    RenderedWork work,
    Passage passage,
    UnitAtom? Function(UnitAtom atom) keep,
  ) sync* {
    final rendering = work.rendering;
    final start = rendering.starts[passage.start];
    if (start == null) return;
    final end = passage.end;
    Unit? next;
    for (final u in work.analysis.units) {
      if (u.level.scheme == end.level.scheme &&
          u.level.depth <= end.level.depth &&
          !u.isZero &&
          u.start.compareTo(end.start) > 0 &&
          rendering.starts.containsKey(u) &&
          (next == null || u.start.compareTo(next.start) < 0)) {
        next = u;
      }
    }
    final stop = next == null ? null : rendering.starts[next];
    final from = work.order.indexOf(start.$1);
    final to = stop == null
        ? work.order.length - 1
        : work.order.indexOf(stop.$1);
    if (from < 0 || to < from) return;
    for (var i = from; i <= to; i++) {
      final node = work.order[i];
      final atStop = stop != null && i == to;
      if (node is Section ||
          (node is Block && node.context == BlockContext.floatingTitle)) {
        if (atStop && stop.$2 < 0) return;
        final source = (node as AbstractBlock).sourceTitle ?? '';
        yield (
          node: node,
          text: _import(
            rendering.prepared[node]?.text ?? source,
            rendering,
            keep,
          ),
          heading: true,
        );
        continue;
      }
      var text = rendering.prepared[node]?.text ?? _source(node);
      if (atStop) {
        final at = text.indexOf('$atomMark${stop.$2}$markEnd');
        if (at <= 0) return;
        text = text.substring(0, at);
      }
      if (i == from && start.$2 >= 0) {
        final at = text.indexOf('$atomMark${start.$2}$markEnd');
        if (at > 0) text = text.substring(at);
      }
      text = _import(text, rendering, keep).trimRight();
      if (text.endsWith(' +')) text = text.substring(0, text.length - 2);
      if (text.trim().isEmpty) continue;
      yield (node: node, text: text, heading: false);
    }
  }

  /// [left] and [right] (a text and its translation, in the same scheme)
  /// side by side, unit by unit, matched by address: [left]'s headings,
  /// and between them a table with a row for each unit of the default
  /// level, its text on each side. Empty when they share no unit.
  List<AbstractBlock> parallel(RenderedWork left, RenderedWork right) {
    UnitAtom? leftKeeps(UnitAtom atom) => switch (atom) {
      FootnoteAtom() || NoteCallAtom() || NoteEntryAtom() => null,
      PartAtom(kind: PartKind.overlay || PartKind.entry) => null,
      _ => atom,
    };
    UnitAtom? rightKeeps(UnitAtom atom) => switch (atom) {
      AnchorAtom() || UnitStartAtom() => null,
      UnitMarkAtom(:final parts) when parts.isEmpty => null,
      UnitMarkAtom() => atom.copyWith(anchored: false),
      _ => leftKeeps(atom),
    };
    // Each side's text starts with the unit's number, whatever its scheme
    // prints: the rows are read by it.
    String text(RenderedWork work, Unit u, UnitAtom? Function(UnitAtom) keep) {
      UnitAtom? withoutLabels(UnitAtom atom) => switch (atom) {
        PartAtom(kind: PartKind.label) => null,
        UnitMarkAtom(start: true, anchored: false) => null,
        UnitMarkAtom(start: true) => keep(atom.copyWith(parts: const [])),
        _ => keep(atom),
      };
      final body = [
        for (final slice in _slices(work, Passage(u, u), withoutLabels))
          if (!slice.heading) slice.text,
      ].join('\n\n');
      final number = u.level.bare(u.label);
      if (body.trim().isEmpty || number.isEmpty) return body;
      final label =
          into.place(
            PartAtom(
              number,
              style: PartStyle.superscript,
              kind: PartKind.label,
            ),
          ) +
          into.place(const PartAtom('\u00a0'));
      // After the anchor, if the text starts with one.
      final anchor = RegExp('^(?:$atomMark\\d+$markEnd)*')
          .firstMatch(body)![0]!;
      return anchor + label + body.substring(anchor.length);
    }

    final units = [...left.analysis.units]
      ..sort((x, y) => x.start.compareTo(y.start));
    if (!units.any((u) => right.analysis.byId.containsKey(u.id))) {
      return const [];
    }
    final out = <AbstractBlock>[];
    Table? table;
    int? firstDepth;
    for (final u in units) {
      if (u.heading != null) {
        table = null;
        final node = left.rendering.starts[u]?.$1;
        if (node is! AbstractBlock) continue;
        final depth = node.level ?? 0;
        firstDepth ??= depth;
        final source = node.sourceTitle ?? '';
        final title = _import(
          left.rendering.prepared[node]?.text ?? source,
          left.rendering,
          rightKeeps,
        );
        out.add(
          Block(
              parent,
              BlockContext.floatingTitle,
              contentModel: ContentModel.empty,
            )
            ..title = title.trim().isEmpty ? u.reftext : title
            ..level = level + depth - firstDepth
            ..style = 'discrete',
        );
        continue;
      }
      if (!u.level.isDefault) continue;
      final l = text(left, u, leftKeeps);
      final other = right.analysis.byId[u.id];
      final r = other == null ? '' : text(right, other, rightKeeps);
      if (l.trim().isEmpty && r.trim().isEmpty) continue;
      if (table == null) {
        table = Table(parent, const {})
          ..createColumns(const [ColumnSpec(), ColumnSpec()]);
        table.attributes
          ..['grid'] = 'rows'
          ..['frame'] = 'none';
        table.addRole('parallel-text');
        out.add(table);
      }
      final row = [Cell(table.columns[0], l), Cell(table.columns[1], r)];
      table.rows.body.add(row);
    }
    for (final t in out.whereType<Table>()) {
      t.partitionHeaderFooter(footer: false);
    }
    return out;
  }

  /// [block] (of this document) again: its text without its anchors, and
  /// no ID.
  AbstractBlock? repeat(AbstractBlock block, Rendering rendering) {
    UnitAtom? keep(UnitAtom atom) => switch (atom) {
      AnchorAtom() || UnitStartAtom() => null,
      UnitMarkAtom() => atom.copyWith(anchored: false),
      _ => atom,
    };
    AbstractBlock? copy(AbstractBlock node, AbstractBlock parent) {
      if (node is! Block) return null;
      final b = Block(
        parent,
        node.context,
        contentModel: node.contentModel,
        lines: node.contentModel == ContentModel.compound
            ? null
            : _import(
                rendering.prepared[node]?.text ?? node.lines.join('\n'),
                rendering,
                keep,
              ).split('\n'),
      )..style = node.style;
      for (final MapEntry(:key, :value) in node.attributes.entries) {
        if (key != 'id' && key != 'reftext') b.attributes[key] = value;
      }
      if (node.hasTitle) b.title = node.sourceTitle;
      b.commitSubs();
      for (final child in node.blocks) {
        if (copy(child, b) case final c?) b.blocks.add(c);
      }
      return b;
    }

    return copy(block, parent);
  }

  /// [text] (prepared in [from]) with its atoms and range marks in [into]
  /// instead: the atoms [keep] keeps (or changes), the rest gone.
  String _import(
    String text,
    Rendering from,
    UnitAtom? Function(UnitAtom atom) keep,
  ) {
    UnitAtom? atom(UnitAtom a) => switch (keep(a)) {
      null => null,
      TextAtom(:final text) => TextAtom(_import(text, from, keep)),
      FootnoteAtom(:final content, :final id, :final stream, :final caller) =>
        FootnoteAtom(
          content == null ? null : _import(content, from, keep),
          id: id,
          stream: stream,
          caller: caller,
        ),
      NoteEntryAtom(:final stream, :final atoms, :final role) => NoteEntryAtom(
        stream,
        [for (final a in atoms) ?atom(a)],
        role: role,
      ),
      final kept => kept,
    };
    return text
        .replaceAllMapped(atomRx, (m) {
          final a = atom(from.atoms[int.parse(m[1]!)]);
          return a == null ? '' : into.place(a);
        })
        .replaceAllMapped(
          RegExp('([$rangeOpenMark$rangeCloseMark])(\\d+)$markEnd'),
          (m) => '${m[1]}${into.role(from.roles[int.parse(m[2]!)])}$markEnd',
        );
  }

  /// A paragraph (or verse, or other block of text) of [text], as [node]
  /// is.
  Block _block(
    AbstractNode node,
    String text,
    List<String> roles,
    AbstractBlock parent,
  ) {
    final b = switch (node) {
      Block(:final context, :final contentModel)
          when contentModel == ContentModel.simple =>
        Block(
          parent,
          context,
          contentModel: contentModel,
          lines: text.split('\n'),
        )..style = node.style,
      _ => Block(
        parent,
        BlockContext.paragraph,
        contentModel: ContentModel.simple,
        lines: text.split('\n'),
      ),
    };
    roles.forEach(b.addRole);
    if (node.attributes.containsKey('hardbreaks-option')) {
      b.setOption('hardbreaks');
    }
    return b..commitSubs();
  }

  /// The list [node] is an item of, if it is one.
  static ListBlock? _listOf(AbstractNode node) => switch (node) {
    ListItem(parent: final ListBlock list) => list,
    _ => null,
  };

  static String _source(AbstractNode node) => switch (node) {
    Block(:final lines) => lines.join('\n'),
    ListItem(:final sourceText) => sourceText ?? '',
    Cell(:final sourceText) => sourceText ?? '',
    _ => '',
  };

  static List<String> _rolesOf(AbstractNode node) => [
    ...node.roles,
    if (node is ListItem)
      if (node.parent case final AbstractBlock list) ...list.roles,
  ];
}
