/// The `multipage_html5` backend (the name asciidoctor-multipage uses): a
/// book as a website, one HTML page per part and chapter (or deeper, by
/// `multipage-level`), with navigation, and links that reach across pages.
library;

import 'package:asciidart/src/abstract_block.dart';
import 'package:asciidart/src/block.dart';
import 'package:asciidart/src/context.dart';
import 'package:asciidart/src/converter.dart';
import 'package:asciidart/src/document.dart';
import 'package:asciidart/src/helpers.dart';
import 'package:asciidart/src/html5.dart';
import 'package:asciidart/src/io.dart' as io;
import 'package:asciidart/src/section.dart';

/// A page of the site: a section of its own, the page it belongs to
/// ([up]; the root page when null), and its file name.
final class _Page {
  new(this.section, this.file, this.up);

  final Section section;
  final String file;
  final _Page? up;
  final List<_Page> children = [];
}

/// Converts a document to linked HTML pages: the root page (the output
/// file: the header, the preamble and a list of the pages) and one page
/// per section up to `multipage-level` (1, chapters, by default; parts
/// too), each named after the section's id. Links to an id on another
/// page are rewritten to that page; footnotes are listed on the page they
/// are on; the index links to every use, wherever it is.
class MultipageHtml5Converter extends Html5Converter
    implements PackagingConverter {
  /// A converter for [backend].
  new(super.backend, [super.opts]);

  /// Registers the `multipage_html5` backend.
  static void register() => Converter.register(MultipageHtml5Converter.new, [
    'multipage_html5',
  ], provided: true);

  /// The pages converted, by file name; the root page first.
  final Map<String, String> pages = {};

  /// The root page's file name.
  String _rootFile = 'index.html';

  @override
  void beginIndex(Document document) {
    // Once, for the whole document (each page is converted as a document
    // of its own sections).
  }

  @override
  String convertEmbedded(Document node) => convertDocument(node);

  @override
  String convertDocument(Document node) {
    if (node.parentDocument != null) return super.convertEmbedded(node);
    super.beginIndex(node);
    pages.clear();
    _rootFile = switch (node.attr('outfile')) {
      final String path when path.isNotEmpty => Helpers.basename(path),
      _ => 'index${node.outfilesuffix}',
    };
    final level = int.tryParse(node.attr('multipage-level') ?? '') ?? 1;
    final tree = <_Page>[];
    final order = <_Page>[];
    void collect(AbstractBlock parent, _Page? up, List<_Page> into) {
      for (final child in parent.blocks) {
        if (child is! Section || child.level! > level) continue;
        final page = _Page(child, '${child.id}${node.outfilesuffix}', up);
        into.add(page);
        order.add(page);
        collect(child, page, page.children);
      }
    }

    collect(node, null, tree);

    final blocks = [...node.blocks];
    final attributes = Map<String, String>.of(node.attributes);
    final footnotes = node.catalog.footnotes;
    final html = <String, String>{};
    try {
      // The root page: the header, what comes before the first page, and
      // the list of pages (in place of the table of contents).
      node.attributes.remove('toc');
      node.blocks
        ..clear()
        ..addAll(blocks.where((block) => block is! Section))
        ..add(_raw(node, _list(tree, node, 'multipage-toc')));
      footnotes.clear();
      final root = (file: _rootFile, title: node.doctitle() ?? '');
      ({String file, String title}) link(_Page page) =>
          (file: page.file, title: _title(page.section));
      html[_rootFile] = _withNavigation(
        super.convertDocument(node),
        title: null,
        previous: null,
        up: null,
        next: order.isEmpty ? null : link(order.first),
      );
      node.attributes['noheader'] = '';
      for (final (i, page) in order.indexed) {
        final section = page.section;
        final own = [...section.blocks];
        section.blocks
          ..clear()
          ..addAll(
            own.where(
              (block) => !page.children.any((c) => identical(c.section, block)),
            ),
          );
        if (page.children.isNotEmpty) {
          section.blocks.add(
            _raw(section, _list(page.children, node, 'multipage-children')),
          );
        }
        node.blocks
          ..clear()
          ..add(section);
        footnotes.clear();
        try {
          html[page.file] = _withNavigation(
            super.convertDocument(node),
            title: _title(section),
            previous: i == 0 ? root : link(order[i - 1]),
            up: page.up == null ? root : link(page.up!),
            next: i + 1 < order.length ? link(order[i + 1]) : null,
          );
        } finally {
          section.blocks
            ..clear()
            ..addAll(own);
        }
      }
    } finally {
      node.blocks
        ..clear()
        ..addAll(blocks);
      node.attributes
        ..clear()
        ..addAll(attributes);
    }
    pages.addAll(_relinked(html));
    return pages[_rootFile]!;
  }

  /// Writes the root page to [path] and the other pages beside it.
  @override
  void write(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final dir = slash < 0 ? '' : path.substring(0, slash + 1);
    for (final MapEntry(key: file, value: html) in pages.entries) {
      io.writeString(
        file == _rootFile ? path : '$dir$file',
        html.endsWith('\n') ? html : '$html\n',
      );
    }
  }

  /// A block of [parent] that converts to [html] as it is.
  static Block _raw(AbstractBlock parent, String html) => Block(
    parent,
    BlockContext.pass,
    source: html,
    subs: const BlockSubs.none(),
  );

  /// The title of [section] as the list of pages shows it (with its
  /// number, when sections are numbered), as plain HTML.
  static String _title(Section section) {
    final number = section.numbered ? '${section.sectnum()} ' : '';
    return '$number${section.title ?? ''}'.replaceAll(
      RegExp('<a [^>]*>|</a>'),
      '',
    );
  }

  /// The pages of [pages] (and theirs) as a nested list.
  String _list(List<_Page> pages, Document document, String role) {
    String items(List<_Page> pages) => [
      '<ul>',
      for (final page in pages)
        [
          '<li><a href="${page.file}">${_title(page.section)}</a>',
          if (page.children.isNotEmpty) '\n${items(page.children)}\n',
          '</li>',
        ].join(),
      '</ul>',
    ].join('\n');
    return '<nav class="$role">\n${items(pages)}\n</nav>';
  }

  /// [html] (a page titled [title], the root when null) with links to the
  /// [previous], enclosing ([up]) and [next] pages above and below its
  /// content.
  String _withNavigation(
    String html, {
    required String? title,
    required ({String file, String title})? previous,
    required ({String file, String title})? up,
    required ({String file, String title})? next,
  }) {
    String a(String kind, ({String file, String title}) page, String text) =>
        '<a class="$kind" rel="$kind" href="${page.file}">$text</a>';
    final links = [
      if (previous != null) a('prev', previous, '&#8592; ${previous.title}'),
      if (up != null) a('up', up, '&#8593; ${up.title}'),
      if (next != null) a('next', next, '${next.title} &#8594;'),
    ];
    final nav = '<nav class="multipage-nav">\n${links.join('\n')}\n</nav>';
    var result = html
        .replaceFirst('<div id="content"', '$nav\n<div id="content"')
        .replaceFirstMapped(
          RegExp('</div>\n(<div id="footnotes"|<div id="footer")'),
          (m) => '</div>\n$nav\n${m[1]}',
        );
    if (title != null) {
      result = result.replaceFirstMapped(
        RegExp('<title>([^<]*)</title>'),
        (m) =>
            '<title>${title.replaceAll(RegExp('<[^>]*>'), '')} | ${m[1]}</title>',
      );
    }
    return result;
  }

  /// [pages] with each link to an id on another page (`href="#id"`)
  /// pointing to that page.
  static Map<String, String> _relinked(Map<String, String> pages) {
    final idRx = RegExp(r'\sid="([^"]+)"');
    final ids = <String, Set<String>>{
      for (final MapEntry(key: file, value: html) in pages.entries)
        file: {for (final m in idRx.allMatches(html)) m[1]!},
    };
    final home = <String, String>{};
    for (final MapEntry(key: file, value: own) in ids.entries) {
      for (final id in own) {
        home.putIfAbsent(id, () => file);
      }
    }
    return {
      for (final MapEntry(key: file, value: html) in pages.entries)
        // Links in tags only: a listing's HTML is escaped (`&lt;a`).
        file: html.replaceAllMapped(RegExp('(<a [^>]*?href=")#([^"]+)"'), (m) {
          final id = m[2]!;
          if (ids[file]!.contains(id)) return m[0]!;
          final target = home[id];
          return target == null ? m[0]! : '${m[1]}$target#$id"';
        }),
    };
  }
}
