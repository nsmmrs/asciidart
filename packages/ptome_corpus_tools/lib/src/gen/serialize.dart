/// Writes a generated [Doc] as AsciiDoc.
library;

import 'model.dart';

String serialize(Doc doc) {
  final out = <String>[];
  if (doc.header case final header?) {
    out.add('= ${inlines(header.title)}');
    if (header.authors.isNotEmpty) out.add(header.authors.join('; '));
    if (header.revision case final revision?) {
      if (header.authors.isEmpty) out.add('Anon Ymous');
      out.add(revision);
    }
    for (final entry in header.attributes) {
      out.addAll(_attributeEntry(entry));
    }
    out.add('');
  }
  _blocks(doc.blocks, out);
  final text = out.join(doc.lineEnding);
  return doc.bom ? '﻿$text' : text;
}

void _blocks(List<Block> blocks, List<String> out) {
  for (var i = 0; i < blocks.length; i++) {
    if (i > 0 && (out.isEmpty || out.last.isNotEmpty)) out.add('');
    _block(blocks[i], out);
  }
}

void _meta(Meta meta, List<String> out) {
  if (meta.title case final title?) out.add('.${inlines(title)}');
  if (meta.id != null &&
      meta.style == null &&
      meta.roles.isEmpty &&
      meta.options.isEmpty &&
      meta.named.isEmpty) {
    out.add(
      meta.reftext == null
          ? '[[${meta.id}]]'
          : '[[${meta.id},${meta.reftext}]]',
    );
    return;
  }
  final first = StringBuffer(meta.style ?? '');
  if (meta.id case final id?) first.write('#$id');
  for (final role in meta.roles) {
    first.write('.$role');
  }
  for (final option in meta.options) {
    first.write('%$option');
  }
  final parts = [
    if (first.isNotEmpty) first.toString(),
    for (final MapEntry(:key, :value) in meta.named.entries) '$key="$value"',
    if (meta.reftext case final reftext?) 'reftext="$reftext"',
  ];
  if (parts.isNotEmpty) out.add('[${parts.join(',')}]');
}

void _block(Block block, List<String> out) {
  switch (block) {
    case AttributeEntry():
      out.addAll(_attributeEntry(block));
      return;
    case CommentLine(:final text):
      out.add('//$text');
      return;
    case Raw(:final lines):
      out.addAll(lines);
      return;
    case Include(:final target, :final attributes):
      out.add('include::$target[$attributes]');
      return;
    case Conditional(
      :final directive,
      :final expression,
      :final blocks,
      :final singleLine,
    ):
      if (singleLine != null) {
        out.add('$directive::$expression[$singleLine]');
        return;
      }
      out.add(
        directive == 'ifeval'
            ? 'ifeval::[$expression]'
            : '$directive::$expression[]',
      );
      _blocks(blocks, out);
      out.add('endif::[]');
      return;
    default:
  }
  _meta(block.meta, out);
  switch (block) {
    case Section():
      if (block.discrete && block.meta.style == null) out.add('[discrete]');
      final marker = (block.markdown ? '#' : '=') * (block.level + 1);
      out.add('$marker ${inlines(block.title)}');
      if (block.blocks.isNotEmpty) {
        out.add('');
        _blocks(block.blocks, out);
      }
    case Paragraph(:final lines, :final indent):
      for (final line in lines) {
        out.add('${' ' * indent}${inlines(line)}');
      }
    case Delimited():
      final open = block.kind.char * block.length;
      final close = block.kind.char * (block.closeLength ?? block.length);
      out.add(open);
      if (block.kind.verbatim) {
        out.addAll(block.lines);
      } else {
        _blocks(block.blocks, out);
      }
      if (!block.unterminated) out.add(close);
    case ListBlock():
      _list(block, out);
    case Table():
      _table(block, out);
    case Admonition(:final kind, :final content):
      final label = kind.name.toUpperCase();
      if (content is Paragraph) {
        final lines = content.lines;
        out.add('$label: ${lines.isEmpty ? '' : inlines(lines.first)}');
        for (final line in lines.skip(1)) {
          out.add(inlines(line));
        }
      } else {
        content.meta.style = label;
        _block(content, out);
      }
    case BlockMacro(:final name, :final target, :final attributes):
      out.add('$name::$target[$attributes]');
    case Break(:final page):
      out.add(page ? '<<<' : "'''");
    case AttributeEntry() ||
        CommentLine() ||
        Raw() ||
        Include() ||
        Conditional():
      break;
  }
}

List<String> _attributeEntry(AttributeEntry entry) {
  if (entry.unset) return [':${entry.name}!:'];
  final head = entry.value.isEmpty
      ? ':${entry.name}:'
      : ':${entry.name}: ${entry.value}';
  if (entry.continuation.isEmpty) return [head];
  return [
    '$head \\',
    for (var i = 0; i < entry.continuation.length; i++)
      i == entry.continuation.length - 1
          ? entry.continuation[i]
          : '${entry.continuation[i]} \\',
  ];
}

void _list(ListBlock list, List<String> out) {
  for (var i = 0; i < list.items.length; i++) {
    final item = list.items[i];
    final text = inlines(item.text);
    switch (list.kind) {
      case ListKind.unordered:
        out.add('${item.marker ?? '*' * list.depth} $text');
      case ListKind.checklist:
        out.add(
          '${'*' * list.depth} [${item.checked ?? false ? 'x' : ' '}] $text',
        );
      case ListKind.ordered:
        out.add('${item.marker ?? '.' * list.depth} $text');
      case ListKind.callout:
        out.add('${item.marker ?? '<${i + 1}>'} $text');
      case ListKind.description || ListKind.qanda || ListKind.horizontal:
        final term = inlines(item.term ?? const []);
        out.add(
          text.isEmpty
              ? '$term${list.separator}'
              : '$term${list.separator} $text',
        );
    }
    for (final attached in item.attached) {
      out.add('+');
      _block(attached, out);
    }
    for (final nested in item.nested) {
      _block(nested, out);
    }
  }
}

void _table(Table table, List<String> out) {
  final sep =
      table.separator ??
      switch (table.format) {
        TableFormat.psv => table.nested ? '!' : '|',
        TableFormat.csv => ',',
        TableFormat.dsv => ':',
        TableFormat.tsv => '\t',
      };
  final delimiter = switch (table.format) {
    TableFormat.psv => table.nested ? '!===' : '|===',
    TableFormat.csv => ',===',
    TableFormat.dsv => ':===',
    TableFormat.tsv => '|===',
  };
  out.add(delimiter);
  for (var r = 0; r < table.rows.length; r++) {
    final row = table.rows[r];
    if (table.format == TableFormat.psv) {
      out.add(
        [
          for (final cell in row)
            if (cell.blocks case final blocks?)
              '${cell.spec}a$sep${_nestedBlocks(blocks)}'
            else
              '${cell.spec}$sep${inlines(cell.content)}',
        ].join(' '),
      );
    } else {
      out.add([for (final cell in row) inlines(cell.content)].join(sep));
    }
    if (r == 0 && table.header && table.format == TableFormat.psv) out.add('');
  }
  out.add(delimiter);
}

String _nestedBlocks(List<Block> blocks) {
  final lines = <String>[];
  _blocks(blocks, lines);
  return lines.join('\n');
}

/// Inline content as AsciiDoc text.
String inlines(List<Inline> content) {
  final out = StringBuffer();
  for (final inline in content) {
    out.write(_inline(inline));
  }
  return out.toString();
}

String _inline(Inline inline) => switch (inline) {
  Text(:final text) => text,
  Symbol(:final text) => text,
  Formatted(
    :final mark,
    :final children,
    :final constrained,
    :final role,
    :final unbalanced,
  ) =>
    () {
      final m =
          constrained || mark == Mark.superscript || mark == Mark.subscript
          ? mark.char
          : mark.char * 2;
      return '${role == null ? '' : '[.$role]'}$m${inlines(children)}${unbalanced ? '' : m}';
    }(),
  Passthrough(:final kind, :final text) => switch (kind) {
    'pass' => 'pass:[$text]',
    'passq' => 'pass:q[$text]',
    _ => '$kind$text$kind',
  },
  AttributeReference(:final name, :final escaped) =>
    '${escaped ? r'\' : ''}{$name}',
  Macro(:final name, :final target, :final attributes) =>
    name.contains('://') || name.endsWith(':')
        ? '$name$target[$attributes]'
        : '$name:$target[$attributes]',
  Xref(:final target, :final text) =>
    text == null ? '<<$target>>' : '<<$target,${inlines(text)}>>',
  InlineAnchor(:final id, :final reftext) =>
    reftext == null ? '[[$id]]' : '[[$id,$reftext]]',
  IndexTerm(:final terms, :final visible) =>
    visible ? '((${terms.first}))' : '(((${terms.join(', ')})))',
};
