/// AsciiMath and LaTeX straight to the typed MathML tree.
library;

import 'package:plain_math/src/asciimath.dart';
import 'package:plain_math/src/latex.dart';
import 'package:plain_math/src/mathml.dart';

/// [asciimath] as a MathML tree: the tree of [asciimathToMathml]'s MathML
/// (built directly).
MathNode asciimathToMath(String asciimath) => asciimathToMathTree(asciimath);

/// [tex] as a MathML tree: the tree of [latexToMathml]'s MathML (with
/// [display] and [unknown] as there).
MathNode latexToMath(
  String tex, {
  bool display = false,
  Set<String>? unknown,
}) => parseMathML(latexToMathml(tex, display: display, unknown: unknown));
