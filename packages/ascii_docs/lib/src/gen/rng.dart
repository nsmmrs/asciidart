/// A small, fast, seedable PRNG (SplitMix64 over 32-bit halves, so it
/// behaves the same on the VM and in JavaScript), with the helpers the
/// generator uses.
library;

final class Rng {
  Rng(int seed) : _hi = (seed >> 32) & 0xFFFFFFFF, _lo = seed & 0xFFFFFFFF;

  int _hi;
  int _lo;

  /// The next 32 random bits (an xorshift64 step).
  int next32() {
    var hi = _hi;
    var lo = _lo;
    // x ^= x << 13
    hi ^= ((hi << 13) | (lo >>> 19)) & 0xFFFFFFFF;
    lo ^= (lo << 13) & 0xFFFFFFFF;
    // x ^= x >> 7
    lo ^= ((lo >>> 7) | (hi << 25)) & 0xFFFFFFFF;
    hi ^= hi >>> 7;
    // x ^= x << 17
    hi ^= ((hi << 17) | (lo >>> 15)) & 0xFFFFFFFF;
    lo ^= (lo << 17) & 0xFFFFFFFF;
    if (hi == 0 && lo == 0) lo = 0x9E3779B9;
    _hi = hi;
    _lo = lo;
    return (hi ^ lo) & 0xFFFFFFFF;
  }

  /// A uniform integer in `[0, n)`.
  int below(int n) {
    if (n <= 1) return 0;
    return next32() % n;
  }

  /// A uniform integer in `[min, max]`.
  int between(int min, int max) => min + below(max - min + 1);

  /// True with probability [p].
  bool chance(double p) => next32() < p * 0x100000000;

  T pick<T>(List<T> items) => items[below(items.length)];

  /// One of [weights]' keys, with probability proportional to its weight.
  T weighted<T>(Map<T, int> weights) {
    var total = 0;
    for (final w in weights.values) {
      total += w;
    }
    var n = below(total);
    for (final MapEntry(:key, :value) in weights.entries) {
      if (n < value) return key;
      n -= value;
    }
    return weights.keys.last;
  }

  /// A geometric count: usually small, sometimes large.
  int count({double mean = 2, int max = 64}) {
    var n = 0;
    final p = 1 / (mean + 1);
    while (n < max && !chance(p)) {
      n++;
    }
    return n;
  }

  /// An independent generator derived from this one.
  Rng fork() => Rng(next32() << 20 ^ next32());
}
