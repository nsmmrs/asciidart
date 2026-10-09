/// Set cover: the fewest candidates (conversions) that together reach
/// every element (line or branch arm) any of them reaches.
library;

import 'dart:typed_data';

/// Candidates and the elements each reaches, numbered `0 ..< universe`.
final class CoverProblem {
  CoverProblem(this.universe);

  final int universe;
  final List<String> ids = [];
  final List<Int32List> sets = [];
  final List<int> costs = [];
  final Map<String, int> _index = {};

  /// Adds [elements] to candidate [id] (creating it with [cost]).
  void add(String id, Iterable<int> elements, {int cost = 0}) {
    final i = _index[id];
    if (i == null) {
      _index[id] = ids.length;
      ids.add(id);
      sets.add(Int32List.fromList(elements.toSet().toList()..sort()));
      costs.add(cost);
    } else {
      sets[i] = Int32List.fromList({...sets[i], ...elements}.toList()..sort());
      costs[i] = costs[i] > cost ? costs[i] : cost;
    }
  }

  int? indexOf(String id) => _index[id];

  /// Every element some candidate reaches.
  Uint8List reachable() {
    final reached = Uint8List(universe);
    for (final set in sets) {
      for (final e in set) {
        reached[e] = 1;
      }
    }
    return reached;
  }
}

/// Lazy greedy (gains only shrink, so a popped candidate whose recomputed
/// gain still tops the queue is the true best), then reverse delete
/// (drop chosen candidates, costliest first, whose elements others cover).
///
/// [forced] candidates are chosen first, whatever they add; ties in gain go
/// to the cheaper candidate.
List<int> greedyCover(CoverProblem problem, {Iterable<int> forced = const []}) {
  final covered = Uint8List(problem.universe);
  final chosen = <int>[];
  void take(int i) {
    chosen.add(i);
    for (final e in problem.sets[i]) {
      covered[e] = 1;
    }
  }

  forced.forEach(take);
  final forcedCount = chosen.length;
  int gain(int i) {
    var g = 0;
    for (final e in problem.sets[i]) {
      if (covered[e] == 0) g++;
    }
    return g;
  }

  // (gain, -cost, index), largest first.
  final queue = PriorityQueue<(int, int, int)>((a, b) {
    if (a.$1 != b.$1) return b.$1.compareTo(a.$1);
    if (a.$2 != b.$2) return b.$2.compareTo(a.$2);
    return a.$3.compareTo(b.$3);
  });
  final isForced = chosen.toSet();
  for (var i = 0; i < problem.ids.length; i++) {
    if (!isForced.contains(i)) queue.add((gain(i), -problem.costs[i], i));
  }
  while (queue.isNotEmpty) {
    final (stale, cost, i) = queue.removeFirst();
    if (stale == 0) break;
    final fresh = gain(i);
    if (fresh == 0) continue;
    if (queue.isEmpty || fresh >= queue.first.$1) {
      take(i);
    } else {
      queue.add((fresh, cost, i));
    }
  }
  // Reverse delete, never touching forced candidates.
  final count = Int32List(problem.universe);
  for (final i in chosen) {
    for (final e in problem.sets[i]) {
      count[e]++;
    }
  }
  final optional = chosen.sublist(forcedCount)
    ..sort((a, b) => problem.costs[b].compareTo(problem.costs[a]));
  final dropped = <int>{};
  for (final i in optional) {
    if (problem.sets[i].every((e) => count[e] > 1)) {
      dropped.add(i);
      for (final e in problem.sets[i]) {
        count[e]--;
      }
    }
  }
  return [
    for (final i in chosen)
      if (!dropped.contains(i)) i,
  ];
}

/// A binary heap (dart:collection has none).
final class PriorityQueue<T> {
  PriorityQueue(this._compare);

  final int Function(T, T) _compare;
  final List<T> _heap = [];

  bool get isEmpty => _heap.isEmpty;
  bool get isNotEmpty => _heap.isNotEmpty;
  T get first => _heap.first;

  void add(T value) {
    _heap.add(value);
    var i = _heap.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_compare(_heap[i], _heap[parent]) >= 0) break;
      _swap(i, parent);
      i = parent;
    }
  }

  T removeFirst() {
    final top = _heap.first;
    final last = _heap.removeLast();
    if (_heap.isNotEmpty) {
      _heap[0] = last;
      var i = 0;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < _heap.length && _compare(_heap[l], _heap[m]) < 0) m = l;
        if (r < _heap.length && _compare(_heap[r], _heap[m]) < 0) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final t = _heap[a];
    _heap[a] = _heap[b];
    _heap[b] = t;
  }
}
