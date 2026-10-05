/// The inline tree: the elements the substitutions find, nested, with the
/// text between them, while the converted text stays as it was.
library;

import 'package:asciidart/src/internal.dart';
import 'package:test/test.dart';

/// The first block of [source], parsed.
Block firstBlock(String source) =>
    load(
          source,
          options: const AsciidoctorOptions(safe: SafeMode.safe),
        ).blocks.first
        as Block;

/// [content] as a compact string: text as is, elements as
/// `kind(children)` (or `kind` without children).
String shape(List<InlineContent> content) => [
  for (final item in content)
    switch (item) {
      InlineText(:final text) => text,
      InlineElement(:final node, :final children) =>
        '${node.type ?? node.contextName}'
            '${children.isEmpty ? '' : '(${shape(children)})'}',
    },
].join('|');

/// The tree of [source]'s first block, after checking that the elements'
/// output and the text between them make up the converted text.
List<InlineContent> treeOf(String source) {
  final block = firstBlock(source);
  final text = block.lines.join('\n');
  final expected = applySubs(block, text, block.subs);
  final tree = applySubsTree(firstBlock(source), text, block.subs);
  String flatten(List<InlineContent> content) => [
    for (final item in content)
      switch (item) {
        InlineText(:final text) => text,
        InlineElement(:final output) => output,
      },
  ].join();
  expect(flatten(tree), expected);
  return tree;
}

void main() {
  test('formatted text, with the text around it', () {
    expect(shape(treeOf('Hello *World*!')), 'Hello |strong(World)|!');
  });

  test('elements nest: a link inside strong text, emphasis in the link', () {
    expect(
      shape(treeOf('*see https://example.org[the _site_] now*')),
      'strong(see |link(the |emphasis(site))| now)',
    );
  });

  test("later substitutions apply inside an element's text", () {
    expect(shape(treeOf('*a -- b*')), 'strong(a&#8201;&#8212;&#8201;b)');
  });

  test('elements without text are leaves', () {
    expect(
      shape(treeOf('A footnote:[note] and image:a.png[] here.')),
      'A |footnote| and |image| here.',
    );
  });

  test('a hard line break holds the text of its line', () {
    expect(
      shape(treeOf('one *two* +\nthree')),
      'line(one |strong(two))|\nthree',
    );
  });

  test('passthroughs are text', () {
    expect(shape(treeOf('a +*b*+ c')), 'a *b* c');
  });

  test('the converted text is unchanged by tracking', () {
    for (final source in [
      'x *a*_b_ "`*q*`" `m` #h# ^s^ ~t~ (C) --',
      '<<sec,*Section*>> and https://a.b/_c_[d] mailto:x@y.z[]',
      'kbd:[Ctrl+C] btn:[OK] menu:File[Save] ((term)) (((concealed)))',
      'pass:q[*x*] +++<b>raw</b>+++ footnote:id[text] footnote:id[]',
    ]) {
      treeOf(':experimental:\n\n$source');
    }
  });
}
