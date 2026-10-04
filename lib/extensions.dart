/// The Asciidoctor extension API.
///
/// Register processors on a `Registry` (globally through
/// `Extensions.register`, or per document through the `extension_registry`
/// option) to hook into reading, parsing and conversion.
library;

export 'src/extensions.dart'
    show
        BlockMacroProcessor,
        BlockProcessor,
        BlockProcessorCallback,
        DocinfoProcessor,
        DocinfoProcessorCallback,
        DocumentProcessorDsl,
        Extension,
        ExtensionGroup,
        Extensions,
        IncludeProcessor,
        IncludeProcessorCallback,
        InlineMacroProcessor,
        MacroProcessor,
        MacroProcessorCallback,
        NamedProcessor,
        Postprocessor,
        PostprocessorCallback,
        Preprocessor,
        PreprocessorCallback,
        Processor,
        ProcessorExtension,
        Registry,
        TreeProcessor,
        TreeProcessorCallback;
export 'src/reader.dart'
    show PreprocessorReader, Reader, ReaderDocument, ReaderIncludeProcessor;
