/// Rectangles and transformation matrices in a canvas's space (points, y
/// up, as in PDF).
library;

import 'dart:math' as math;

import 'package:meta/meta.dart';

/// A rectangle: its lower-left corner and its size.
@immutable
final class Rect {
  /// The rectangle from ([left], [bottom]) that is [width] by [height].
  const new(this.left, this.bottom, this.width, this.height);

  /// The rectangle with corners ([left], [bottom]) and ([right], [top]).
  const new fromEdges(double left, double bottom, double right, double top)
    : this(left, bottom, right - left, top - bottom);

  /// The left edge.
  final double left;

  /// The bottom edge.
  final double bottom;

  /// The width.
  final double width;

  /// The height.
  final double height;

  /// The right edge.
  double get right => left + width;

  /// The top edge.
  double get top => bottom + height;

  @override
  bool operator ==(Object other) =>
      other is Rect &&
      other.left == left &&
      other.bottom == bottom &&
      other.width == width &&
      other.height == height;

  @override
  int get hashCode => Object.hash(left, bottom, width, height);

  @override
  String toString() => 'Rect($left, $bottom, $width, $height)';
}

/// An affine transformation `[a b c d e f]` (ISO 32000-2, 8.3.4): a point
/// (x, y) maps to (a·x + c·y + e, b·x + d·y + f).
@immutable
final class Matrix {
  /// The matrix `[a b c d e f]`.
  const new(this.a, this.b, this.c, this.d, this.e, this.f);

  /// The identity.
  const new identity() : this(1, 0, 0, 1, 0, 0);

  /// A translation by ([x], [y]).
  const new translation(double x, double y) : this(1, 0, 0, 1, x, y);

  /// A scaling by [x] horizontally and [y] vertically.
  const new scaling(double x, double y) : this(x, 0, 0, y, 0, 0);

  /// A counterclockwise rotation by [radians].
  factory rotation(double radians) {
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return Matrix(cos, sin, -sin, cos, 0, 0);
  }

  /// The coefficient `a`.
  final double a;

  /// The coefficient `b`.
  final double b;

  /// The coefficient `c`.
  final double c;

  /// The coefficient `d`.
  final double d;

  /// The coefficient `e`.
  final double e;

  /// The coefficient `f`.
  final double f;

  /// This transformation followed by [other].
  Matrix then(Matrix other) => Matrix(
    a * other.a + b * other.c,
    a * other.b + b * other.d,
    c * other.a + d * other.c,
    c * other.b + d * other.d,
    e * other.a + f * other.c + other.e,
    e * other.b + f * other.d + other.f,
  );

  /// The point ([x], [y]) transformed.
  (double, double) apply(double x, double y) =>
      (a * x + c * y + e, b * x + d * y + f);

  @override
  bool operator ==(Object other) =>
      other is Matrix &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.e == e &&
      other.f == f;

  @override
  int get hashCode => Object.hash(a, b, c, d, e, f);

  @override
  String toString() => 'Matrix($a, $b, $c, $d, $e, $f)';
}
