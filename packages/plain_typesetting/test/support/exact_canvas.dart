// A canvas that records every call with its arguments written exactly
// (each double as its shortest round-trip form), for equivalence tests
// that compare two layouts bit for bit.
import 'package:plain_typesetting/plain_typesetting.dart';

/// [value] written exactly: doubles round-trip, glyphs, rectangles,
/// styles and lists field by field.
String exact(Object? value) => switch (value) {
  // (-0.0 writes as -0.0.)
  final double d => '$d',
  ShapedGlyph(:final id, :final text, :final advance, :final kerning) =>
    'g($id ${exact(text)} ${exact(advance)} ${exact(kerning)})',
  Rect(:final left, :final bottom, :final width, :final height) =>
    'r(${exact(left)} ${exact(bottom)} ${exact(width)} ${exact(height)})',
  Matrix(:final a, :final b, :final c, :final d, :final e, :final f) =>
    'm(${[a, b, c, d, e, f].map(exact).join(' ')})',
  final TextStyle s =>
    's(${s.font.name} ${exact(s.size)} '
        '${exact(s.characterSpacing)} ${exact(s.wordSpacing)} '
        '${exact(s.rise)} ${exact(s.horizontalScaling)} ${s.renderMode} '
        '${s.kerning} ${s.ligatures} ${s.features} ${exact(s.skew)} '
        '${exact(s.embolden)})',
  final List<Object?> list => '[${list.map(exact).join(', ')}]',
  final String text => '"$text"',
  _ => '$value',
};

/// A canvas that records each call, exactly, as a line.
final class ExactCanvas implements Canvas {
  /// What was drawn, a call a line.
  final List<String> calls = [];

  @override
  Object? noSuchMethod(Invocation invocation) {
    final named = invocation.namedArguments.entries
        .map((e) => '${e.key}: ${exact(e.value)}')
        .join(', ');
    calls.add(
      '${invocation.memberName} '
      '${invocation.positionalArguments.map(exact).join(', ')}'
      '${named.isEmpty ? '' : ' {$named}'}',
    );
    // (The advance of text and glyphs: not used by the layouts compared.)
    return invocation.memberName == #text || invocation.memberName == #glyphs
        ? 0.0
        : null;
  }
}

/// A page recording, exactly, what is drawn on it and its links.
final class ExactPage implements LayoutPage {
  /// A page that is [box].
  new(this.box);

  /// The page's extent.
  final Rect box;

  @override
  final ExactCanvas canvas = ExactCanvas();

  /// The links made.
  final List<String> links = [];

  @override
  void link(Rect rect, LinkTarget target) =>
      links.add('link ${exact(rect)} $target');
}

/// A document of [ExactPage]s, recording its anchors.
final class ExactDocument implements LayoutDocument<ExactPage> {
  /// The pages, in order.
  final List<ExactPage> pages = [];

  /// The anchors added, a line each.
  final List<String> anchors = [];

  @override
  ExactPage addPage(Rect mediaBox, {Rect? bleedBox, Rect? trimBox}) {
    final page = ExactPage(mediaBox);
    pages.add(page);
    return page;
  }

  @override
  void addAnchor(String name, ExactPage page, double left, double top) =>
      anchors.add(
        'destination $name ${pages.indexOf(page)} ${exact(left)} ${exact(top)}',
      );
}
