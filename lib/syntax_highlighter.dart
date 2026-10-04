/// Source highlighting: the adapter interface and factory used to plug in a
/// highlighter selected by the `source-highlighter` document attribute.
library;

export 'src/highlight/highlight.dart'
    show
        CssMode,
        DocinfoLocation,
        HighlightRequest,
        HighlightResult,
        LineNumbersMode,
        SourceLexer;
export 'src/highlight/syntax_highlighter.dart'
    show
        FormatOptions,
        HighlighterOptions,
        SyntaxHighlighter,
        SyntaxHighlighterBase,
        SyntaxHighlighterDefaultFactoryProxy,
        SyntaxHighlighterFactory,
        SyntaxHighlighterFactoryFn;
