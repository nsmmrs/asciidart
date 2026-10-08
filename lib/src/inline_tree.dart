/// The inline tree: the inline elements the substitutions find in a text,
/// with what is between them.
///
/// Asciidoctor's substitutions convert each inline element the moment
/// they find it and splice its output into the text, where later
/// substitutions see the output and may rewrite it: a later pass applies
/// to the text of formatted text or of a link inside its markup, and the
/// characters of the markup decide whether a later pattern matches next to
/// it. So the output cannot be rebuilt from the elements alone without
/// changing it; it is the text as the substitutions leave it.
///
/// What a tracking run ([InlineRun.track]) adds is where each element is:
/// every replacement the substitutions make in the text records where the
/// output of an element it found goes and moves the positions of the
/// elements found before, so at the end each element is a range of the
/// text (with, for formatted text and links, the range of its own text in
/// it). Those ranges nest into the tree; the text is unchanged.
library;

import 'package:ptome/src/converter.dart' show BuiltInConverter;
import 'package:ptome/src/inline.dart';

/// A piece of inline content: text, or an element.
sealed class InlineContent {
  /// Creates a piece of content.
  const new();
}

/// Text between inline elements, as converted (special characters
/// escaped, replacements applied).
final class InlineText extends InlineContent {
  /// Creates text.
  const new(this.text);

  /// The converted text.
  final String text;
}

/// An inline element and what is inside it.
final class InlineElement extends InlineContent {
  /// Creates an element.
  const new(this.node, this.output, this.children);

  /// The element.
  final Inline node;

  /// The element's output, as in the converted text.
  final String output;

  /// The content of the element's text (formatted text, a link's text);
  /// empty for elements without text.
  final List<InlineContent> children;
}

/// An element found by a tracking run, and where it is.
final class _Span {
  new(this.node, this.start, this.end, [this.textStart, this.textEnd]);

  final Inline node;
  int start;
  int end;

  /// Where the element's text is in its output, for elements whose output
  /// is their text with markup around it.
  int? textStart;
  int? textEnd;

  bool lost = false;
}

/// One element found while a callback computed a replacement: its output,
/// and where its text is in the output, if it is there.
typedef _Emission = ({Inline node, String output, String? text, int? textAt});

/// Stands in for an element's text to find where the text goes.
const String _textMarker = '\uE000';

/// One replacement made by a tracking run.
final class _Edit {
  new(
    this.start,
    this.end,
    this.newStart,
    this.replacement,
    this.matched,
    this.emissions,
  );

  final int start;
  final int end;
  final int newStart;
  final String replacement;
  final String matched;
  final List<_Emission> emissions;

  int get delta => replacement.length - (end - start);
}

/// A substitution run that tracks the elements it finds.
///
/// The substitutions call [emit] for each element they find and [replace]
/// for each replacement they make in the text being substituted; outside a
/// tracking run (when converting), both do only what the substitutions did
/// before.
final class InlineRun {
  new _(this._subject);

  static InlineRun? _current;

  String _subject;
  final List<_Span> _spans = [];
  List<_Emission>? _emissions;

  /// Runs [body] (substitutions applied to [text]) tracking the elements
  /// it finds, and returns the text it returns with the tree of its
  /// elements.
  static (String, List<InlineContent>) track(
    String text,
    String Function() body,
  ) {
    final outer = _current;
    final run = _current = InlineRun._(text);
    try {
      final result = body();
      return (result, run._tree(result));
    } finally {
      _current = outer;
    }
  }

  /// The output of [node], recorded as an element of the replacement being
  /// computed (in a tracking run).
  static String emit(Inline node) {
    final output = node.convert();
    _current?._emissions?.add((
      node: node,
      output: output,
      text: node.text,
      textAt: _textAt(node, output),
    ));
    return output;
  }

  /// Where [node]'s text is in its [output], for the elements whose markup
  /// goes around their text (formatted text, a link with text, a line
  /// break, a button, a visible index term).
  ///
  /// The markup is found by converting again with a marker as the text,
  /// which only the built-in converters, which convert these elements
  /// without side effects, are asked to do.
  static int? _textAt(Inline node, String output) {
    final text = node.text;
    if (text == null || node.converter is! BuiltInConverter) return null;
    final wraps = switch (node.context) {
      .quoted || .lineBreak || .button => true,
      .anchor => node.type == 'link' || node.type == 'xref',
      .indexterm => node.type == 'visible',
      _ => false,
    };
    if (!wraps) return null;
    node.text = _textMarker;
    final markup = node.convert();
    node.text = text;
    final at = markup.indexOf(_textMarker);
    if (at == -1 || markup.indexOf(_textMarker, at + 1) != -1) return null;
    return '${markup.substring(0, at)}$text${markup.substring(at + 1)}' ==
            output
        ? at
        : null;
  }

  /// [text] with the matches of [pattern] replaced by [replacement]'s
  /// results, as [String.replaceAllMapped]; in a tracking run, when [text]
  /// is the text being substituted, the elements' positions follow.
  static String replace(
    String text,
    Pattern pattern,
    String Function(Match match) replacement, {
    bool first = false,
  }) {
    final run = _current;
    if (run == null || !identical(text, run._subject)) {
      return first
          ? text.replaceFirstMapped(pattern, replacement)
          : text.replaceAllMapped(pattern, replacement);
    }
    return run._replace(text, pattern, replacement, first: first);
  }

  /// Records that the substitutions moved on to [text], the result of a
  /// step that did not go through [replace]; elements are kept only if
  /// the text is unchanged.
  static void advance(String text) {
    final run = _current;
    if (run == null || identical(text, run._subject)) return;
    if (text != run._subject) {
      for (final span in run._spans) {
        span.lost = true;
      }
    }
    run._subject = text;
  }

  String _replace(
    String text,
    Pattern pattern,
    String Function(Match match) replacement, {
    required bool first,
  }) {
    final out = StringBuffer();
    final edits = <_Edit>[];
    var at = 0;
    final outer = _emissions;
    try {
      for (final match in pattern.allMatches(text)) {
        out.write(text.substring(at, match.start));
        final emissions = _emissions = [];
        final value = replacement(match);
        edits.add(
          _Edit(
            match.start,
            match.end,
            out.length,
            value,
            match[0]!,
            emissions,
          ),
        );
        out.write(value);
        at = match.end;
        if (first) break;
      }
    } finally {
      _emissions = outer;
    }
    if (edits.isEmpty) return text;
    out.write(text.substring(at));
    final result = out.toString();
    _move(edits);
    _subject = result;
    return result;
  }

  /// Moves the elements' positions through [edits] and adds the elements
  /// the edits found.
  void _move(List<_Edit> edits) {
    for (final span in _spans) {
      if (span.lost) continue;
      final start = _map(edits, span.start, isEnd: false);
      final end = _map(edits, span.end, isEnd: true);
      if (start == null || end == null) {
        span.lost = true;
        continue;
      }
      span
        ..start = start
        ..end = end;
      if (span.textStart case final textStart?) {
        final newTextStart = _map(edits, textStart, isEnd: false);
        final newTextEnd = _map(edits, span.textEnd!, isEnd: true);
        if (newTextStart == null || newTextEnd == null) {
          span.lost = true;
          continue;
        }
        span
          ..textStart = newTextStart
          ..textEnd = newTextEnd;
      }
    }
    for (final edit in edits) {
      var from = 0;
      for (final emission in edit.emissions) {
        final at = edit.replacement.indexOf(emission.output, from);
        if (at == -1) continue;
        from = at + emission.output.length;
        final start = edit.newStart + at;
        final end = start + emission.output.length;
        final textAt = emission.textAt;
        _spans.add(
          textAt == null
              ? _Span(emission.node, start, end)
              : _Span(
                  emission.node,
                  start,
                  end,
                  start + textAt,
                  start + textAt + emission.text!.length,
                ),
        );
      }
    }
  }

  /// Where position [at] of the text before [edits] is after them, or
  /// `null` if an edit replaced the text around it and did not keep it.
  ///
  /// A position inside a replaced match survives when the match was an
  /// element's text kept in the element's output (the text of formatted
  /// text, of a link), which is how elements end up inside others.
  int? _map(List<_Edit> edits, int at, {required bool isEnd}) {
    var delta = 0;
    for (final edit in edits) {
      final inside = isEnd
          ? at > edit.start && at < edit.end
          : at >= edit.start && at < edit.end;
      if (inside) return _mapInside(edit, at);
      if (isEnd ? at <= edit.start : at < edit.start) return at + delta;
      delta += edit.delta;
    }
    return at + delta;
  }

  int? _mapInside(_Edit edit, int at) {
    final offset = at - edit.start;
    for (final emission in edit.emissions) {
      final text = emission.text;
      final inOutput = emission.textAt;
      if (text == null || text.isEmpty || inOutput == null) continue;
      final inMatch = edit.matched.lastIndexOf(text);
      if (inMatch == -1 || offset < inMatch || offset > inMatch + text.length) {
        continue;
      }
      final outputAt = edit.replacement.indexOf(emission.output);
      if (outputAt == -1) continue;
      return edit.newStart + outputAt + inOutput + (offset - inMatch);
    }
    return null;
  }

  /// The tree of the elements in [text] (the text the run returned).
  List<InlineContent> _tree(String text) {
    advance(text);
    final spans = [
      for (final span in _spans)
        if (!span.lost && span.start <= span.end && span.end <= text.length)
          span,
    ]..sort((a, b) => a.start != b.start ? a.start - b.start : b.end - a.end);
    return _content(text, spans, 0, text.length);
  }

  /// The content of [text] from [from] to [to]: the [spans] in that range
  /// that no other span in it contains, and the text between them.
  List<InlineContent> _content(
    String text,
    List<_Span> spans,
    int from,
    int to,
  ) {
    final result = <InlineContent>[];
    var at = from;
    for (var i = 0; i < spans.length; i++) {
      final span = spans[i];
      if (span.start < at || span.end > to) continue;
      if (span.start > at) {
        result.add(InlineText(text.substring(at, span.start)));
      }
      final textStart = span.textStart;
      final textEnd = span.textEnd;
      final inner = [
        for (final other in spans.skip(i + 1))
          if (other.start >= span.start && other.end <= span.end) other,
      ];
      result.add(
        InlineElement(
          span.node,
          text.substring(span.start, span.end),
          textStart != null &&
                  textEnd != null &&
                  textStart >= span.start &&
                  textEnd <= span.end &&
                  textStart <= textEnd
              ? _content(text, inner, textStart, textEnd)
              : const [],
        ),
      );
      at = span.end;
    }
    if (at < to) result.add(InlineText(text.substring(at, to)));
    return result;
  }
}
