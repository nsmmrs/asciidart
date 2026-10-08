/// Test-case reduction: the smallest document (by lines) that still passes
/// a test, such as "reaches the same code" or "crashes the same way".
library;

/// Removes blank-line-separated chunks, then single lines, while [keeps]
/// holds (delta debugging: halves first, then finer slices), and returns
/// the lines that remain. [keeps] must hold for [lines] itself.
Future<List<String>> reduceLines(
  List<String> lines,
  Future<bool> Function(List<String> candidate) keeps,
) async {
  // Chunks: runs of non-blank lines with the blank lines after them.
  final chunks = <List<String>>[];
  for (final line in lines) {
    if (chunks.isEmpty ||
        (line.trim().isNotEmpty && chunks.last.last.trim().isEmpty)) {
      chunks.add([line]);
    } else {
      chunks.last.add(line);
    }
  }
  final kept = await _ddmin(
    chunks,
    (units) => keeps([for (final u in units) ...u]),
  );
  final remaining = [for (final u in kept) ...u];
  final single = await _ddmin([
    for (final l in remaining) [l],
  ], (units) => keeps([for (final u in units) ...u]));
  return [for (final u in single) ...u];
}

/// Zeller's ddmin over [units], removing complements: returns a subset
/// that still [keeps] and from which no single slice at the finest
/// granularity can be removed.
Future<List<T>> _ddmin<T>(
  List<T> units,
  Future<bool> Function(List<T>) keeps,
) async {
  var current = units;
  var n = 2;
  while (current.length >= 2) {
    final size = (current.length / n).ceil();
    var reduced = false;
    for (var start = 0; start < current.length; start += size) {
      final end = start + size > current.length ? current.length : start + size;
      final complement = [
        ...current.sublist(0, start),
        ...current.sublist(end),
      ];
      if (complement.isNotEmpty && await keeps(complement)) {
        current = complement;
        n = n > 2 ? n - 1 : 2;
        reduced = true;
        break;
      }
    }
    if (!reduced) {
      if (n >= current.length) break;
      n = n * 2 > current.length ? current.length : n * 2;
    }
  }
  if (current.length == 1 && await keeps(<T>[])) return <T>[];
  return current;
}
