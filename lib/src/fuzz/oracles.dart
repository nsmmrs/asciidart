/// What makes a conversion a finding: a crash or hang, a difference between
/// Ruby and asciidart, or an output that breaks an invariant every correct
/// conversion keeps.
library;

import 'package:xml/xml.dart';

import '../spec/conversion.dart';

/// One problem with one conversion.
final class Finding {
  const Finding(this.kind, this.detail, {this.engine});

  /// `crash`, `timeout`, `differs`, `xml`, `html-balance`, `duplicate-id`,
  /// `placeholder`, `content-lost`.
  final String kind;
  final String detail;

  /// The engine it concerns (a profile name), or null for both.
  final String? engine;

  /// What groups findings of the same bug: kind, engine and a detail key.
  String get signature => '$kind|${engine ?? '*'}|${_key(detail)}';

  static String _key(String detail) => detail
      // Generated words differ from document to document; markup stays.
      .replaceAllMapped(
        RegExp(r'(^|>)([^<]*)'),
        (m) =>
            '${m[1]}${m[2]!.replaceAll(RegExp(r'\p{L}+', unicode: true), 'w')}',
      )
      .replaceAll(RegExp(r'\d+'), 'N')
      .replaceAll(RegExp(r'"[^"]*"'), '"…"')
      .split('\n')
      .first;

  @override
  String toString() => '$kind${engine == null ? '' : ' [$engine]'}: $detail';
}

/// Findings for one engine's [outcome] of [conversion].
List<Finding> checkOutcome(
  Outcome outcome,
  Conversion conversion, {
  required String engine,
  Set<String> words = const {},
}) {
  switch (outcome) {
    case TimedOut():
      return [
        Finding('timeout', 'no result within the time limit', engine: engine),
      ];
    case Crashed(:final error, :final frame):
      return [
        Finding(
          'crash',
          '${error.split('\n').first} @ ${frame ?? '?'}',
          engine: engine,
        ),
      ];
    case Converted(:final output, :final log):
      if (output is! String) return const [];
      return [
        ...checkInvariants(
          output,
          conversion.format,
          input: conversion.input,
          log: log,
        ),
        if (words.isNotEmpty && conversion.format == Format.html5)
          ...checkContent(output, words),
      ].map((f) => Finding(f.kind, f.detail, engine: engine)).toList();
  }
}

/// Invariants of a text [output] in [format].
List<Finding> checkInvariants(
  String output,
  Format format, {
  required String input,
  List<LogEntry> log = const [],
}) {
  final findings = <Finding>[];
  // Placeholder characters Asciidoctor uses internally (passthroughs,
  // escapes) must never reach the output unless the input had them.
  for (final c in const [
    '\u0096',
    '\u0097',
    '\u0098',
    '\u0000',
    '\u0001',
    '\u0002',
    '\u0003',
    '\u0010',
  ]) {
    if (output.contains(c) && !input.contains(c)) {
      findings.add(
        Finding(
          'placeholder',
          'U+${c.codeUnitAt(0).toRadixString(16).padLeft(4, '0')} in the output',
        ),
      );
    }
  }
  switch (format) {
    case Format.docbook5 || Format.xhtml5:
      final problem = xmlProblem(output);
      if (problem != null) findings.add(Finding('xml', problem));
    case Format.html5:
      final problem = htmlBalanceProblem(output);
      if (problem != null) findings.add(Finding('html-balance', problem));
    default:
  }
  if (format == Format.html5 ||
      format == Format.xhtml5 ||
      format == Format.docbook5) {
    final attribute = format == Format.docbook5 ? 'xml:id' : 'id';
    final seen = <String>{};
    final warnedDuplicate = log.any(
      (e) =>
          e.message.contains('duplicate') ||
          e.message.contains('already in use'),
    );
    for (final m in RegExp(
      '\\s${RegExp.escape(attribute)}="([^"]*)"',
    ).allMatches(output)) {
      final id = m[1]!;
      if (id.isEmpty) {
        findings.add(const Finding('duplicate-id', 'an empty id'));
      } else if (!seen.add(id) && !warnedDuplicate) {
        findings.add(
          Finding('duplicate-id', 'id "$id" twice, without a warning'),
        );
        break;
      }
    }
  }
  return findings;
}

/// Why [output] isn't well-formed XML (wrapped, since embedded output has
/// several top-level elements), or null.
String? xmlProblem(String output) {
  final body = output
      .replaceFirst(RegExp(r'^<\?xml[^>]*\?>\s*'), '')
      .replaceFirst(RegExp(r'<!DOCTYPE[^>]*>\s*'), '');
  try {
    XmlDocument.parse(
      '<wrapper xmlns="http://docbook.org/ns/docbook" '
      'xmlns:xl="http://www.w3.org/1999/xlink" xmlns:xlink="http://www.w3.org/1999/xlink">$body</wrapper>',
    );
    return null;
  } on XmlException catch (e) {
    return e.message;
  }
}

const _voidElements = {
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'source',
  'track',
  'wbr',
  'param',
};

/// The first unbalanced tag of HTML [output], or null. Raw passthrough
/// content can't be told apart, so only Asciidoctor's own block-level
/// structure elements are checked.
String? htmlBalanceProblem(String output) {
  const checked = {
    'div',
    'table',
    'tr',
    'td',
    'th',
    'ul',
    'ol',
    'li',
    'dl',
    'dt',
    'dd',
    'blockquote',
    'pre',
    'figure',
    'section',
    'details',
    'summary',
  };
  final stack = <String>[];
  for (final m in RegExp(
    r'<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)>',
  ).allMatches(output)) {
    final name = m[2]!.toLowerCase();
    if (!checked.contains(name) || _voidElements.contains(name) || m[4] == '/')
      continue;
    if (m[1] == '/') {
      if (stack.isEmpty || stack.last != name) {
        return 'closing </$name> while ${stack.isEmpty ? 'nothing' : '<${stack.last}>'} is open';
      }
      stack.removeLast();
    } else {
      stack.add(name);
    }
  }
  return stack.isEmpty ? null : '<${stack.last}> never closed';
}

/// The generator's tracked words missing from [output].
List<Finding> checkContent(String output, Set<String> words) {
  final missing = [
    for (final w in words)
      if (!output.contains(w)) w,
  ];
  if (missing.isEmpty) return const [];
  return [
    Finding(
      'content-lost',
      '${missing.length} of ${words.length} words missing, e.g. ${missing.take(3).join(', ')}',
    ),
  ];
}

/// The difference between two engines' outputs, as a finding, or null.
Finding? compareOutputs(
  String reference,
  String other, {
  required String referenceName,
  required String otherName,
}) {
  if (reference == other) return null;
  final a = reference.split('\n');
  final b = other.split('\n');
  for (var i = 0; i < a.length || i < b.length; i++) {
    final x = i < a.length ? a[i] : '<end>';
    final y = i < b.length ? b[i] : '<end>';
    if (x != y) {
      return Finding(
        'differs',
        '$referenceName: ${_clip(x)}\n$otherName: ${_clip(y)}',
        engine: otherName,
      );
    }
  }
  return null;
}

String _clip(String s) => s.length > 160 ? '${s.substring(0, 160)}…' : s;
