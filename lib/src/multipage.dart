/// The `multipage_html5` backend (the name asciidoctor-multipage uses): a
/// book as a website, one HTML page per part and chapter (or deeper, by
/// `multipage-level`), with navigation, and links that reach across pages.
library;

import 'dart:typed_data';

import 'package:mustache_template/mustache_template.dart' show Template;
import 'package:ptome/src/abstract_block.dart';
import 'package:ptome/src/block.dart';
import 'package:ptome/src/context.dart';
import 'package:ptome/src/converter.dart';
import 'package:ptome/src/document.dart';
import 'package:ptome/src/helpers.dart';
import 'package:ptome/src/html5.dart';
import 'package:ptome/src/io.dart' as io;
import 'package:ptome/src/output_template.dart';
import 'package:ptome/src/section.dart';
import 'package:ptome/src/template_loader.dart';

/// A link to a page: its path, its title (numbered, as the list of pages
/// has it), its title alone and its number (when numbered).
typedef _Link = ({String file, String title, String basic, String? number});

/// A page of the site: a section of its own, the page it belongs to
/// ([up]; the root page when null), its file (relative to the root
/// page's directory) and the path links to it go to (the directory of an
/// `index.html`).
final class _Page {
  new(this.section, this.file, this.up, {String? href}) : href = href ?? file;

  final Section section;
  final String file;
  final String href;
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

  /// The list of pages a `toc::[]` macro shows, when the document has one.
  String? _contents;

  @override
  String convertToc(Block node) {
    final contents = _contents;
    if (contents == null) return super.convertToc(node);
    final doc = node.document! as Document;
    final title = node.hasTitle ? node.title! : doc.attr('toc-title') ?? '';
    final id = node.id ?? 'toc';
    final role = doc.attr('toc-class') ?? 'toc';
    return '<div id="$id" class="$role">\n'
        '<div id="${id}title">$title</div>\n'
        '$contents\n'
        '</div>';
  }

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
    _document = node;
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
        final page = _pageOf(child, node.outfilesuffix ?? '.html', up);
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
      final contents = _list(
        tree,
        node,
        'multipage-toc',
        levels: int.tryParse(node.attr('multipage-toclevels') ?? '') ?? 0,
      );
      // A `toc::[]` macro (on a page of its own, say) takes the list of
      // pages; else it ends the home page.
      final hasMacro = node.findBy(context: BlockContext.toc).isNotEmpty;
      _contents = hasMacro ? contents : null;
      node.blocks
        ..clear()
        ..addAll(blocks.where((block) => block is! Section))
        ..addAll([if (!hasMacro) _raw(node, contents)]);
      footnotes.clear();
      final root = (
        file: _rootFile,
        title: node.doctitle() ?? '',
        basic: node.doctitle() ?? '',
        number: null,
      );
      _Link link(_Page page) => (
        file: page.href,
        title: _title(page.section),
        basic: _plainTitle(page.section.title ?? ''),
        number: page.section.numbered ? page.section.sectnum() : null,
      );
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
        if (_pageContents(node, section) case final contents?) {
          section.blocks.insert(0, _raw(section, contents));
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
    final hrefs = {for (final page in order) page.file: page.href};
    pages.addAll(_rebased(_relinked(html, hrefs)));
    return pages[_rootFile]!;
  }

  /// The page of [section] (under [up]): its file is its id, or its
  /// `page-path` (`part/one/`, a directory, gives `part/one/index.html`,
  /// linked as the directory).
  _Page _pageOf(Section section, String suffix, _Page? up) {
    final path = section.attr('page-path')?.replaceFirst(RegExp('^/+'), '');
    if (path == null || path.isEmpty) {
      return _Page(section, '${section.id}$suffix', up);
    }
    if (path.split('/').any((segment) => segment == '..' || segment == '.')) {
      logger.warn(
        'page-path must stay in the site: $path (the page is named after '
        'its id)',
      );
      return _Page(section, '${section.id}$suffix', up);
    }
    if (path.endsWith('/')) {
      return _Page(section, '${path}index$suffix', up, href: path);
    }
    final file = path.substring(path.lastIndexOf('/') + 1).contains('.')
        ? path
        : '$path$suffix';
    return _Page(section, file, up);
  }

  /// The website is several files: none to give as one.
  @override
  Uint8List? get output => null;

  /// Writes the root page to [path] and the other pages beside it.
  @override
  void write(String path) {
    final slash = path.lastIndexOf(RegExp(r'[/\\]'));
    final dir = slash < 0 ? '' : path.substring(0, slash + 1);
    for (final MapEntry(key: file, value: html) in pages.entries) {
      if (file.contains('/')) {
        io.createDirectories('$dir${file.substring(0, file.lastIndexOf('/'))}');
      }
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

  /// [section]'s entry in the list of pages: its numbered title, or the
  /// `multipage-toc-entry-template` (ADR-0010; `{{title}}`,
  /// `{{basic-title}}`, `{{number}}`).
  static String _entry(Document document, Section section) =>
      switch (document.attr('multipage-toc-entry-template')) {
        final template? => renderTemplate(template, {
          'title': _title(section),
          'basic-title': _plainTitle(section.title ?? ''),
          'number': section.numbered ? section.sectnum() : null,
        }),
        null => _title(section),
      };

  /// [title] as plain HTML (its links left out).
  static String _plainTitle(String title) =>
      title.replaceAll(RegExp('<a [^>]*>|</a>'), '');

  /// The title of [section] as the list of pages shows it (with its
  /// number, when sections are numbered), as plain HTML.
  static String _title(Section section) {
    final number = section.numbered ? '${section.sectnum()} ' : '';
    return '$number${section.title ?? ''}'.replaceAll(
      RegExp('<a [^>]*>|</a>'),
      '',
    );
  }

  /// The pages of [pages] (and theirs) as a nested list, with each page's
  /// sections down to section level [levels] (`multipage-toclevels`).
  String _list(
    List<_Page> pages,
    Document document,
    String role, {
    int levels = 0,
  }) {
    String sections(_Page page, AbstractBlock parent) {
      final listed = [
        for (final child in parent.blocks)
          if (child is Section &&
              child.level! <= levels &&
              !page.children.any((c) => identical(c.section, child)))
            child,
      ];
      if (listed.isEmpty) return '';
      return [
        '\n<ul class="multipage-sections">',
        for (final section in listed)
          [
            '<li><a href="${page.href}#${section.id}">',
            _entry(document, section),
            '</a>',
            sections(page, section),
            '</li>',
          ].join(),
        '</ul>\n',
      ].join('\n');
    }

    String items(List<_Page> pages) => [
      '<ul>',
      // Ptome's `notoc` option: a page left out of the list.
      for (final page in pages.where((p) => !p.section.hasOption('notoc')))
        [
          // The section's kind and roles, for a stylesheet (chapters
          // numbered by a counter, say).
          '<li class="${_classes(page.section)}">',
          '<a href="${page.href}">${_entry(document, page.section)}</a>',
          if (levels > 0) sections(page, page.section),
          if (page.children.isNotEmpty) '\n${items(page.children)}\n',
          '</li>',
        ].join(),
      '</ul>',
    ].join('\n');
    return '<nav class="$role">\n${items(pages)}\n</nav>';
  }

  /// [section]'s kind (`chapter`, `part`...) and roles.
  static String _classes(Section section) =>
      [section.sectname, ...section.roles].nonNulls.join(' ');

  /// [html] (a page titled [title], the root when null) with links to the
  /// [previous], enclosing ([up]) and [next] pages above and below its
  /// content.
  String _withNavigation(
    String html, {
    required String? title,
    required _Link? previous,
    required _Link? up,
    required _Link? next,
  }) {
    final nav = _navigation(previous: previous, up: up, next: next);
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

  /// The links to the [previous], enclosing ([up]) and [next] pages: the
  /// `multipage_nav.mustache` template of a `-T` directory (with
  /// `previous`, `up` and `next`, each `href`, `title`, `basic-title`,
  /// `number` and `label`), or the default markup; each link's text from
  /// the `multipage-nav-<kind>-template` attribute (ADR-0010; `{{title}}`,
  /// `{{basic-title}}`, `{{number}}`).
  String _navigation({
    required _Link? previous,
    required _Link? up,
    required _Link? next,
  }) {
    final document = _document;
    String label(String kind, String fallback, _Link page) => renderTemplate(
      document?.attr('multipage-nav-$kind-template') ?? fallback,
      {'title': page.title, 'basic-title': page.basic, 'number': page.number},
    );
    Map<String, String>? link(String kind, String fallback, _Link? page) =>
        page == null
        ? null
        : {
            'href': page.file,
            'title': page.title,
            'basic-title': page.basic,
            'number': ?page.number,
            'label': label(kind, fallback, page),
          };
    final context = {
      'previous': ?link('previous', '&#8592; {{title}}', previous),
      'up': ?link('up', '&#8593; {{title}}', up),
      'next': ?link('next', '{{title}} &#8594;', next),
    };
    if (_navTemplate case final template?) {
      return template.renderString(context).trimRight();
    }
    String a(String rel, Map<String, String> page) =>
        '<a class="$rel" rel="$rel" href="${page['href']}">${page['label']}</a>';
    final links = [
      if (context['previous'] case final page?) a('prev', page),
      if (context['up'] case final page?) a('up', page),
      if (context['next'] case final page?) a('next', page),
    ];
    return '<nav class="multipage-nav">\n${links.join('\n')}\n</nav>';
  }

  /// The contents of [section]'s page, at its top: its own sections, down
  /// `multipage-page-toclevels` levels (none by default), in the
  /// `multipage_toc.mustache` template of a `-T` directory (with `title`,
  /// the `toc-title`, and `entries`, the list) or in a table of contents'
  /// markup.
  String? _pageContents(Document document, Section section) {
    final levels =
        int.tryParse(document.attr('multipage-page-toclevels') ?? '') ?? 0;
    // (Sections with pages of their own are no longer among its blocks.)
    if (levels < 1 || section.sections.isEmpty) return null;
    final entries = convertOutline(
      section,
      ConvertOptions(toclevels: section.level! + levels),
    );
    if (entries == null) return null;
    final title = document.attr('toc-title') ?? 'Table of Contents';
    if (_templates['multipage_toc'] case final template?) {
      return template.renderString({
        'title': title,
        'entries': entries,
      }).trimRight();
    }
    return '<div id="toc" class="toc">\n<div id="toctitle">$title</div>\n'
        '$entries\n</div>';
  }

  /// The document being converted.
  Document? _document;

  /// The `multipage_nav.mustache` template of the `-T` directories.
  Template? get _navTemplate => _templates['multipage_nav'];

  /// The website's templates (`multipage_nav`, `multipage_toc`) in the
  /// `-T` directories.
  late final Map<String, Template> _templates = {
    if (opts.templateDirs.isNotEmpty)
      for (final MapEntry(:key, :value) in FileTemplateLoader(
        templateDirs: opts.templateDirs,
      ).load().entries)
        if (key.startsWith('multipage_'))
          key: Template(value, lenient: true, htmlEscapeValues: false),
  };

  /// [pages] with each link to an id on another page (`href="#id"`)
  /// pointing to that page (by its path in [hrefs]).
  static Map<String, String> _relinked(
    Map<String, String> pages,
    Map<String, String> hrefs,
  ) {
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
          return target == null
              ? m[0]!
              : '${m[1]}${hrefs[target] ?? target}#$id"';
        }),
    };
  }

  /// [pages] with the relative URLs of the pages in subdirectories
  /// (`page-path`) made relative to them: links, images, stylesheets and
  /// scripts written for the root page's directory.
  static Map<String, String> _rebased(Map<String, String> pages) => {
    for (final MapEntry(key: file, value: html) in pages.entries)
      file: switch ('/'.allMatches(file).length) {
        0 => html,
        final depth => html.replaceAllMapped(_tagRx, (tag) {
          return tag[0]!.replaceAllMapped(_urlAttributeRx, (m) {
            final url = m[2]!;
            if (url.isEmpty || _absoluteRx.hasMatch(url)) return m[0]!;
            return '${m[1]}${'../' * depth}$url"';
          });
        }),
      },
  };

  /// The tags whose `href` or `src` load or link a resource (in code,
  /// tags are escaped: none is found there).
  static final RegExp _tagRx = RegExp(
    r'<(?:a|img|link|script|source|video|audio|iframe|object|embed)\s[^>]*>',
  );

  static final RegExp _urlAttributeRx = RegExp(
    r'(\s(?:href|src|poster|data)=")([^"]*)"',
  );

  /// A URL that isn't relative to the page's directory: in the page, from
  /// the site's root, or with a scheme.
  static final RegExp _absoluteRx = RegExp(r'^(?:#|/|\?|[a-zA-Z][\w+.-]*:)');
}
