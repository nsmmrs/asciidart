/// Prettify adapter: marks up source blocks for client-side highlighting.
///
/// Dart port of `lib/asciidoctor/syntax_highlighter/prettify.rb`.
///
/// Full port: highlighting itself runs in the browser via `run_prettify.js`,
/// so everything here is pure string transformation (the `<pre>`/`<code>`
/// hooks plus the head and footer loader tags).
library;

import 'package:asciidart/src/highlight/highlight.dart';

/// Syntax-highlighter adapter for Google Code Prettify.
///
/// Highlighting is performed by the prettify script in the browser; this
/// adapter only emits the markup hooks ([format]) and the loader tags
/// ([docinfoHead], [docinfoFooter]).
class PrettifyAdapter {
  /// Creates a prettify adapter.
  const new();

  /// Names this adapter registers for (`register_for 'prettify'`).
  static const List<String> registeredNames = ['prettify'];

  /// The adapter name.
  static const String name = 'prettify';

  /// The `<pre>` CSS class.
  static const String preClass = 'prettyprint';

  /// The default CDN base URL (see `HighlightJsAdapter.defaultCdnBaseUrl`).
  static const String defaultCdnBaseUrl =
      'https://cdnjs.cloudflare.com/ajax/libs';

  /// The pinned prettify revision on the CDN.
  static const String prettifyRevision = 'r298';

  /// Formats converted [content] for client-side highlighting.
  ///
  /// When [linenums] is set (the `linenums` option on the block), the
  /// `<pre>` class gains `linenums` (or `linenums:{start}` when [start], the
  /// block's `start` attribute, is present). [nowrap] appends the `nowrap`
  /// class.
  String format({
    required String content,
    String? language,
    bool nowrap = false,
    bool linenums = false,
    String? start,
  }) => wrapSourceBlock(
    preClass: preClass,
    content: content,
    language: language,
    nowrap: nowrap,
    transform: linenums
        ? (pre, _) {
            // NOTE a present-but-empty start still takes the numbered
            // branch; only an absent attribute counts as unset.
            pre['class'] =
                '${pre['class']} '
                '${start != null ? 'linenums:$start' : 'linenums'}';
          }
        : null,
  );

  /// Whether this adapter injects markup at [location].
  ///
  /// Always true: prettify needs both the head stylesheet link and the
  /// footer script.
  bool hasDocinfo(DocinfoLocation location) => true;

  /// Returns the `<link>` tag for the prettify theme stylesheet.
  ///
  /// [prettifyDir] mirrors the `prettifydir` document attribute (default:
  /// `{cdnBaseUrl}/prettify/{prettifyRevision}`); [theme] mirrors
  /// `prettify-theme` (default: `prettify`). An absolute `http(s)` theme is
  /// used verbatim, otherwise it resolves under the base URL.
  /// [selfClosingSlash] mirrors the converter's void-element slash (default
  /// `''` for HTML, `'/'` for XML).
  String docinfoHead({
    String? prettifyDir,
    String theme = 'prettify',
    String cdnBaseUrl = defaultCdnBaseUrl,
    String selfClosingSlash = '',
  }) {
    final baseUrl = prettifyDir ?? '$cdnBaseUrl/prettify/$prettifyRevision';
    final themeUrl = theme.startsWith('http://') || theme.startsWith('https://')
        ? theme
        : '$baseUrl/$theme.min.css';
    return '<link rel="stylesheet" href="$themeUrl"$selfClosingSlash>';
  }

  /// Returns the footer `<script>` tag that loads `run_prettify.js`.
  String docinfoFooter({
    String? prettifyDir,
    String cdnBaseUrl = defaultCdnBaseUrl,
  }) {
    final baseUrl = prettifyDir ?? '$cdnBaseUrl/prettify/$prettifyRevision';
    return '<script src="$baseUrl/run_prettify.min.js"></script>';
  }
}
