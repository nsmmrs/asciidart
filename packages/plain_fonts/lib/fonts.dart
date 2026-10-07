/// fonts: TrueType and OpenType fonts in pure Dart.
///
/// Reading them (`OpenTypeFont`: metrics, character maps, outlines,
/// kerning, OpenType substitutions, the MATH table), the WOFF and WOFF2 web
/// fonts that wrap them (`decodeWebFont`), subsetting for embedding, and
/// the fonts installed on a machine (`FontIndex`: by file name, or by
/// family and style), on the Dart VM, on Node.js and given as bytes.
library;

export 'src/cff.dart' show subsetCff;
export 'src/font_files.dart'
    show
        FontFiles,
        FontFilesException,
        FontFolderEntry,
        FontPlatform,
        cacheDirectoryFor,
        fontDirectoriesFor;
export 'src/font_index.dart' show FontIndex, InstalledFont;
export 'src/opentype.dart' show FontFormatException, OpenTypeFont;
export 'src/subset.dart' show assembleFont, glyphClosure, subsetTrueType;
export 'src/woff.dart' show decodeWebFont, isWebFont;
