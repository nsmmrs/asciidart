/// The EPUB package the EPUB3 backend builds: its metadata, manifest and
/// spine, written out as the gepub 1.0.17 gem writes them for
/// asciidoctor-epub3 (`package.opf`, `META-INF/container.xml`, the zip
/// with `mimetype` first and stored, then every file sorted by path).
library;

import 'dart:convert';

import 'package:asciidart/src/epub3/zip.dart';

/// The media type gepub guesses for a path by its extension.
String? guessMediaType(String href) {
  final ext = extname(href).toLowerCase();
  for (final (pattern, type) in _mediaTypesByExtension) {
    if (pattern.hasMatch(ext)) return type;
  }
  return null;
}

final List<(RegExp, String)> _mediaTypesByExtension = [
  (RegExp(r'^\.(html|xhtml)$'), 'application/xhtml+xml'),
  (RegExp(r'^\.css$'), 'text/css'),
  (RegExp(r'^\.js$'), 'text/javascript'),
  (RegExp(r'^\.(jpg|jpeg)$'), 'image/jpeg'),
  (RegExp(r'^\.png$'), 'image/png'),
  (RegExp(r'^\.gif$'), 'image/gif'),
  (RegExp(r'^\.svg$'), 'image/svg+xml'),
  (RegExp(r'^\.opf$'), 'application/oebps-package+xml'),
  (RegExp(r'^\.ncx$'), 'application/x-dtbncx+xml'),
  (RegExp(r'^\.(otf|ttf|ttc|eot)$'), 'application/vnd.ms-opentype'),
  (RegExp(r'^\.woff$'), 'application/font-woff'),
  (RegExp(r'^\.mp4$'), 'video/mp4'),
  (RegExp(r'^\.mp3$'), 'audio/mpeg'),
];

/// The extension of [path] (from the last dot of its last segment, as
/// Ruby's `File.extname`: leading dots belong to the name, so `.profile`
/// and `....xhtml` have none).
String extname(String path) {
  final base = _basename(path);
  final leading = base.length - base.replaceFirst(RegExp(r'^\.+'), '').length;
  final dot = base.lastIndexOf('.');
  return dot < leading || dot <= 0 || dot == base.length - 1
      ? ''
      : base.substring(dot);
}

String _basename(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

/// The ids in use in a package, and gepub's way of generating new ones.
final class _IdPool {
  final Set<String> _taken = {};
  final Map<String, int> _counters = {};

  bool contains(String id) => _taken.contains(id);

  void add(String id) => _taken.add(id);

  /// A new id: [prefix] alone first when [withoutCount], then [prefix]
  /// with a counter.
  String generate(String prefix, {bool withoutCount = false}) {
    var count = _counters[prefix] ?? 1;
    if (count < 1) count = 1;
    var bare = withoutCount;
    while (true) {
      final String key;
      if (bare) {
        key = prefix;
        count -= 1;
        bare = false;
      } else {
        key = '$prefix$count';
      }
      if (!_taken.contains(key)) {
        _counters[prefix] = count + 1;
        return key;
      }
      count += 1;
    }
  }
}

/// One `<dc:*>` or `<meta>` element of the metadata, with the `<meta
/// refines>` elements that refine it.
final class EpubMeta {
  new _(this.name, this.content, this.attributes);

  /// The element name (`title`, `creator`, `meta`...).
  final String name;

  /// The text of the element.
  final String content;

  /// The attributes, in order.
  final Map<String, String> attributes;

  final Map<String, List<EpubMeta>> _refiners = {};

  /// Replaces the refinements for [property] with one of [content].
  void refine(String property, String content) {
    _refiners[property] = [
      EpubMeta._('meta', content, {'property': property}),
    ];
  }

  void _write(
    _Xml xml,
    _IdPool pool, {
    bool dc = true,
    Map<String, String> extra = const {},
  }) {
    if (_refiners.isNotEmpty && attributes['id'] == null) {
      final id = pool.generate(name);
      pool.add(id);
      attributes['id'] = id;
    }
    xml.element(dc && name != 'meta' ? 'dc:$name' : name, {
      ...attributes,
      ...extra,
    }, text: content);
    for (final list in _refiners.values) {
      for (final refiner in list) {
        refiner._write(
          xml,
          pool,
          dc: false,
          extra: {'refines': '#${attributes['id']}'},
        );
      }
    }
  }
}

/// A file of the package (a manifest item).
final class EpubItem {
  new _(this.id, this.href, this.mediaType);

  /// The manifest id.
  final String id;

  /// The path, relative to the package document.
  final String href;

  /// The media type (`null` when gepub can't guess it).
  final String? mediaType;

  /// The manifest properties, in the order they were added (`null` until
  /// one is, or until the content of an XHTML item is set).
  List<String>? properties;

  /// The bytes of the file, or `null` for an item without content.
  List<int>? content;

  /// Adds [property] to the item's properties.
  void addProperty(String property) => (properties ??= []).add(property);

  /// Sets the content of the item to [text] (UTF-8).
  void setText(String text) => setBytes(utf8.encode(text));

  /// Sets the content of the item to [bytes]; for an XHTML document, adds
  /// the properties its content calls for (gepub's
  /// `guess_content_property`).
  void setBytes(List<int> bytes) {
    content = bytes;
    if (RegExp(r'\.x?html').hasMatch(extname(href)) &&
        mediaType == 'application/xhtml+xml') {
      properties ??= [];
      _guessProperties(utf8.decode(bytes, allowMalformed: true));
    }
  }

  void _guessProperties(String xhtml) {
    if (!_htmlRootRx.hasMatch(xhtml)) return;
    if (_remoteImageRx.hasMatch(xhtml) ||
        _remoteMediaRx.hasMatch(xhtml) ||
        _remoteSourceRx.hasMatch(xhtml)) {
      addProperty('remote-resources');
    }
    if (_mathmlRx.hasMatch(xhtml)) addProperty('mathml');
    if (_svgRx.hasMatch(xhtml)) addProperty('svg');
    if (xhtml.contains('<epub:switch')) addProperty('switch');
    if (_scriptRx.hasMatch(xhtml)) addProperty('scripted');
  }
}

final RegExp _htmlRootRx = RegExp(
  r'^(?:<\?[^>]*\?>\s*)?(?:<!DOCTYPE[^>]*>\s*)?<html\b',
);
final RegExp _remoteImageRx = RegExp(r'''<img\b[^>]*\ssrc=["']http''');
final RegExp _remoteMediaRx = RegExp(
  r'''<(?:video|audio)\b[^>]*\ssrc=["']http''',
);
final RegExp _remoteSourceRx = RegExp(
  r'''<(?:video|audio)\b[^>]*>(?:(?!</(?:video|audio)>)[\s\S])*<source\b[^>]*\ssrc=["']http''',
);
final RegExp _mathmlRx = RegExp(
  r'<mml:math\b|<math\b[^>]*xmlns="http://www\.w3\.org/1998/Math/MathML"',
);
final RegExp _svgRx = RegExp(
  r'<svg:svg\b|<svg\b[^>]*xmlns="http://www\.w3\.org/2000/svg"',
);
final RegExp _scriptRx = RegExp(r'<(?:script|form)\b');

/// An EPUB 3 publication being built.
final class EpubBook {
  /// The path of the package document in the container.
  static const String packagePath = 'EPUB/package.opf';
  static const String _contentsPrefix = 'EPUB/';

  final _IdPool _pool = _IdPool();
  final Map<String, List<EpubMeta>> _metadata = {};
  final List<EpubMeta> _oldstyleMeta = [];
  final Map<String, EpubItem> _items = {};
  final List<String> _spine = [];
  final Map<String, String> _optionalFiles = {};

  /// Prefixes declared on the package (`calibre`...), in order.
  final Map<String, String> prefixes = {};

  String? _uniqueIdentifier;

  /// The identifier of the publication.
  String? get identifier {
    for (final meta in _metadata['identifier'] ?? const <EpubMeta>[]) {
      if (meta.attributes['id'] == _uniqueIdentifier) return meta.content;
    }
    return null;
  }

  EpubMeta _add(String name, String content, {String? id}) {
    final meta = EpubMeta._(name, content, {'id': ?id});
    if (id != null) {
      if (_pool.contains(id)) throw StateError("id '$id' is already in use.");
      _pool.add(id);
    }
    (_metadata[name] ??= []).add(meta);
    return meta;
  }

  void _clear(String name) {
    if (_metadata.containsKey(name)) _metadata[name] = [];
  }

  /// Sets the language.
  void language(String value, {String? id}) {
    _clear('language');
    _add('language', value, id: id);
  }

  /// Sets the primary identifier, of [type].
  void primaryIdentifier(String value, String id, String type) {
    _uniqueIdentifier = id;
    _add('identifier', value, id: id).refine('identifier-type', type);
  }

  /// Adds a title.
  void addTitle(String value, {String? id}) => _add('title', value, id: id);

  /// Adds a creator with [role].
  void addCreator(String value, {String role = 'aut'}) =>
      _add('creator', value).refine('role', role);

  /// Sets the publisher, description, source or rights ([name]).
  void setText(String name, String value) {
    _clear(name);
    _add(name, value);
  }

  /// Sets the publication date (already in gepub's UTC ISO 8601 form).
  void setDate(String isoDate) {
    _clear('date');
    _add('date', isoDate);
  }

  /// Sets `dcterms:modified` (UTC, `2026-01-01T00:00:00Z`).
  void lastModified(String isoDate) {
    (_metadata['meta'] ??= []).removeWhere(
      (m) => m.attributes['property'] == 'dcterms:modified',
    );
    _add('meta', isoDate).attributes['property'] = 'dcterms:modified';
  }

  /// Adds a metadata element (`subject`, or a `meta` with [id]).
  EpubMeta addMetadata(String name, String value, {String? id}) =>
      _add(name, value, id: id);

  /// Adds the file at [href] to the manifest, with [id] (default:
  /// gepub's `item_<basename>`).
  EpubItem addItem(String href, {String? id, String? mediaType}) {
    final itemId =
        id ??
        _pool.generate(
          'item_${_basenameWithoutExtension(href)}',
          withoutCount: true,
        );
    if (_pool.contains(itemId)) {
      throw StateError("id '$itemId' is already in use.");
    }
    _pool.add(itemId);
    final item = EpubItem._(itemId, href, mediaType ?? guessMediaType(href));
    _items[itemId] = item;
    return item;
  }

  /// Like [addItem], also adding the item to the spine.
  EpubItem addOrderedItem(String href, {String? id}) {
    final item = addItem(href, id: id);
    _spine.add(item.id);
    return item;
  }

  /// Adds a file to the container outside of the package (in `META-INF/`).
  void addOptionalFile(String path, String text) => _optionalFiles[path] = text;

  /// The package document.
  String packageXml() {
    if (!_oldstyleMeta.any((m) => m.attributes['name'] == 'cover')) {
      for (final item in _items.values) {
        if (item.properties?.contains('cover-image') ?? false) {
          _oldstyleMeta.add(
            EpubMeta._('meta', '', {'name': 'cover', 'content': item.id}),
          );
        }
      }
    }
    final xml = _Xml()
      ..declaration()
      ..open('package', {
        'xmlns': 'http://www.idpf.org/2007/opf',
        'version': '3.0',
        'unique-identifier': ?_uniqueIdentifier,
        if (prefixes.isNotEmpty)
          'prefix': [
            for (final MapEntry(:key, :value) in prefixes.entries)
              '$key: $value',
          ].join(' '),
      })
      ..open('metadata', {'xmlns:dc': 'http://purl.org/dc/elements/1.1/'});
    for (final list in _metadata.values) {
      for (final meta in list) {
        meta._write(xml, _pool);
      }
    }
    for (final meta in _oldstyleMeta) {
      xml.element('meta', meta.attributes);
    }
    xml
      ..close('metadata')
      ..open('manifest', const {});
    for (final item in _items.values) {
      final properties = item.properties?.toSet().join(' ');
      xml.element('item', {
        'id': item.id,
        'href': item.href,
        'media-type': item.mediaType ?? '',
        if (properties != null && properties.isNotEmpty)
          'properties': properties,
      });
    }
    xml
      ..close('manifest')
      ..open('spine', {'toc': 'ncx'});
    for (final idref in _spine) {
      xml.element('itemref', {'idref': idref});
    }
    xml
      ..close('spine')
      ..close('package');
    return xml.toString();
  }

  /// The `META-INF/container.xml` file.
  static const String containerXml =
      '<?xml version="1.0" encoding="UTF-8"?>\n'
      '<container version="1.0" '
      'xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
      '  <rootfiles>\n'
      '    <rootfile full-path="$packagePath" media-type="application/oebps-package+xml"/>\n'
      '  </rootfiles>\n'
      '</container>\n';

  /// The files of the EPUB container, by path, in the order they are
  /// zipped: `mimetype` first, then the rest sorted by path.
  Map<String, List<int>> files() {
    final entries = <String, List<int>>{
      for (final MapEntry(:key, :value) in _optionalFiles.entries)
        key: utf8.encode(value),
      'META-INF/container.xml': utf8.encode(containerXml),
      packagePath: utf8.encode(packageXml()),
      for (final item in _items.values)
        '$_contentsPrefix${item.href}': ?item.content,
    };
    final paths = entries.keys.toList()..sort(_compareBytes);
    return {
      'mimetype': utf8.encode('application/epub+zip'),
      for (final path in paths) path: entries[path]!,
    };
  }

  /// The EPUB file: [files] zipped, `mimetype` stored, the rest
  /// compressed with [deflate] when given.
  List<int> zip({List<int> Function(List<int> bytes)? deflate}) {
    final zip = ZipWriter();
    for (final MapEntry(key: path, value: bytes) in files().entries) {
      zip.add(path, bytes, deflate: path == 'mimetype' ? null : deflate);
    }
    return zip.finish();
  }
}

/// Compares paths as Ruby sorts strings (by bytes).
int _compareBytes(String a, String b) {
  final x = utf8.encode(a);
  final y = utf8.encode(b);
  for (var i = 0; i < x.length && i < y.length; i++) {
    if (x[i] != y[i]) return x[i] - y[i];
  }
  return x.length - y.length;
}

String _basenameWithoutExtension(String path) {
  final base = _basename(path);
  final ext = extname(base);
  return ext.isEmpty ? base : base.substring(0, base.length - ext.length);
}

/// XML written as Nokogiri's builder writes it (two-space indentation,
/// empty elements self-closed).
final class _Xml {
  final StringBuffer _out = StringBuffer();
  int _depth = 0;

  void declaration() => _out.write('<?xml version="1.0" encoding="utf-8"?>\n');

  void open(String name, Map<String, String> attributes) {
    _indent();
    _out.write('<$name${_attributes(attributes)}>\n');
    _depth += 1;
  }

  void close(String name) {
    _depth -= 1;
    _indent();
    _out.write('</$name>\n');
  }

  void element(String name, Map<String, String> attributes, {String? text}) {
    _indent();
    _out.write('<$name${_attributes(attributes)}');
    if (text == null || text.isEmpty) {
      _out.write('/>\n');
    } else {
      _out.write('>${_escapeText(text)}</$name>\n');
    }
  }

  void _indent() => _out.write('  ' * _depth);

  String _attributes(Map<String, String> attributes) => [
    for (final MapEntry(:key, :value) in attributes.entries)
      ' $key="${_escapeAttribute(value)}"',
  ].join();

  @override
  String toString() => _out.toString();
}

String _escapeText(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('\r', '&#13;');

String _escapeAttribute(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll('\n', '&#10;')
    .replaceAll('\r', '&#13;')
    .replaceAll('\t', '&#9;');
