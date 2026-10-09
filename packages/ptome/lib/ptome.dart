/// ptome: an AsciiDoc processor compatible with Asciidoctor 2.1.0.alpha.0.
///
/// Start with `asciidoc` (the default configuration) or a `Ptome`
/// configured with a safe mode, attributes, `Extension`s, an
/// `HtmlOverride` or `Highlighter`s:
///
/// ```dart
/// import 'package:ptome/ptome.dart';
///
/// void main() {
///   print(asciidoc.convert('Hello, *World*!'));
///
///   final doc = asciidoc.parse('= Title\n\n== Section\n\ntext');
///   for (final section in doc.descendants<Section>()) {
///     print(section.title);
///   }
/// }
/// ```
///
/// A parsed `Document` is a sealed tree of `Node`s, and its
/// `Document.diagnostics` list what was reported while parsing and
/// converting it. `package:ptome/io.dart` reads and writes files;
/// `package:ptome/cli.dart` runs the command line. `doc/api.md` in the
/// repository walks through the common uses.
library;

export 'src/api/api.dart'
    show
        Admonition,
        AdmonitionKind,
        Attributes,
        Audio,
        Author,
        Backend,
        BibliographyAnchor,
        Block,
        BlockKind,
        BlockMacro,
        BlockMacroContext,
        Button,
        Callout,
        CalloutList,
        CrossReference,
        CustomBlock,
        CustomBlockContext,
        DescriptionList,
        DescriptionListEntry,
        Diagnostic,
        DiagnosticCode,
        DiscreteHeading,
        Docinfo,
        DocinfoLocation,
        Doctype,
        Document,
        Example,
        Extension,
        FontFile,
        Footnote,
        Formatted,
        FormattedKind,
        Highlighter,
        HtmlDefaults,
        HtmlOverride,
        Icon,
        Image,
        IncludeRequest,
        IncludeResolver,
        IndexEntry,
        IndexLetter,
        IndexTerm,
        Inline,
        InlineAnchor,
        InlineContent,
        InlineImage,
        InlineMacro,
        InlineMacroContext,
        InlineStem,
        InlineText,
        Keyboard,
        LineBreak,
        Link,
        ListItem,
        Listing,
        Literal,
        Menu,
        Node,
        NoteCall,
        NoteEntry,
        Open,
        OrderedList,
        OtherBlock,
        PageBreak,
        Paragraph,
        Passthrough,
        Postprocessor,
        Preamble,
        Preprocessor,
        Ptome,
        PtomeException,
        Quote,
        SafeMode,
        Section,
        Severity,
        Sidebar,
        SourceCode,
        SourceLocation,
        Stem,
        StemNotation,
        Table,
        TableCell,
        TableColumn,
        TableOfContents,
        ThematicBreak,
        TreeProcessor,
        Unit,
        UnitBlock,
        UnitMark,
        UnorderedList,
        Verse,
        Video,
        asciidoc,
        asciidoctorVersion,
        ptomeVersion;
