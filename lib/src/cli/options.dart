/// Command-line option parsing for the Dart port of Asciidoctor.
///
/// Port of `lib/asciidoctor/cli/options.rb` (`Asciidoctor::Cli::Options`).
///
/// ## Parser choice
///
/// Ruby configures its stdlib `OptionParser` here. The Dart port hand-rolls an
/// equivalent parser instead of using `package:args` (already in
/// `pubspec.yaml`), because `package:args` cannot express the behaviors this
/// port must preserve: options with optional arguments (`-h/--help [TOPIC]`),
/// unambiguous-prefix completion of long options (`--back`) and of
/// enumerated values (`--failure-level=e`, `-d art`), in-order short-circuit
/// (`-h`/`-V` return before a later invalid option is examined), order
/// dependence (`-q -v` vs `-v -q`), and Ruby's exact error strings. No new
/// dependency is added.
///
/// ## Deliberate divergences from `options.rb`
///
/// - [CliOptions.parse] returns `null` on success and an `int` exit code on
///   early exit or error, instead of returning the options object or an exit
///   code. Ruby callers distinguish with `Integer === result`; Dart callers
///   check for `null`.
/// - [CliOptions.parse] does not mutate the [List] it is given. Ruby's
///   `parse!` removes the parsed switches from the argument array; no caller
///   or test depends on that.
/// - `-I/--load-path` values are recorded in [CliOptions.loadPaths] but are
///   not pushed anywhere: Dart has no `$LOAD_PATH`.
/// - Every `-r/--require` fails with an
///   `asciidoctor: FAILED: '...' could not be loaded` message, exactly as
///   Ruby reports an unloadable library, because Dart cannot load libraries
///   at runtime. With `--trace`, Ruby re-raises the `LoadError`; the Dart
///   port throws [UnsupportedError] instead.
/// - `-T/--template-dir` is accepted and recorded without requiring the
///   `tilt` gem (Ruby-only). `-E/--template-engine` records any name
///   untouched (Ruby parity); the name is validated when templates engage
///   during conversion (only `mustache` + `dart` exist, per ADR-0002 T1),
///   and an unknown engine fails like Ruby's missing-engine error (see
///   `template_loader.dart`). Mustache rendering itself is template wave A.
/// - The `manpage`/`syntax` help topics resolve `ROOT_DIR`-relative files by
///   searching upward from the current working directory for a checkout
///   containing them (Ruby joins the compile-time `ROOT_DIR`). The
///   `ASCIIDOCTOR_MANPAGE_PATH` override and the `man -w` fallback keep
///   Ruby's precedence and messages.
/// - Ruby suggests near-miss spellings for some invalid long options
///   (`Did you mean? ...`); that suggestion engine is Ruby-version dependent
///   and is not ported. The stable `asciidoctor: invalid option: ...` first
///   line is preserved.
/// - Input readability is approximated with permission bits
///   (`mode & 0o444`, i.e. `0x124`) instead of an access check, so a
///   superuser may see `is not readable` where Ruby would proceed. Character
///   and block device nodes (e.g. `/dev/null`) report as `is missing` because
///   `dart:io` cannot distinguish them from absent paths (`File.stat` in Ruby
///   reports their `ftype`).
/// - Glob expansion supports `*`, `?`, `[...]` and `**`. Brace expansion
///   (`{a,b}`) is not supported; such patterns fall back to the
///   missing-file path. (Shells normally expand braces before the program
///   runs, so this rarely matters.)
/// - Ruby manipulates the `$VERBOSE` flag while parsing; Dart has no
///   equivalent and ignores it.
/// - The `Runtime Environment` line in [CliOptions.printVersion] reports the
///   Dart VM version; the encoding quadruplet is always UTF-8.
library;

import 'dart:convert';
import 'dart:io'
    show
        Directory,
        File,
        FileSystemEntity,
        FileSystemEntityType,
        Platform,
        Process,
        gzip,
        stderr,
        stdout;

import 'package:asciidoctor/src/abstract_node.dart';
import 'package:asciidoctor/src/cli/help_topics.g.dart';
import 'package:asciidoctor/src/logging.dart';
import 'package:asciidoctor/src/version.dart';

/// The CLI usage text, byte-identical to Ruby's `OptionParser#to_s` output
/// for this option set (captured from the `options.rb` oracle; the safe
/// mode names interpolate to `unsafe, safe, server, secure`).
const String usageText = r'''
Usage: asciidoctor [OPTION]... FILE...
Convert the AsciiDoc input FILE(s) to the backend output format (e.g., HTML 5, DocBook 5, etc.)
Unless specified otherwise, the output is written to a file whose name is derived from the input file.
Application log messages are printed to STDERR.
Example: asciidoctor input.adoc

    -b, --backend BACKEND            set backend output format: [html5, xhtml5, docbook5, manpage] (default: html5)
                                     additional backends are supported via extended converters (e.g., pdf, epub3)
    -d, --doctype DOCTYPE            document type to use when converting document: [article, book, manpage, inline] (default: article)
    -e, --embedded                   suppress enclosing document structure and output an embedded document (default: false)
    -o, --out-file FILE              output file (default: based on path of input file); use - to output to STDOUT
        --safe                       set safe mode level to safe (default: unsafe)
                                     enables include directives, but prevents access to ancestor paths of source file
                                     provided for compatibility with the asciidoc command
    -S, --safe-mode SAFE_MODE        set safe mode level explicitly: [unsafe, safe, server, secure] (default: unsafe)
                                     disables potentially dangerous macros in source files, such as include::[]
        --sourcemap                  add source location information to each parsed block (default: false)
    -s, --no-header-footer           suppress enclosing document structure and output an embedded document (default: false)
    -n, --section-numbers            auto-number section titles in the HTML backend; disabled by default
        --eruby ERUBY                specify eRuby implementation to use when rendering custom ERB templates: [erb, erubi, erubis] (default: erb)
    -a, --attribute name[=value]     a document attribute to set in the form of name, name!, or name=value pair
                                     that takes precedence over the same attribute defined in the source document
                                     unless either the name or value ends in @ (i.e., name@=value or name=value@)
                                     may be specified more than once
    -T, --template-dir DIR           a directory containing custom converter templates that override the built-in converter (requires tilt gem)
                                     may be specified more than once
    -E, --template-engine NAME       template engine to use for the custom converter templates (loads gem on demand)
    -B, --base-dir DIR               base directory containing the document and resources (default: directory of source file)
    -R, --source-dir DIR             source root directory (used for calculating path in destination directory)
    -D, --destination-dir DIR        destination output directory (default: directory of source file)
    -I, --load-path DIRECTORY        add a directory to the $LOAD_PATH
                                     may be specified more than once
    -r, --require LIBRARY            require the specified library before executing the processor (using require)
                                     may be specified more than once
        --log-level LEVEL            set minimum level of log messages that get logged: [DEBUG, INFO, WARN, ERROR, FATAL] (default: WARN)
        --failure-level LEVEL        set minimum log level that yields a non-zero exit code: [INFO, WARN, ERROR, FATAL] (default: FATAL)
    -q, --quiet                      silence application log messages and script warnings (default: false)
        --trace                      include backtrace information when reporting errors (default: false)
    -v, --verbose                    show all application log messages, including DEBUG and INFO levels (default: false)
    -w, --warnings                   turn on script warnings (default: false)
    -t, --timings                    print timings report (default: false)
    -h, --help [TOPIC]               print a help message
                                     show this usage if TOPIC is not specified or recognized
                                     show an overview of the AsciiDoc syntax if TOPIC is syntax
                                     dump the Asciidoctor man page (in troff/groff format) if TOPIC is manpage
    -V, --version                    display the version and runtime environment (or -v if no other flags or arguments)
''';

/// Thrown when an abbreviated long option matches more than one option.
///
/// Port of `OptionParser::AmbiguousOption`, which `parse!` does not rescue,
/// so it propagates to the caller just like in Ruby
/// (e.g. `asciidoctor --s` crashes instead of exiting cleanly).
final class AmbiguousCliOptionException implements Exception {
  /// Creates an exception with Ruby's message (e.g. `ambiguous option: --s`).
  const new(this.message);

  /// Ruby's `OptionParser::AmbiguousOption` message text.
  final String message;

  @override
  String toString() => 'AmbiguousCliOptionException: $message';
}

/// Thrown when an explicit `=value` is attached to a flag that takes none.
///
/// Port of `OptionParser::NeedlessArgument`, which `parse!` does not rescue,
/// so it propagates to the caller just like in Ruby
/// (e.g. `asciidoctor --quiet=true` raises).
final class NeedlessCliArgumentException implements Exception {
  /// Creates an exception with Ruby's message
  /// (e.g. `needless argument: --quiet=true`).
  const new(this.message);

  /// Ruby's `OptionParser::NeedlessArgument` message text.
  final String message;

  @override
  String toString() => 'NeedlessCliArgumentException: $message';
}

/// Raised internally for values outside an option's candidate list.
///
/// Port of `OptionParser::InvalidArgument`. Caught inside [CliOptions.parse],
/// which prints `asciidoctor: <message>` plus the usage text and returns 1.
final class _InvalidCliArgument implements Exception {
  /// Creates an error with Ruby's message
  /// (e.g. `invalid argument: -d chapter`).
  const new(this.message);

  /// Ruby's `OptionParser::InvalidArgument` message text.
  final String message;

  @override
  String toString() => '_InvalidCliArgument: $message';
}

/// Raised internally for values matching more than one candidate.
///
/// Port of `OptionParser::AmbiguousArgument`. Handled exactly like
/// [_InvalidCliArgument] with an `ambiguous argument: ...` message.
final class _AmbiguousCliArgument implements Exception {
  /// Creates an error with Ruby's message
  /// (e.g. `ambiguous argument: --eruby er`).
  const new(this.message);

  /// Ruby's `OptionParser::AmbiguousArgument` message text.
  final String message;

  @override
  String toString() => '_AmbiguousCliArgument: $message';
}

/// How many arguments a command-line option consumes.
enum _Arity {
  /// The option takes no argument (a flag).
  none,

  /// The option requires an argument, attached or separate.
  required,

  /// The option takes an optional argument (`-h/--help [TOPIC]` only).
  optional,
}

/// A command-line option switch.
enum _CliOption {
  /// `-b/--backend BACKEND`.
  backend,

  /// `-d/--doctype DOCTYPE`.
  doctype,

  /// `-e/--embedded`.
  embedded,

  /// `-o/--out-file FILE`.
  outFile,

  /// `--safe`.
  safe,

  /// `-S/--safe-mode SAFE_MODE`.
  safeMode,

  /// `--sourcemap`.
  sourcemap,

  /// `-s/--no-header-footer`.
  noHeaderFooter,

  /// `-n/--section-numbers`.
  sectionNumbers,

  /// `--eruby ERUBY`.
  eruby,

  /// `-a/--attribute name[=value]`.
  attribute,

  /// `-T/--template-dir DIR`.
  templateDir,

  /// `-E/--template-engine NAME`.
  templateEngine,

  /// `-B/--base-dir DIR`.
  baseDir,

  /// `-R/--source-dir DIR`.
  sourceDir,

  /// `-D/--destination-dir DIR`.
  destinationDir,

  /// `-I/--load-path DIRECTORY`.
  loadPath,

  /// `-r/--require LIBRARY`.
  require,

  /// `--log-level LEVEL`.
  logLevel,

  /// `--failure-level LEVEL`.
  failureLevel,

  /// `-q/--quiet`.
  quiet,

  /// `--trace`.
  trace,

  /// `-v/--verbose`.
  verbose,

  /// `-w/--warnings`.
  warnings,

  /// `-t/--timings`.
  timings,

  /// `-j/--jobs N` (Dart-only extension; no Ruby analog).
  jobs,

  /// `-h/--help [TOPIC]`.
  help,

  /// `-V/--version`.
  version,
}

/// Static description of one command-line option.
class _Spec {
  /// Creates a spec for [option] with short flag [short] (or `null`), long
  /// name [long], argument [arity] and completion [allowed] values (or `null`
  /// for unrestricted arguments).
  const new(this.option, this.short, this.long, this.arity, [this.allowed]);

  /// The option identity.
  final _CliOption option;

  /// The single-character short flag, or `null` when the option has none.
  final String? short;

  /// The long option name without leading `--`.
  final String long;

  /// How many arguments the option consumes.
  final _Arity arity;

  /// Enumerated values for prefix completion (case-sensitive), or `null`
  /// when any value is accepted.
  final List<String>? allowed;
}

/// The option table, in the same order as the `opts.on` calls in
/// `options.rb`.
const List<_Spec> _specs = [
  _Spec(_CliOption.backend, 'b', 'backend', _Arity.required),
  _Spec(_CliOption.doctype, 'd', 'doctype', _Arity.required, [
    'article',
    'book',
    'manpage',
    'inline',
  ]),
  _Spec(_CliOption.embedded, 'e', 'embedded', _Arity.none),
  _Spec(_CliOption.outFile, 'o', 'out-file', _Arity.required),
  _Spec(_CliOption.safe, null, 'safe', _Arity.none),
  _Spec(_CliOption.safeMode, 'S', 'safe-mode', _Arity.required, _safeModeNames),
  _Spec(_CliOption.sourcemap, null, 'sourcemap', _Arity.none),
  _Spec(_CliOption.noHeaderFooter, 's', 'no-header-footer', _Arity.none),
  _Spec(_CliOption.sectionNumbers, 'n', 'section-numbers', _Arity.none),
  _Spec(_CliOption.eruby, null, 'eruby', _Arity.required, [
    'erb',
    'erubi',
    'erubis',
  ]),
  _Spec(_CliOption.attribute, 'a', 'attribute', _Arity.required),
  _Spec(_CliOption.templateDir, 'T', 'template-dir', _Arity.required),
  _Spec(_CliOption.templateEngine, 'E', 'template-engine', _Arity.required),
  _Spec(_CliOption.baseDir, 'B', 'base-dir', _Arity.required),
  _Spec(_CliOption.sourceDir, 'R', 'source-dir', _Arity.required),
  _Spec(_CliOption.destinationDir, 'D', 'destination-dir', _Arity.required),
  _Spec(_CliOption.loadPath, 'I', 'load-path', _Arity.required),
  _Spec(_CliOption.require, 'r', 'require', _Arity.required),
  _Spec(_CliOption.logLevel, null, 'log-level', _Arity.required, [
    'debug',
    'DEBUG',
    'info',
    'INFO',
    'warning',
    'WARNING',
    'error',
    'ERROR',
    'fatal',
    'FATAL',
  ]),
  _Spec(_CliOption.failureLevel, null, 'failure-level', _Arity.required, [
    'info',
    'INFO',
    'warning',
    'WARNING',
    'error',
    'ERROR',
    'fatal',
    'FATAL',
  ]),
  _Spec(_CliOption.quiet, 'q', 'quiet', _Arity.none),
  _Spec(_CliOption.trace, null, 'trace', _Arity.none),
  _Spec(_CliOption.verbose, 'v', 'verbose', _Arity.none),
  _Spec(_CliOption.warnings, 'w', 'warnings', _Arity.none),
  _Spec(_CliOption.timings, 't', 'timings', _Arity.none),
  _Spec(_CliOption.jobs, 'j', 'jobs', _Arity.required),
  _Spec(_CliOption.help, 'h', 'help', _Arity.optional),
  _Spec(_CliOption.version, 'V', 'version', _Arity.none),
];

/// Safe mode names in severity order. Port of `SafeMode.names`.
const List<String> _safeModeNames = ['unsafe', 'safe', 'server', 'secure'];

/// Parsed command-line options.
///
/// Port of `Asciidoctor::Cli::Options` (a `Hash` subclass in Ruby). Field
/// names mirror the Ruby keys (`input_files` becomes [inputFiles] and so on).
/// Collection fields alias the objects passed to the constructor, exactly as
/// Ruby stores the caller's objects without copying; [parse] may mutate them.
final class CliOptions {
  /// Creates an options object with the given seeds.
  ///
  /// Mirrors `Options.new`: [attributes] defaults to an empty map,
  /// [standalone] to `true`, [safe] to [SafeMode.unsafe], [verbose] to 1,
  /// [warnings] to `false`, and [failureLevel] to [Severity.fatal];
  /// [trace] and [timings] are always `false` (Ruby ignores any seed for
  /// them, as it does for the failure level); everything else defaults to
  /// `null`. [doctype] and [backend] seed `attributes['doctype']` and
  /// `attributes['backend']` when given.
  ///
  /// [templateDirs] accepts a single [String] directory, an
  /// [Iterable] of directories, or `null` (Ruby callers may seed a bare
  /// string). [logLevel] accepts a [Severity], an [int], or a [String] name
  /// (see [Severity.coerce]).
  new({
    Map<String, String>? attributes,
    this.inputFiles,
    this.outputFile,
    int? safe,
    this.standalone = true,
    Object? templateDirs,
    this.templateEngine,
    String? doctype,
    String? backend,
    this.eruby,
    this.verbose = 1,
    this.warnings = false,
    this.loadPaths,
    this.requires,
    this.baseDir,
    this.sourceDir,
    this.destinationDir,
    Object? logLevel,
    this.sourcemap,
    this.jobs = 1,
  }) : attributes = attributes ?? <String, String>{},
       safe = safe ?? SafeMode.unsafe,
       templateDirs = _normalizeTemplateDirs(templateDirs),
       logLevel = logLevel == null ? null : Severity.coerce(logLevel) {
    if (doctype != null) this.attributes!['doctype'] = doctype;
    if (backend != null) this.attributes!['backend'] = backend;
  }

  /// Document attributes from `-a/--attribute` (plus `-b`, `-d` and `-n`).
  ///
  /// Set to `null` by [parse] when no attribute was defined, mirroring
  /// Ruby's `delete :attributes`.
  Map<String, String>? attributes;

  /// Input files to convert, after glob expansion.
  List<String>? inputFiles;

  /// Output file from `-o/--out-file` (`-` means STDOUT).
  String? outputFile;

  /// Safe mode level (see [SafeMode]).
  int safe;

  /// Whether to output a standalone document (cleared by `-e` and `-s`).
  bool standalone;

  /// Template directories from `-T/--template-dir`.
  List<String>? templateDirs;

  /// Template engine name from `-E/--template-engine`.
  String? templateEngine;

  /// eRuby implementation from `--eruby`.
  String? eruby;

  /// Verbosity from `-q/--quiet` (0), default (1) or `-v/--verbose` (2).
  int verbose;

  /// Whether script warnings are enabled (`-w/--warnings`).
  bool warnings;

  /// Load paths from `-I/--load-path`.
  List<String>? loadPaths;

  /// Libraries from `-r/--require`.
  List<String>? requires;

  /// Base directory from `-B/--base-dir`.
  String? baseDir;

  /// Source directory from `-R/--source-dir`.
  String? sourceDir;

  /// Destination directory from `-D/--destination-dir`.
  String? destinationDir;

  /// Minimum logged severity from `--log-level`.
  Severity? logLevel;

  /// Minimum severity that yields a non-zero exit code
  /// (from `--failure-level`; default [Severity.fatal]).
  Severity failureLevel = Severity.fatal;

  /// Whether source location info is added (`--sourcemap`).
  bool? sourcemap;

  /// Whether backtraces are shown (`--trace`).
  bool trace = false;

  /// Whether a timings report is printed (`-t/--timings`).
  bool timings = false;

  /// Worker count from `-j/--jobs N` (default 1: sequential conversion).
  ///
  /// A Dart-only extension with no Ruby analog (hence absent from
  /// [usageText], which stays byte-identical to Ruby's help): with N > 1 the
  /// invoker converts multiple input files on a pool of worker isolates (see
  /// `Invoker.invokeAsync`). Values below 1 behave like 1; [parse] rejects
  /// them (and non-integers) with a make-style usage error instead.
  int jobs;

  /// Normalizes a [CliOptions.templateDirs] seed. See the constructor docs.
  static List<String>? _normalizeTemplateDirs(Object? value) {
    if (value == null) return null;
    if (value is String) return [value];
    if (value is List<String>) return value;
    if (value is Iterable<String>) return value.toList();
    throw ArgumentError.value(
      value,
      'templateDirs',
      'expected a String, an Iterable<String>, or null',
    );
  }

  /// Parses [args] into a fresh [CliOptions].
  ///
  /// Returns a record holding the options and the exit code (`null` on
  /// success). Port of `Options.parse!`. See [parse] for the parameters.
  static ({CliOptions options, int? exitCode}) parseArgs(
    List<String> args, {
    StringSink? out,
    StringSink? err,
    Map<String, String>? environment,
  }) {
    final options = CliOptions();
    final exitCode = options.parse(
      args,
      out: out,
      err: err,
      environment: environment,
    );
    return (options: options, exitCode: exitCode);
  }

  /// Parses [args] into this object.
  ///
  /// Port of `Options#parse!`. Returns `null` on success, or the process
  /// exit code when parsing ends early: 0 for `-h/--help` and `-V/--version`
  /// (and lone `-v`), 1 for usage and input errors. Option switches are
  /// processed strictly in order; `-h` and `-V` act (and return) before any
  /// later argument is examined, exactly as in Ruby.
  ///
  /// The [List] itself is never mutated (unlike Ruby's `parse!`).
  ///
  /// [out] and [err] receive STDOUT and STDERR output (defaulting to the
  /// process streams); [environment] supplies environment variables
  /// (defaulting to [Platform.environment]) and is consulted only for
  /// `ASCIIDOCTOR_MANPAGE_PATH`.
  ///
  /// Throws [AmbiguousCliOptionException] for abbreviated long options
  /// matching several options, [NeedlessCliArgumentException] for `=value`
  /// attached to a flag, and [UnsupportedError] when `--trace` is combined
  /// with `-r` (mirroring the errors Ruby lets propagate out of `parse!`).
  int? parse(
    List<String> args, {
    StringSink? out,
    StringSink? err,
    Map<String, String>? environment,
  }) {
    final outSink = out ?? stdout;
    final errSink = err ?? stderr;
    final env = environment ?? Platform.environment;

    final positionals = <String>[];
    var endOfOptions = false;
    var i = 0;
    while (i < args.length) {
      final token = args[i];
      if (token == '--' && !endOfOptions) {
        endOfOptions = true;
        i++;
        continue;
      }
      if (endOfOptions || !_looksLikeOption(token)) {
        positionals.add(token);
        i++;
        continue;
      }
      int? exitCode;
      if (token.startsWith('--')) {
        final step = _parseLong(token, args, i, outSink, errSink, env);
        i = step.nextIndex;
        exitCode = step.exitCode;
      } else {
        final step = _parseShortCluster(token, args, i, outSink, errSink, env);
        i = step.nextIndex;
        exitCode = step.exitCode;
      }
      if (exitCode != null) return exitCode;
    }

    if (positionals.isEmpty) {
      // `asciidoctor -v` (with nothing else) prints the version; Ruby checks
      // `verbose == 2` rather than the flag itself.
      if (verbose == 2) return printVersion(outSink);
      errSink.write(usageText);
      return 1;
    }

    final infiles = <String>[];
    // Shave off stdin so that option errors appear correctly.
    if (positionals.length == 1 && positionals[0] == '-') {
      infiles.add('-');
    } else {
      final unparsed = positionals.map((p) => "'$p'").join(', ');
      for (var file in positionals) {
        if (file.startsWith('-')) {
          // Warn, but don't panic; there may be enough to proceed.
          errSink.writeln(
            'asciidoctor: WARNING: extra arguments detected '
            '(unparsed arguments: $unparsed) '
            'or incorrect usage of stdin',
          );
        } else if (_isFile(file)) {
          infiles.add(file);
        } else {
          // NOTE only attempt to glob if file is not found.
          // Tilt backslashes in Windows paths the Ruby-friendly way.
          if (Platform.isWindows && file.contains(r'\')) {
            file = file.replaceAll(r'\', '/');
          }
          final matches = _glob(file);
          if (matches.isEmpty) {
            // NOTE if no matches, assume it's just a missing file and proceed.
            infiles.add(file);
          } else {
            infiles.addAll(matches);
          }
        }
      }
    }

    for (final file in infiles) {
      if (file == '-') continue;
      final type = FileSystemEntity.typeSync(file);
      if (type == FileSystemEntityType.directory) {
        errSink.writeln(
          'asciidoctor: FAILED: input path $file is a directory, not a file',
        );
        return 1;
      }
      if (type == FileSystemEntityType.file ||
          type == FileSystemEntityType.pipe) {
        // Permission-bit approximation of `File::Stat#readable?` (see the
        // library docs). Never open the file: opening a fifo would block.
        if ((File(file).statSync().mode & 0x124) == 0) {
          errSink.writeln(
            'asciidoctor: FAILED: input file $file is not readable',
          );
          return 1;
        }
      } else {
        errSink.writeln('asciidoctor: FAILED: input file $file is missing');
        return 1;
      }
    }

    inputFiles = infiles;

    if (attributes != null && attributes!.isEmpty) attributes = null;

    // Ruby requires the `tilt` gem here when template directories are set.
    // Dart has no tilt; the engine name is validated when templates engage
    // during conversion instead (see the library docs).

    if (loadPaths != null) {
      // Ruby unshifts the expanded paths onto $LOAD_PATH; Dart records them.
      final seen = <String>{};
      loadPaths = loadPaths!.where(seen.add).toList();
    }

    if (requires != null) {
      final seen = <String>{};
      requires = requires!.where(seen.add).toList();
      for (final path in requires!) {
        // Dart cannot load libraries at runtime (see the library docs), so
        // every require fails exactly as an unloadable library does in Ruby.
        if (trace) {
          throw UnsupportedError(
            "asciidoctor: FAILED: '$path' could not be loaded",
          );
        }
        errSink
          ..writeln("asciidoctor: FAILED: '$path' could not be loaded")
          ..writeln('  Use --trace to show backtrace');
        return 1;
      }
    }

    return null;
  }

  /// Prints the version and runtime environment to [out] (default STDOUT).
  ///
  /// Port of `Options#print_version`. Always returns 0.
  int printVersion([StringSink? out]) {
    (out ?? stdout)
      ..writeln('Asciidoctor ${Asciidoctor.version} [https://asciidoctor.org]')
      ..writeln(
        'Runtime Environment (Dart ${Platform.version}) '
        '(lc:UTF-8 fs:UTF-8 in:UTF-8 ex:UTF-8)',
      );
    return 0;
  }

  /// Handles `-h/--help [topic]`. Always returns an exit code.
  int _showHelp(
    String? topic,
    StringSink outSink,
    StringSink errSink,
    Map<String, String> env,
  ) {
    switch (topic) {
      // Use `asciidoctor -h manpage | man -l -` to view with man pager.
      case 'manpage':
        return _showManpage(outSink, errSink, env);
      case 'syntax':
        final syntaxPath = _findCheckoutFile([
          'data',
          'reference',
          'syntax.adoc',
        ]);
        if (syntaxPath != null) {
          _putsFile(outSink, syntaxPath);
        } else {
          // A standalone executable run outside the checkout has no files
          // to read; serve the embedded copy (byte-identical).
          _putsContent(outSink, HelpTopics.syntax);
        }
      default:
        outSink.write(usageText);
    }
    return 0;
  }

  /// Dumps the man page for `-h manpage`. Port of the `when 'manpage'`
  /// branch; see the library docs for the `ROOT_DIR` substitution.
  int _showManpage(
    StringSink outSink,
    StringSink errSink,
    Map<String, String> env,
  ) {
    final override = env['ASCIIDOCTOR_MANPAGE_PATH'];
    if (override != null) {
      if (File(override).existsSync()) {
        _putsManpage(outSink, override);
      } else {
        errSink.writeln(
          'asciidoctor: FAILED: manual page not found: $override',
        );
        return 1;
      }
    } else if (_findCheckoutFile(['man', 'asciidoctor.1']) case final path?) {
      _putsManpage(outSink, path);
    } else if (HelpTopics.manpage.isNotEmpty) {
      // A standalone executable run outside the checkout has no files to
      // read; serve the embedded copy (byte-identical).
      _putsContent(outSink, HelpTopics.manpage);
      return 0;
    } else {
      var resolved = '';
      try {
        final result = Process.runSync('man', ['-w', 'asciidoctor']);
        resolved = result.stdout.toString();
        if (resolved.endsWith('\n')) {
          resolved = resolved.substring(0, resolved.length - 1);
        }
      } on Exception catch (_) {
        // Ruby rescues the backtick call to ''.
      }
      if (resolved.isEmpty) {
        errSink.writeln(
          'asciidoctor: FAILED: manual page not found; '
          'try `man asciidoctor`',
        );
        return 1;
      } else if (resolved.endsWith('.gz')) {
        _putsGzipFile(outSink, resolved);
      } else {
        _putsFile(outSink, resolved);
      }
    }
    return 0;
  }

  /// Parses one `--long` token at [index]. Returns the next index to visit
  /// and the exit code when the token ends parsing early (`null` otherwise).
  ({int nextIndex, int? exitCode}) _parseLong(
    String token,
    List<String> args,
    int index,
    StringSink outSink,
    StringSink errSink,
    Map<String, String> env,
  ) {
    final body = token.substring(2);
    final equals = body.indexOf('=');
    final name = equals < 0 ? body : body.substring(0, equals);
    final attached = equals < 0 ? null : body.substring(equals + 1);
    if (name.isEmpty) {
      // Only `--=...` reaches here (`--` alone is the terminator); Ruby
      // reports the value as needless.
      throw NeedlessCliArgumentException('needless argument: $token');
    }
    final spec = _resolveLong(name, token);
    if (spec == null) {
      errSink.writeln('asciidoctor: invalid option: $token');
      outSink.write(usageText);
      return (nextIndex: index + 1, exitCode: 1);
    }
    try {
      switch (spec.arity) {
        case _Arity.none:
          if (attached != null) {
            throw NeedlessCliArgumentException('needless argument: $token');
          }
          final exitCode = _apply(spec, null, outSink, errSink, env);
          return (nextIndex: index + 1, exitCode: exitCode);
        case _Arity.optional:
          // Only `-h/--help [TOPIC]`.
          if (attached != null) {
            return (
              nextIndex: index + 1,
              exitCode: _showHelp(attached, outSink, errSink, env),
            );
          }
          String? topic;
          var nextIndex = index + 1;
          if (nextIndex < args.length &&
              _consumableAsOptionalArgument(args[nextIndex])) {
            topic = args[nextIndex];
            nextIndex++;
          }
          return (
            nextIndex: nextIndex,
            exitCode: _showHelp(topic, outSink, errSink, env),
          );
        case _Arity.required:
          if (attached != null) {
            final value = _completeValue(spec, attached, token);
            final exitCode = _apply(spec, value, outSink, errSink, env);
            return (nextIndex: index + 1, exitCode: exitCode);
          }
          // Required arguments consume the next token unconditionally, even
          // `--` or an option-looking token.
          if (index + 1 >= args.length) {
            errSink.writeln('asciidoctor: option missing argument: $token');
            outSink.write(usageText);
            return (nextIndex: index + 1, exitCode: 1);
          }
          final value = args[index + 1];
          final completed = _completeValue(spec, value, '$token $value');
          final exitCode = _apply(spec, completed, outSink, errSink, env);
          return (nextIndex: index + 2, exitCode: exitCode);
      }
    } on _InvalidCliArgument catch (e) {
      errSink.writeln('asciidoctor: ${e.message}');
      outSink.write(usageText);
      return (nextIndex: args.length, exitCode: 1);
    } on _AmbiguousCliArgument catch (e) {
      errSink.writeln('asciidoctor: ${e.message}');
      outSink.write(usageText);
      return (nextIndex: args.length, exitCode: 1);
    }
  }

  /// Parses one short-option cluster (e.g. `-ve` or `-bhtml5`) at [index].
  /// Returns the next index to visit and the exit code when the token ends
  /// parsing early (`null` otherwise).
  ({int nextIndex, int? exitCode}) _parseShortCluster(
    String token,
    List<String> args,
    int index,
    StringSink outSink,
    StringSink errSink,
    Map<String, String> env,
  ) {
    var nextIndex = index + 1;
    var j = 1;
    while (j < token.length) {
      final char = token[j];
      _Spec? spec;
      for (final candidate in _specs) {
        if (candidate.short == char) {
          spec = candidate;
          break;
        }
      }
      // Ruby reports the unconsumed remainder of the cluster.
      final rest = '-${token.substring(j)}';
      if (spec == null) {
        errSink.writeln('asciidoctor: invalid option: $rest');
        outSink.write(usageText);
        return (nextIndex: nextIndex, exitCode: 1);
      }
      final attached = token.substring(j + 1);
      try {
        switch (spec.arity) {
          case _Arity.none:
            if (attached.startsWith('=')) {
              throw NeedlessCliArgumentException(
                'needless argument: -$char$attached',
              );
            }
            final exitCode = _apply(spec, null, outSink, errSink, env);
            if (exitCode != null) {
              return (nextIndex: nextIndex, exitCode: exitCode);
            }
            j++;
          case _Arity.optional:
            // Only `-h/--help [TOPIC]`; the rest is the topic verbatim.
            if (attached.isNotEmpty) {
              return (
                nextIndex: nextIndex,
                exitCode: _showHelp(attached, outSink, errSink, env),
              );
            }
            String? topic;
            if (nextIndex < args.length &&
                _consumableAsOptionalArgument(args[nextIndex])) {
              topic = args[nextIndex];
              nextIndex++;
            }
            return (
              nextIndex: nextIndex,
              exitCode: _showHelp(topic, outSink, errSink, env),
            );
          case _Arity.required:
            if (attached.isNotEmpty) {
              // Attached values are verbatim (a leading `=` is kept).
              final value = _completeValue(spec, attached, rest);
              final exitCode = _apply(spec, value, outSink, errSink, env);
              return (nextIndex: nextIndex, exitCode: exitCode);
            }
            if (nextIndex >= args.length) {
              errSink.writeln('asciidoctor: option missing argument: -$char');
              outSink.write(usageText);
              return (nextIndex: nextIndex, exitCode: 1);
            }
            final value = args[nextIndex];
            nextIndex++;
            final completed = _completeValue(spec, value, '-$char $value');
            final exitCode = _apply(spec, completed, outSink, errSink, env);
            return (nextIndex: nextIndex, exitCode: exitCode);
        }
      } on _InvalidCliArgument catch (e) {
        errSink.writeln('asciidoctor: ${e.message}');
        outSink.write(usageText);
        return (nextIndex: args.length, exitCode: 1);
      } on _AmbiguousCliArgument catch (e) {
        errSink.writeln('asciidoctor: ${e.message}');
        outSink.write(usageText);
        return (nextIndex: args.length, exitCode: 1);
      }
    }
    return (nextIndex: nextIndex, exitCode: null);
  }

  /// Applies [spec] with [value] (`null` for flags). Returns an exit code
  /// for `-h/--help` and `-V/--version`, `null` otherwise.
  int? _apply(
    _Spec spec,
    String? value,
    StringSink outSink,
    StringSink errSink,
    Map<String, String> env,
  ) {
    switch (spec.option) {
      case _CliOption.backend:
        _attributeMap['backend'] = value!;
      case _CliOption.doctype:
        _attributeMap['doctype'] = value!;
      case _CliOption.embedded:
      case _CliOption.noHeaderFooter:
        standalone = false;
      case _CliOption.outFile:
        outputFile = value;
      case _CliOption.safe:
        safe = SafeMode.safe;
      case _CliOption.safeMode:
        safe = _safeModeValue(value!);
      case _CliOption.sourcemap:
        sourcemap = true;
      case _CliOption.sectionNumbers:
        _attributeMap['sectnums'] = '';
      case _CliOption.eruby:
        eruby = value;
      case _CliOption.attribute:
        _assignAttribute(value!);
      case _CliOption.templateDir:
        (templateDirs ??= []).add(value!);
      case _CliOption.templateEngine:
        templateEngine = value;
      case _CliOption.baseDir:
        baseDir = value;
      case _CliOption.sourceDir:
        sourceDir = value;
      case _CliOption.destinationDir:
        destinationDir = value;
      case _CliOption.loadPath:
        loadPaths ??= [];
        loadPaths!.addAll(value!.split(_pathListSeparator));
      case _CliOption.require:
        (requires ??= []).add(value!);
      case _CliOption.logLevel:
        logLevel = _severityForLevel(value!);
      case _CliOption.failureLevel:
        failureLevel = _severityForLevel(value!);
      case _CliOption.quiet:
        verbose = 0;
      case _CliOption.trace:
        trace = true;
      case _CliOption.verbose:
        verbose = 2;
      case _CliOption.warnings:
        warnings = true;
      case _CliOption.timings:
        timings = true;
      case _CliOption.jobs:
        jobs = _parseJobsValue(value!);
      case _CliOption.help:
        return _showHelp(value, outSink, errSink, env);
      case _CliOption.version:
        return printVersion(outSink);
    }
    return null;
  }

  /// The attribute map, recreating it when [parse] already nulled it.
  ///
  /// Ruby would raise `NoMethodError` on a second `parse!` call once
  /// `:attributes` was deleted; recreating the map keeps repeated parsing
  /// usable. Single-parse behavior is identical.
  Map<String, String> get _attributeMap => attributes ??= {};

  /// Assigns one `-a/--attribute` value. Port of the `-a` handler: trailing
  /// whitespace is stripped, empty values and a lone `=` are skipped, and
  /// the name splits from the value on the first `=` only.
  void _assignAttribute(String argument) {
    final attr = argument.trimRight();
    if (attr.isEmpty || attr == '=') return;
    final equals = attr.indexOf('=');
    if (equals < 0) {
      _attributeMap[attr] = '';
    } else {
      _attributeMap[attr.substring(0, equals)] = attr.substring(equals + 1);
    }
  }
}

/// Whether [token] starts option parsing (a `-` alone is the stdin pseudo
/// file, not an option).
bool _looksLikeOption(String token) => token.startsWith('-') && token != '-';

/// Whether [token] may be consumed as an optional option-argument.
///
/// Ruby only consumes the following token when it is neither `--` nor
/// option-looking; a lone `-` is consumed (as the `-h` topic it still prints
/// the usage text).
bool _consumableAsOptionalArgument(String token) =>
    token != '--' && !_looksLikeOption(token);

/// Resolves a long option [name] with Ruby's completion rules: exact match
/// first (an exact case-insensitive match beats prefix matches), then a
/// unique case-insensitive prefix match. Returns `null` for unknown names
/// and throws [AmbiguousCliOptionException] for ambiguous ones. [token] is
/// the full command-line token, used verbatim in the throw message.
_Spec? _resolveLong(String name, String token) {
  for (final spec in _specs) {
    if (spec.long == name) return spec;
  }
  final lower = name.toLowerCase();
  for (final spec in _specs) {
    if (spec.long.toLowerCase() == lower) return spec;
  }
  _Spec? match;
  for (final spec in _specs) {
    if (spec.long.toLowerCase().startsWith(lower)) {
      if (match != null) {
        throw AmbiguousCliOptionException('ambiguous option: $token');
      }
      match = spec;
    }
  }
  return match;
}

/// Completes [value] against the candidate list of [spec] with Ruby's
/// case-sensitive rules: an exact match wins, else a unique prefix match
/// wins. [display] renders the failure messages exactly as Ruby spells them
/// (`--opt value` or `--opt=value` for longs, `-x value` or `-xvalue` for
/// shorts, always with the option as given on the command line).
String _completeValue(_Spec spec, String value, String display) {
  final candidates = spec.allowed;
  if (candidates == null) return value;
  if (candidates.contains(value)) return value;
  final matches = candidates.where((c) => c.startsWith(value)).toList();
  if (matches.length == 1) return matches.single;
  if (matches.isEmpty) throw _InvalidCliArgument('invalid argument: $display');
  throw _AmbiguousCliArgument('ambiguous argument: $display');
}

/// Maps a completed `--safe-mode` value to its level.
int _safeModeValue(String name) {
  switch (name) {
    case 'unsafe':
      return SafeMode.unsafe;
    case 'safe':
      return SafeMode.safe;
    case 'server':
      return SafeMode.server;
    case 'secure':
      return SafeMode.secure;
  }
  throw StateError('unreachable: completed safe mode "$name"');
}

/// Parses a `-j/--jobs` value to a worker count.
///
/// Throws [_InvalidCliArgument] with GNU make's message (verified against
/// make 4.4.1: `make: the '-j' option requires a positive integer argument`)
/// for zero, negative and non-integer values; the usual invalid-argument
/// machinery then reports it with the usage text and exit code 1. The
/// message names `-j` regardless of the spelling used, exactly like make.
int _parseJobsValue(String value) {
  final jobs = int.tryParse(value);
  if (jobs == null || jobs < 1) {
    throw const _InvalidCliArgument(
      "the '-j' option requires a positive integer argument",
    );
  }
  return jobs;
}

/// Maps a completed `--log-level`/`--failure-level` value to its severity.
///
/// Port of the level handlers: the value is uppercased and `WARNING` folds
/// to `WARN`.
Severity _severityForLevel(String value) {
  var level = value.toUpperCase();
  if (level == 'WARNING') level = 'WARN';
  return Severity.fromName(level);
}

/// The path-list separator. Port of `File::PATH_SEPARATOR`.
String get _pathListSeparator => Platform.isWindows ? ';' : ':';

/// Port of `File.file?` (follows links).
bool _isFile(String path) {
  try {
    return FileSystemEntity.typeSync(path) == FileSystemEntityType.file;
  } on Exception catch (_) {
    return false;
  }
}

/// Writes [path] to [sink] with `puts` semantics (exactly one trailing
/// newline), read as UTF-8.
void _putsFile(StringSink sink, String path) {
  final content = File(path).readAsStringSync();
  sink.write(content);
  if (!content.endsWith('\n')) sink.writeln();
}

/// Writes [content] to [sink] with `puts` semantics (exactly one trailing
/// newline). The in-memory counterpart of [_putsFile] for embedded data.
void _putsContent(StringSink sink, String content) {
  sink.write(content);
  if (!content.endsWith('\n')) sink.writeln();
}

/// Writes gzip-compressed [path] to [sink] with `puts` semantics.
void _putsGzipFile(StringSink sink, String path) {
  final content = utf8.decode(gzip.decode(File(path).readAsBytesSync()));
  sink.write(content);
  if (!content.endsWith('\n')) sink.writeln();
}

/// Writes the man page at [path], gunzipping `*.gz` files first.
void _putsManpage(StringSink sink, String path) {
  if (path.endsWith('.gz')) {
    _putsGzipFile(sink, path);
  } else {
    _putsFile(sink, path);
  }
}

/// Finds [segments] (e.g. `['man', 'asciidoctor.1']`) in the enclosing
/// checkout, searching the current directory and its parents.
///
/// Substitution for Ruby's compile-time `ROOT_DIR` join (see the library
/// docs). Returns the path, or `null` when no enclosing directory holds it.
String? _findCheckoutFile(List<String> segments) {
  final relative = segments.join(Platform.pathSeparator);
  var dir = Directory.current;
  for (var depth = 0; depth <= 10; depth++) {
    final candidate = '${dir.path}${Platform.pathSeparator}$relative';
    if (File(candidate).existsSync()) return candidate;
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
  return null;
}

/// Expands [pattern] with the `Dir.glob` subset the CLI needs.
///
/// Returns the matches sorted lexically (as MRI orders them), or an empty
/// list when nothing matches. A pattern without magic characters matches
/// itself when any filesystem node exists at that path. Supported magic:
/// `*` and `?` within a segment, `[...]` character classes (with `!`/`^`
/// negation and ranges), and a `**` segment matching zero or more
/// directories. Like `Dir.glob` without `FNM_DOTMATCH`, a wildcard segment
/// never matches a leading dot unless the segment starts with a literal dot.
/// Brace expansion is not supported (see the library docs).
List<String> _glob(String pattern) {
  if (!_hasMagic(pattern)) {
    return _entityExists(pattern) ? [pattern] : [];
  }
  final isWindows = Platform.isWindows;
  var root = '';
  var rest = pattern;
  final drive = RegExp('^[A-Za-z]:/').firstMatch(pattern);
  if (rest.startsWith('/')) {
    root = '/';
    rest = rest.substring(1);
  } else if (isWindows && drive != null) {
    root = pattern.substring(0, 3);
    rest = rest.substring(3);
  }
  final trailingSlash = rest.endsWith('/');
  final segments = rest.split('/').where((s) => s.isNotEmpty).toList();
  var candidates = [''];
  for (final segment in segments) {
    final next = <String>[];
    if (segment == '**') {
      for (final base in candidates) {
        next
          ..add(base)
          ..addAll(_directoriesUnder(root, base));
      }
    } else {
      final matcher = _segmentMatcher(segment, isWindows);
      for (final base in candidates) {
        next.addAll(_matchSegment(root, base, matcher));
      }
    }
    candidates = next;
    if (candidates.isEmpty) return [];
  }
  final results = <String>[];
  for (final candidate in candidates) {
    final path = _joinRoot(root, candidate);
    if (trailingSlash) {
      if (_entityType(path) == FileSystemEntityType.directory) {
        results.add('$path/');
      }
    } else {
      if (_entityExists(path)) results.add(path == '' ? '.' : path);
    }
  }
  results.sort();
  return results;
}

/// Whether [pattern] holds an unescaped glob magic character.
bool _hasMagic(String pattern) {
  var escaped = false;
  for (var i = 0; i < pattern.length; i++) {
    final char = pattern[i];
    if (escaped) {
      escaped = false;
    } else if (char == r'\') {
      escaped = true;
    } else if (char == '*' || char == '?' || char == '[') {
      return true;
    }
  }
  return false;
}

/// Joins the glob [root] (`''`, `/` or a drive prefix) with [relative].
String _joinRoot(String root, String relative) {
  if (relative.isEmpty) {
    if (root.isEmpty) return '';
    if (root == '/') return '/';
    return root.substring(0, root.length - 1);
  }
  if (root.isEmpty) return relative;
  if (root == '/') return '/$relative';
  return '$root$relative';
}

/// The filesystem path of the glob [root] (`''` means the working directory).
String _rootAsDir(String root) {
  if (root.isEmpty) return '.';
  if (root == '/') return '/';
  return root;
}

/// The entity type at [path], or [FileSystemEntityType.notFound].
FileSystemEntityType _entityType(String path) {
  final target = path.isEmpty ? '.' : path;
  try {
    return FileSystemEntity.typeSync(target);
  } on Exception catch (_) {
    return FileSystemEntityType.notFound;
  }
}

/// Whether any filesystem node exists at [path].
bool _entityExists(String path) =>
    _entityType(path) != FileSystemEntityType.notFound;

/// The base-joined relative paths of every directory under the glob
/// [root]/[base], recursively (excluding [base] itself; the `**` caller adds
/// it for the zero-directory match). Symlinked directories are not descended
/// into, matching `Dir.glob`.
List<String> _directoriesUnder(String root, String base) {
  final results = <String>[];
  final seen = <String>{};
  final start = base.isEmpty ? _rootAsDir(root) : _joinRoot(root, base);
  final queue = [(path: start, relative: base)];
  while (queue.isNotEmpty) {
    final current = queue.removeLast();
    List<FileSystemEntity> entries;
    try {
      entries = Directory(current.path).listSync();
    } on Exception catch (_) {
      continue;
    }
    for (final entry in entries) {
      if (entry is! Directory) continue;
      final name = _basename(entry.path);
      final relative = current.relative.isEmpty
          ? name
          : '${current.relative}/$name';
      if (seen.add(entry.path)) {
        results.add(relative);
        queue.add((path: entry.path, relative: relative));
      }
    }
  }
  return results;
}

/// Matches one path segment against [matcher] inside the glob [root]/[base].
List<String> _matchSegment(String root, String base, _SegmentMatcher matcher) {
  final dirPath = base.isEmpty ? _rootAsDir(root) : _joinRoot(root, base);
  List<FileSystemEntity> entries;
  try {
    entries = Directory(dirPath).listSync();
  } on Exception catch (_) {
    return [];
  }
  final matches = <String>[];
  for (final entry in entries) {
    final name = _basename(entry.path);
    if (matcher.matches(name)) {
      matches.add(base.isEmpty ? name : '$base/$name');
    }
  }
  return matches;
}

/// The final component of [path].
String _basename(String path) {
  final slash = path.lastIndexOf('/');
  final backslash = Platform.isWindows ? path.lastIndexOf(r'\') : -1;
  final cut = slash > backslash ? slash : backslash;
  return cut < 0 ? path : path.substring(cut + 1);
}

/// A compiled single-segment glob matcher.
class _SegmentMatcher {
  /// Creates a matcher from `pattern` with [_regex] and dot rule flag.
  const new(this._regex, {required this._literalDotStart});

  /// The segment pattern translated to a regular expression.
  final RegExp _regex;

  /// Whether the pattern starts with a literal dot.
  final bool _literalDotStart;

  /// Whether file [name] matches this segment.
  bool matches(String name) {
    // Without FNM_DOTMATCH, wildcards never match a leading dot.
    if (name.startsWith('.') && !_literalDotStart) return false;
    return _regex.hasMatch(name);
  }
}

/// Compiles a single glob [segment] to a [_SegmentMatcher].
_SegmentMatcher _segmentMatcher(String segment, bool isWindows) {
  final buffer = StringBuffer('^');
  var literalDotStart = false;
  var first = true;
  var i = 0;
  while (i < segment.length) {
    final char = segment[i];
    if (char == r'\') {
      if (!isWindows && i + 1 < segment.length) {
        final next = segment[i + 1];
        if (first && next == '.') literalDotStart = true;
        buffer.write(RegExp.escape(next));
        i += 2;
        first = false;
        continue;
      }
      buffer.write(r'\\');
      i++;
      first = false;
      continue;
    }
    if (char == '*') {
      buffer.write('[^/]*');
      i++;
      first = false;
      continue;
    }
    if (char == '?') {
      buffer.write('[^/]');
      i++;
      first = false;
      continue;
    }
    if (char == '[') {
      final end = _classEnd(segment, i);
      if (end < 0) {
        if (first && char == '.') literalDotStart = true;
        buffer.write(RegExp.escape(char));
        i++;
        first = false;
        continue;
      }
      buffer.write(_translateClass(segment.substring(i, end + 1)));
      i = end + 1;
      first = false;
      continue;
    }
    if (first && char == '.') literalDotStart = true;
    buffer.write(RegExp.escape(char));
    i++;
    first = false;
  }
  buffer.write(r'$');
  return _SegmentMatcher(
    RegExp(buffer.toString()),
    literalDotStart: literalDotStart,
  );
}

/// Finds the closing bracket of the character class opening at [open].
/// Returns -1 for an unterminated class (matched literally, as in Ruby).
int _classEnd(String segment, int open) {
  var i = open + 1;
  if (i < segment.length && (segment[i] == '!' || segment[i] == '^')) i++;
  if (i < segment.length && segment[i] == ']') i++;
  while (i < segment.length) {
    if (segment[i] == ']') return i;
    i++;
  }
  return -1;
}

/// Translates a glob character class (brackets included) to regex source.
String _translateClass(String charClass) {
  var body = charClass.substring(1, charClass.length - 1);
  final negated = body.startsWith('!') || body.startsWith('^');
  if (negated) body = body.substring(1);
  final buffer = StringBuffer(negated ? '[^' : '[');
  for (var i = 0; i < body.length; i++) {
    final char = body[i];
    if (char == r'\') {
      buffer.write(r'\\');
    } else if (char == '-' && i > 0 && i + 1 < body.length) {
      // A `-` between two chars is a range; elsewhere it is literal.
      buffer.write('-');
    } else if (char == '^' ||
        char == '[' ||
        char == ']' ||
        char == '&' ||
        char == '-' ||
        char == '/') {
      buffer.write('\\$char');
    } else {
      buffer.write(char);
    }
  }
  buffer.write(']');
  return buffer.toString();
}
