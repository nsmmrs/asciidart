/// plain_typesetting: typesetting in pure Dart, independent of the output
/// format.
///
/// - Fonts as typesetting sees them (`Font`), and OpenType shaping
///   (`OpenTypeShaper`: cmap, single substitutions, ligatures, kerning).
/// - Paragraphs (`Paragraph`): inline content broken into lines by a
///   `LineBreaker` (Knuth-Plass, first fit), at UAX #14 opportunities and
///   a `Hyphenator`'s points, then aligned, measured and painted.
/// - Page layout (`FlowLayout`): a tree of boxes (blocks, paragraphs,
///   images, tables, columns, floats, custom content) laid out on pages
///   from `PageTemplate`s, with anchors, marks and running content.
/// - Math layout (`MathLayout`): a plain_math tree set by the OpenType
///   MATH table's rules.
///
/// All of it draws on a `Canvas` and adds pages to a `LayoutDocument`: the
/// interfaces a backend implements (plain_pdf for PDF).
library;

export 'src/canvas.dart'
    show BlendMode, Canvas, LineCap, LineJoin, TextRenderMode, TextStyle;
export 'src/color.dart' show CmykColor, Color, GrayColor, RgbColor, SpotColor;
export 'src/css_color.dart' show CssColor, parseCssColor;
export 'src/font.dart' show Font, OpenTypeShaper, OpenTypeTextFont, ShapedGlyph;
export 'src/geometry.dart' show Matrix, Rect;
export 'src/graphic.dart' show Graphic;
export 'src/layout/flow.dart'
    show
        AnchorPosition,
        AutoColumnWidth,
        BlockBox,
        Border,
        BoxAlign,
        BoxDecoration,
        BoxStyle,
        BreakBox,
        BreakKind,
        ColumnWidth,
        ColumnsBox,
        ComputedColumnWidth,
        CustomBox,
        CustomContent,
        CustomPlacement,
        DefaultPageBreaker,
        DrawingBox,
        EdgeInsets,
        FixedColumnWidth,
        FloatPlacement,
        FloatSide,
        FlowLayout,
        FractionColumnWidth,
        ImageBox,
        LayoutBox,
        LayoutResult,
        LinedContent,
        PageBreaker,
        PageInfo,
        PageSide,
        PageTemplate,
        ParagraphBox,
        SpacerBox,
        TableBorders,
        TableBox,
        TableCell,
        TableRow,
        VerticalAlign;
export 'src/layout/inline.dart'
    show
        InlineAlignment,
        InlineContent,
        InlineDecoration,
        InlineImage,
        PageReference,
        TextRun;
export 'src/layout/paragraph.dart'
    show
        BoxItem,
        ExactLineHeight,
        FirstFitLineBreaker,
        FontLineHeight,
        GlueItem,
        HyphenRepetition,
        Hyphenator,
        ImageFragment,
        ItemLineBreaker,
        KnuthPlassLineBreaker,
        Line,
        LineBreaker,
        LineFragment,
        LineHeight,
        LineItem,
        LineWidths,
        MultipleLineHeight,
        Paragraph,
        PenaltyItem,
        TextAlign,
        TextFragment,
        buildLines,
        paragraphItems;
export 'src/link.dart' show LinkTarget, NamedTarget, UriTarget;
export 'src/math_layout.dart' show MathBox, MathLayout;
export 'src/page.dart' show LayoutDocument, LayoutPage;

/// The version of plain_typesetting.
const String plainTypesettingVersion = '0.1.0-dev';
