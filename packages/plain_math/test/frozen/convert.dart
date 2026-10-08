/// A frozen copy of lib/src/convert.dart at 17001e86, over the frozen
/// converters and reader: the oracle of the equivalence tests
/// (test/equivalence_test.dart). Don't edit.
library;

import 'package:plain_math/plain_math.dart';

import 'asciimath.dart';
import 'latex.dart';
import 'mathml.dart';

export 'asciimath.dart' show frozenAsciimathToMathml;
export 'latex.dart' show frozenLatexToMathml;
export 'mathml.dart' show frozenParseMathML;

/// The frozen `asciimathToMath`.
MathNode frozenAsciimathToMath(String asciimath) =>
    frozenParseMathML(frozenAsciimathToMathml(asciimath));

/// The frozen `latexToMath`.
MathNode frozenLatexToMath(
  String tex, {
  bool display = false,
  Set<String>? unknown,
}) => frozenParseMathML(
  frozenLatexToMathml(tex, display: display, unknown: unknown),
);
