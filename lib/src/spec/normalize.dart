/// The few volatile parts of an output that are not the document's doing
/// (asciidart's ADR-0001: normalize narrowly, so real differences show).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

final _versionStamp = RegExp(
  '(?:Asciidoctor|Asciidart) [0-9][0-9A-Za-z.+_~-]*',
);
final _lastUpdated = RegExp(
  r'Last updated \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2} [+-]\d{4}',
);
final _manDate = RegExp(r'^(\.\\" +Date: ).*$', multiLine: true);

/// Normalizes a text output (or a log message) of a conversion whose base
/// directory was [baseDir]:
///
/// * `Asciidoctor <version>` and `Asciidart <version>` stamps (the manpage
///   generator line, which both emit even with `reproducible`),
/// * the HTML footer's `Last updated <datetime>`,
/// * the manpage `Date:` comment,
/// * the absolute base directory, which becomes `{base}`.
String normalizeText(String text, {required String baseDir}) => text
    .replaceAll(_versionStamp, 'Asciidoctor VERSION')
    .replaceAll(_lastUpdated, 'Last updated DATETIME')
    .replaceAllMapped(_manDate, (m) => '${m[1]}DATE')
    .replaceAll(baseDir, '{base}');

/// The bytes of a normalized output, text or binary.
Uint8List outputBytes(Object output, {required String baseDir}) =>
    switch (output) {
      final String text => utf8.encode(normalizeText(text, baseDir: baseDir)),
      final Uint8List bytes => bytes,
      _ => throw ArgumentError.value(output, 'output'),
    };

/// The content address of an expected output: 12 hex digits of its SHA-256.
String contentHash(List<int> bytes) =>
    sha256.convert(bytes).toString().substring(0, 12);
