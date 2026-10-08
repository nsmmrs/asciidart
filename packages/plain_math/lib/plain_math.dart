/// plain_math: math notations to MathML in pure Dart.
///
/// - AsciiMath to MathML, byte for byte as the `asciimath` Ruby gem 2.0.6
///   writes it (`asciimathToMathml`).
/// - LaTeX math (the set KaTeX and MathJax have in common) to MathML
///   (`latexToMathml`).
/// - A typed tree of MathML Presentation markup (`MathNode` and its kinds),
///   read from any MathML text (`parseMathML`) or straight from either
///   notation (`asciimathToMath`, `latexToMath`), for layout engines.
library;

export 'src/asciimath.dart' show asciimathToMathml;
export 'src/convert.dart' show asciimathToMath, latexToMath;
export 'src/latex.dart' show latexToMathml;
export 'src/mathml.dart'
    show
        MathEnclose,
        MathFraction,
        MathMLException,
        MathNode,
        MathRadical,
        MathRow,
        MathScripts,
        MathSpace,
        MathStyled,
        MathTable,
        MathToken,
        MathTokenKind,
        MathUnderOver,
        parseMathML;
