/// Replaces the words of an AsciiDoc document and keeps everything else:
/// markup, punctuation, digits, whitespace, line structure, attribute and
/// macro names, targets, URLs, roles, preprocessor directives.
///
/// The rules are deliberately approximate; `verify.dart` checks each
/// sanitized document converts the same way and restores words where it
/// doesn't.
library;

import 'word_map.dart';

/// Attributes whose values are prose (author-written text).
const proseAttributes = {
  'description',
  'keywords',
  'author',
  'authors',
  'firstname',
  'lastname',
  'middlename',
  'email',
  'revremark',
  'title',
  'doctitle',
  'subject',
  'copyright',
  'orgname',
  'manmanual',
  'mansource',
  'manname',
  'manpurpose',
  'preface-title',
  'toc-title',
  'appendix-caption',
  'example-caption',
  'figure-caption',
  'table-caption',
  'chapter-signifier',
  'part-signifier',
  'section-refsig',
  'chapter-refsig',
  'appendix-refsig',
  'part-refsig',
  'untitled-label',
  'version-label',
  'last-update-label',
  'note-caption',
  'tip-caption',
  'important-caption',
  'warning-caption',
  'caution-caption',
  'index-title',
  'glossary-title',
  'bibliography-title',
  'abstract-title',
};

/// Named block attributes whose values are prose.
const proseNamedAttributes = {
  'title',
  'reftext',
  'alt',
  'caption',
  'attribution',
  'citetitle',
  'xreflabel',
  'fallback',
  'window-title',
};

/// Words kept in code: common keywords and built-ins across languages, so
/// a syntax highlighter still sees code.
const codeKeywords = {
  'if',
  'else',
  'elif',
  'elsif',
  'unless',
  'for',
  'foreach',
  'while',
  'until',
  'do',
  'done',
  'then',
  'fi',
  'esac',
  'case',
  'when',
  'switch',
  'default',
  'break',
  'continue',
  'return',
  'yield',
  'function',
  'func',
  'fn',
  'def',
  'lambda',
  'class',
  'struct',
  'enum',
  'interface',
  'trait',
  'impl',
  'type',
  'module',
  'package',
  'import',
  'export',
  'from',
  'require',
  'include',
  'use',
  'using',
  'namespace',
  'public',
  'private',
  'protected',
  'internal',
  'static',
  'final',
  'const',
  'let',
  'var',
  'val',
  'mut',
  'new',
  'delete',
  'this',
  'self',
  'super',
  'true',
  'false',
  'null',
  'nil',
  'none',
  'undefined',
  'void',
  'int',
  'long',
  'short',
  'float',
  'double',
  'char',
  'bool',
  'boolean',
  'string',
  'byte',
  'object',
  'try',
  'catch',
  'finally',
  'throw',
  'throws',
  'raise',
  'rescue',
  'ensure',
  'begin',
  'end',
  'async',
  'await',
  'and',
  'or',
  'not',
  'in',
  'is',
  'as',
  'with',
  'extends',
  'implements',
  'abstract',
  'override',
  'virtual',
  'goto',
  'print',
  'echo',
  'select',
  'insert',
  'update',
  'into',
  'values',
  'where',
  'create',
  'table',
  'drop',
  'alter',
  'join',
  'on',
  'group',
  'order',
  'by',
  'html',
  'head',
  'body',
  'div',
  'span',
  'script',
  'style',
  'xml',
  'version',
  'encoding',
  'puts',
  'println',
  'printf',
  'main',
  'local',
  'set',
  'get',
};

final class Sanitizer {
  Sanitizer(this.map, {this.restore = const {}});

  final WordMap map;

  /// Lowercased words left as they are (where replacing them changed how
  /// the document converts).
  final Set<String> restore;

  /// Lowercased words replaced so far (candidates for [restore]).
  final Set<String> replaced = {};

  String _word(String word, {Set<String>? alsoKeep}) {
    final lower = word.toLowerCase();
    if (restore.contains(lower) || (alsoKeep?.contains(lower) ?? false)) {
      return word;
    }
    final result = map[word];
    if (result != word) replaced.add(lower);
    return result;
  }

  /// The sanitized form of a markup file a document reads (SVG, docinfo
  /// HTML): text between tags changes, tags stay.
  String sanitizeMarkup(String source) =>
      source.split('\n').map(_markup).join('\n');

  /// The sanitized form of a source file a document includes (code: its
  /// keywords and tag directives stay).
  String sanitizeCode(String source) => source
      .split('\n')
      .map((line) => _verbatim(line, 'source', null))
      .join('\n');

  /// Every letter run of [text] replaced.
  String words(String text, {Set<String>? keep}) =>
      text.replaceAllMapped(wordPattern, (m) => _word(m[0]!, alsoKeep: keep));

  /// The sanitized form of [source] (line endings and every byte that isn't
  /// part of a replaced word stay).
  String sanitize(String source) {
    final lines = source.split('\n');
    final out = <String>[];
    final blocks = <_Block>[];
    String? pendingStyle;
    var inParagraphStyle = false;
    var header = 0; // 1 after the document title, while header lines follow
    var continuation = false; // an attribute value continues on the next line
    var continuationProse = false;
    for (var i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final cr = raw.endsWith('\r');
      final line = cr ? raw.substring(0, raw.length - 1) : raw;
      String emit(String s) => cr ? '$s\r' : s;
      final top = blocks.isEmpty ? null : blocks.last;

      if (continuation) {
        out.add(emit(continuationProse ? words(line) : line));
        continuation = line.endsWith(r' \') || line.endsWith(r' +\');
        continue;
      }

      // Inside verbatim blocks only the closing delimiter and directives
      // matter.
      if (top != null && top.verbatim) {
        if (line == top.delimiter) {
          blocks.removeLast();
          out.add(emit(line));
        } else if (_directive.hasMatch(line)) {
          out.add(emit(line));
        } else {
          out.add(emit(_verbatim(line, top.kind, top.language)));
        }
        continue;
      }

      if (line.trim().isEmpty) {
        inParagraphStyle = false;
        pendingStyle = null;
        if (header == 1) header = 2;
        out.add(emit(line));
        continue;
      }

      // A paragraph styled verbatim by its attribute line.
      if (inParagraphStyle) {
        out.add(emit(_verbatim(line, pendingStyle!, null)));
        continue;
      }

      if (_directive.hasMatch(line) || _tagDirective.hasMatch(line)) {
        out.add(emit(line));
        continue;
      }

      final delimiter = _delimiter(line);
      if (delimiter != null) {
        if (top != null && top.delimiter == line) {
          blocks.removeLast();
        } else {
          final (kind, language) = _blockKind(delimiter, pendingStyle, line);
          blocks.add(_Block(line, kind, language));
        }
        pendingStyle = null;
        out.add(emit(line));
        continue;
      }

      if (_attributeEntry.firstMatch(line) case final m?) {
        final name = m[1]!.replaceAll('!', '');
        final value = m[2] ?? '';
        final prose =
            proseAttributes.contains(name) || _plainValue(name, value);
        out.add(
          emit(
            '${line.substring(0, line.length - value.length)}${prose ? words(value) : value}',
          ),
        );
        continuation = value.endsWith(r' \') || value.endsWith(r' +\');
        continuationProse = prose;
        continue;
      }

      if (_anchorLine.firstMatch(line) case final m?) {
        out.add(emit('[[${_anchor(m[1]!)}]]'));
        continue;
      }

      if (_blockAttributes.firstMatch(line) case final m?) {
        final attrlist = m[1]!;
        final style = attrlist.split(',').first.trim();
        pendingStyle = _verbatimStyle(style) ? style : null;
        out.add(emit('[${_attrlist(attrlist, style)}]'));
        continue;
      }

      if (line.startsWith('//') && !line.startsWith('///')) {
        out.add(emit('//${words(line.substring(2))}'));
        continue;
      }

      if (pendingStyle != null) {
        // `[source]` and friends make the next paragraph verbatim.
        inParagraphStyle = true;
        out.add(emit(_verbatim(line, pendingStyle, null)));
        continue;
      }

      if (_title.firstMatch(line) case final m?) {
        if (m[1] == '=' && i < 3) header = 1;
        out.add(emit('${m[1]}${m[2]}${_inline(m[3]!)}'));
        continue;
      }
      if (header == 1 && !line.startsWith(':')) {
        // Author and revision lines.
        out.add(emit(_inline(line)));
        continue;
      }

      if (_blockMacro.firstMatch(line) case final m?) {
        out.add(emit('${m[1]}::${m[2]}[${_macroAttributes(m[1]!, m[3]!)}]'));
        continue;
      }

      if (_blockTitle.firstMatch(line) case final m?) {
        out.add(emit('.${_inline(m[1]!)}'));
        continue;
      }

      if (top != null && top.kind == 'table') {
        out.add(emit(_tableLine(line, top.delimiter[0])));
        continue;
      }

      if (_admonition.firstMatch(line) case final m?) {
        out.add(emit('${m[1]}${_inline(m[2]!)}'));
        continue;
      }

      if (_listItem.firstMatch(line) case final m?) {
        out.add(emit('${m[1]}${_inline(m[2]!)}'));
        continue;
      }

      if (_literalParagraph.hasMatch(line)) {
        out.add(emit(_verbatim(line, 'literal', null)));
        continue;
      }

      out.add(emit(_inline(line)));
    }
    return out.join('\n');
  }

  /// A plain custom attribute value (words and spaces only) reads as prose.
  bool _plainValue(String name, String value) =>
      value.contains(' ') &&
      _plainProse.hasMatch(value) &&
      !_builtIn.contains(name);

  String _anchor(String body) {
    final comma = body.indexOf(',');
    if (comma < 0) return words(body);
    return '${words(body.substring(0, comma))},${_inline(body.substring(comma + 1))}';
  }

  /// A block attribute list: the style, roles, options and other names
  /// stay; IDs and prose values change.
  String _attrlist(String attrlist, String style) {
    final parts = _splitAttributes(attrlist);
    final quoteLike = style == 'quote' || style == 'verse';
    return [
      for (var i = 0; i < parts.length; i++)
        _attribute(
          parts[i],
          positionalProse: quoteLike && i > 0,
          first: i == 0,
        ),
    ].join(',');
  }

  String _attribute(
    String part, {
    required bool positionalProse,
    bool first = false,
  }) {
    final eq = part.indexOf('=');
    if (eq > 0 && _attributeName.hasMatch(part.substring(0, eq).trim())) {
      final name = part.substring(0, eq).trim();
      final value = part.substring(eq + 1);
      return proseNamedAttributes.contains(name)
          ? '${part.substring(0, eq + 1)}${_inline(value)}'
          : part;
    }
    if (first) {
      // style#id.role%option: only the id is a word of the document's own.
      return part.replaceAllMapped(_shorthandId, (m) => '#${words(m[1]!)}');
    }
    return positionalProse ? _inline(part) : part;
  }

  /// The attribute list of a block or inline macro.
  String _macroAttributes(String name, String attrlist) {
    switch (name) {
      case 'include' ||
          'pass' ||
          'stem' ||
          'latexmath' ||
          'asciimath' ||
          'kbd' ||
          'toc':
        return attrlist;
    }
    final parts = _splitAttributes(attrlist);
    return [
      for (var i = 0; i < parts.length; i++)
        _attribute(
          parts[i],
          // The first positional of image/video/link/xref is its text.
          positionalProse:
              i == 0 ||
              name == 'footnote' ||
              name == 'indexterm' ||
              name == 'indexterm2',
        ),
    ].join(',');
  }

  /// A line of a PSV/DSV/CSV table: cell specifiers before `|` stay.
  String _tableLine(String line, String separator) {
    if (separator != '|' && separator != '!') return _inline(line);
    final buffer = StringBuffer();
    var start = 0;
    for (final m in RegExp(
      r'(^|[ \t])([0-9.+*<^>]*[aehlmsdv]?)' + RegExp.escape(separator),
    ).allMatches(line)) {
      buffer.write(_inline(line.substring(start, m.start)));
      buffer.write(m[0]);
      start = m.end;
    }
    buffer.write(_inline(line.substring(start)));
    return buffer.toString();
  }

  /// Verbatim content: code keeps its keywords, raw passthroughs keep their
  /// tags, math and comments' tag directives stay.
  String _verbatim(String line, String kind, String? language) {
    if (_tagDirective.hasMatch(line)) {
      return line.replaceAllMapped(
        RegExp(r'^(.*?)((?:tag|end)::\S*\[\])(.*)$'),
        (m) => '${_code(m[1]!)}${m[2]}${_code(m[3]!)}',
      );
    }
    return switch (kind) {
      'stem' || 'latexmath' || 'asciimath' => line,
      'pass' => _markup(line),
      'comment' => words(line),
      'source' || 'listing' || 'fenced' => _code(line),
      _ => _protect(line, _callout),
    };
  }

  String _code(String line) => _protect(line, _callout, keep: codeKeywords);

  /// Raw markup: text between tags changes, tags and entities stay.
  String _markup(String line) =>
      _protect(line, RegExp(r'<[^>]*>|&#?\w+;|\{[\w-]+\}'));

  /// [line] with letter runs replaced outside the spans [protected] matches.
  String _protect(String line, RegExp protected, {Set<String>? keep}) {
    final buffer = StringBuffer();
    var start = 0;
    for (final m in protected.allMatches(line)) {
      buffer.write(words(line.substring(start, m.start), keep: keep));
      buffer.write(m[0]);
      start = m.end;
    }
    buffer.write(words(line.substring(start), keep: keep));
    return buffer.toString();
  }

  /// Inline text: macros, attribute references, URLs, entities, xrefs and
  /// anchors keep their syntax; their text and IDs change.
  String _inline(String text) {
    final buffer = StringBuffer();
    var start = 0;
    for (final m in _inlineSyntax.allMatches(text)) {
      buffer.write(words(text.substring(start, m.start)));
      buffer.write(_inlineToken(m));
      start = m.end;
    }
    buffer.write(words(text.substring(start)));
    return buffer.toString();
  }

  String _inlineToken(RegExpMatch m) {
    if (m.namedGroup('macro') case final name?) {
      final target = m.namedGroup('target')!;
      final attrs = m.namedGroup('attrs')!;
      final keptTarget = switch (name) {
        'menu' || 'footnote' || 'footnoteref' || 'anchor' => words(target),
        'xref' => _xrefTarget(target),
        _ => target,
      };
      return '$name:$keptTarget[${_macroAttributes(name, attrs)}]';
    }
    if (m.namedGroup('url') case final url?) {
      final attrs = m.namedGroup('urlattrs');
      return attrs == null ? url : '$url[${_macroAttributes('link', attrs)}]';
    }
    if (m.namedGroup('xref') case final body?) {
      final comma = body.indexOf(',');
      return comma < 0
          ? '<<${_xrefTarget(body)}>>'
          : '<<${_xrefTarget(body.substring(0, comma))},${_inline(body.substring(comma + 1))}>>';
    }
    if (m.namedGroup('anchor') case final body?) return '[[${_anchor(body)}]]';
    if (m.namedGroup('shorthand') case final body?) {
      return '[${body.replaceAllMapped(_shorthandId, (x) => '#${words(x[1]!)}')}]';
    }
    if (m.namedGroup('index3') case final body?)
      return '(((${_inline(body)})))';
    if (m.namedGroup('index2') case final body?) return '((${_inline(body)}))';
    return m[0]!; // attribute references, entities, raw passthroughs
  }

  /// `file.adoc#id`: the path stays, the ID changes.
  String _xrefTarget(String target) {
    final hash = target.indexOf('#');
    if (hash < 0) return target.contains('.adoc') ? target : words(target);
    return '${target.substring(0, hash + 1)}${words(target.substring(hash + 1))}';
  }
}

final class _Block {
  _Block(this.delimiter, this.kind, this.language);

  final String delimiter;
  final String kind;
  final String? language;

  bool get verbatim => const {
    'listing',
    'literal',
    'pass',
    'comment',
    'fenced',
    'source',
    'stem',
    'latexmath',
    'asciimath',
  }.contains(kind);
}

bool _verbatimStyle(String style) {
  final name = style.split(RegExp('[#.%]')).first;
  return const {
    'source',
    'listing',
    'literal',
    'pass',
    'stem',
    'latexmath',
    'asciimath',
  }.contains(name);
}

(String, String?) _blockKind(String delimiter, String? style, String line) {
  final styleName = style?.split(RegExp('[#.%]')).first;
  return switch (delimiter) {
    '----' => (
      styleName == 'source' || styleName == null ? 'listing' : styleName,
      null,
    ),
    '....' => ('literal', null),
    '++++' => (
      styleName == 'stem' ||
              styleName == 'latexmath' ||
              styleName == 'asciimath'
          ? styleName!
          : 'pass',
      null,
    ),
    '////' => ('comment', null),
    '```' => ('fenced', line.length > 3 ? line.substring(3).trim() : null),
    '|===' || '!===' || ',===' || ':===' => ('table', null),
    _ => (
      styleName == 'pass' || styleName == 'stem' ? styleName! : 'compound',
      null,
    ),
  };
}

/// The delimiter family of [line] if it is a block delimiter line.
String? _delimiter(String line) {
  if (line.startsWith('```')) return '```';
  if (line == '--') return '--';
  final m = _delimiterLine.firstMatch(line);
  if (m == null) return null;
  final c = line[0];
  return switch (c) {
    '|' || '!' || ',' || ':' => '$c===',
    _ => c * 4,
  };
}

final _delimiterLine = RegExp(
  r'^(?:-{4,}|\.{4,}|\+{4,}|/{4,}|={4,}|\*{4,}|_{4,}|~{4,}|[|!,:]={3,})$',
);
final _directive = RegExp(r'^\\?(?:ifn?def|ifeval|endif|include)::');
final _tagDirective = RegExp(r'\b(?:tag|end)::\S*\[\]');
final _attributeEntry = RegExp(r'^:(!?[\w{][\w{}-]*!?):(?:[ \t]+(.*))?$');
final _attributeName = RegExp(r'^[\w-]+$');
final _anchorLine = RegExp(r'^\[\[([^\]]+)\]\]$');
final _blockAttributes = RegExp(r'^\[(.*)\]$');
final _title = RegExp(r'^(={1,6}|#{1,6})([ \t]+)(.*)$');
final _blockTitle = RegExp(r'^\.([^.\s].*)$');
final _blockMacro = RegExp(r'^([\w-]+)::(\S*?)\[(.*)\]$');
final _admonition = RegExp(
  r'^((?:NOTE|TIP|IMPORTANT|WARNING|CAUTION):[ \t]+)(.*)$',
);
final _listItem = RegExp(
  r'^([ \t]*(?:[*\-]+|\.+|\d+\.|[a-zA-Z]\.|[ivxIVX]+\)|<(?:\d+|\.)>)[ \t]+(?:\[[ xX*]\][ \t]+)?)(.*)$',
);
final _literalParagraph = RegExp(r'^[ \t]+\S');
final _callout = RegExp(r'<(?:\d+|\.|!--\d+--)>|\(\d+\)');
final _plainProse = RegExp(r"^[\p{L}\p{M}0-9 ,.'’!?;-]+$", unicode: true);
final _shorthandId = RegExp(r'#([\w-]+)');
const _builtIn = {
  'source-highlighter',
  'icons',
  'toc',
  'doctype',
  'backend',
  'imagesdir',
  'iconsdir',
  'stylesheet',
  'stylesdir',
  'experimental',
  'sectnums',
  'sectanchors',
  'sectlinks',
  'idprefix',
  'idseparator',
  'lang',
  'encoding',
};

final _inlineSyntax = RegExp(
  r'(?<attr>\\?\{[\w-]+(?:[:!][^}\n]*)?\})'
  r'|(?<entity>&#?\w+;)'
  r'|(?<raw>\+\+\+.*?\+\+\+|\$\$.*?\$\$)'
  r'|(?<url>(?:https?|ftp|irc|file)://[^\s\[\]<>]*)(?:\[(?<urlattrs>[^\]]*)\])?'
  r'|(?<![\w])(?<macro>link|mailto|xref|footnote|footnoteref|image|kbd|btn|menu|pass|stem|latexmath|asciimath|indexterm2?|anchor|icon|video|audio):(?<target>[^\s\[]*)\[(?<attrs>(?:\\\]|[^\]])*)\]'
  r'|<<(?<xref>[^>\n]+)>>'
  r'|\[\[(?<anchor>[^\]\n]+)\]\]'
  r'|\[(?<shorthand>[#.%][\w#.%-]*)\]'
  r'|\(\(\((?<index3>.+?)\)\)\)'
  r'|\(\((?<index2>[^)\n]+)\)\)',
);

/// Splits an attribute list on commas outside quotes.
List<String> _splitAttributes(String attrlist) {
  final parts = <String>[];
  final current = StringBuffer();
  String? quote;
  for (var i = 0; i < attrlist.length; i++) {
    final c = attrlist[i];
    if (quote != null) {
      if (c == quote && (i == 0 || attrlist[i - 1] != r'\')) quote = null;
    } else if (c == '"' || c == "'") {
      if (current.toString().trim().isEmpty || current.toString().endsWith('='))
        quote = c;
    } else if (c == ',') {
      parts.add(current.toString());
      current.clear();
      continue;
    }
    current.write(c);
  }
  parts.add(current.toString());
  return parts;
}
