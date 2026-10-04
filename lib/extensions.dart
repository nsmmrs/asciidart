/// The Asciidoctor extension API.
///
/// Register processors on a `Registry` (globally through
/// `Extensions.register`, or per document through the `extensionRegistry`
/// option) to hook into reading, parsing and conversion.
library;

export 'src/block.dart' show BlockSubs;
export 'src/extensions.dart'
    show
        BlockMacroProcessor,
        BlockMacroProcessorCallback,
        BlockProcessor,
        BlockProcessorCallback,
        DocinfoProcessor,
        DocinfoProcessorCallback,
        ExtensionGroup,
        Extensions,
        IncludeProcessor,
        IncludeProcessorCallback,
        InlineMacroProcessor,
        InlineMacroProcessorCallback,
        MacroProcessor,
        NamedProcessor,
        Postprocessor,
        PostprocessorCallback,
        Preprocessor,
        PreprocessorCallback,
        Processor,
        ProcessorConfig,
        ProcessorExtension,
        Registry,
        TreeProcessor,
        TreeProcessorCallback;
export 'src/reader.dart' show PreprocessorReader, Reader;
