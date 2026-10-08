/// plain_pdf: a pure-Dart PDF library written from ISO 32000.
///
/// The object layer: the PDF object model (`PdfObject` and its kinds) and a
/// `PdfWriter` that writes a file with cross-reference tables or streams
/// (compressed by the plain_compression package). Fonts (`PdfFont`, read by the
/// plain_fonts package) and images (`PdfImage`). The drawing layer: a
/// `PdfDocument` of pages drawn on `PdfCanvas`es, with links, destinations,
/// outlines and page labels. The canvas, pages and fonts implement
/// plain_typesetting's interfaces, so its layouts make PDF pages.
library;

export 'src/drawing/canvas.dart'
    show PdfCanvas, PdfForm, SoftMaskKind, TransparencyGroup, pdfCanvasOf;
export 'src/drawing/document.dart'
    show
        DestinationTarget,
        FitDestination,
        FitHeightDestination,
        FitWidthDestination,
        PageLabel,
        PageMode,
        PageNumberStyle,
        PdfDestination,
        PdfDocument,
        PdfOutlineItem,
        PdfOutputIntent,
        PdfPage,
        StreamPayload,
        XyzDestination,
        encodeStream;
export 'src/drawing/shading.dart'
    show AxialShading, GradientStop, PdfShading, RadialShading;
export 'src/fonts/fonts.dart' show EmbeddedFont, PdfFont, StandardFont;
export 'src/images/images.dart'
    show
        ImageFormatException,
        JpegImage,
        PdfImage,
        PngColorType,
        PngImage,
        PngPayload;
export 'src/objects.dart'
    show
        PdfArray,
        PdfBool,
        PdfDict,
        PdfInt,
        PdfName,
        PdfNull,
        PdfObject,
        PdfReal,
        PdfRef,
        PdfStream,
        PdfString,
        formatNumber,
        pdfDocEncode;
export 'src/reader/reader.dart' show ImportedPage, PdfFile, PdfFormatException;
export 'src/svg/path.dart'
    show
        CloseSegment,
        CubicSegment,
        LineSegment,
        MoveSegment,
        PathSegment,
        SvgPath;
export 'src/svg/svg.dart' show SvgFontResolver, SvgImage, SvgImageResolver;
export 'src/writer.dart'
    show PdfInfo, PdfWriter, PdfWriterOptions, ZlibCodec, pdfDate;

/// The version of plain_pdf.
const String plainPdfVersion = '0.1.0-dev';
