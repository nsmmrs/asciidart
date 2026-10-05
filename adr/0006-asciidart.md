# ADR-0006: asciidart, a Compatible Re-implementation

**Status:** Final — decided with the user 2026-10-05.

## Context

The project started as "an unofficial Dart port of Asciidoctor" whose bar
was byte-identical output (ADR-0001 D4, ADR-0003). Two things changed:

- The user wants to fix upstream Asciidoctor bugs here (after triaging its
  open issues), and to restructure the code around Dart's type system
  rather than mirroring the Ruby sources. Both make the code diverge from
  upstream on purpose.
- The package was named `asciidoctor` (never published), with an
  `asciidoctor` executable. That implies an official port and puts two
  different `asciidoctor` commands on the same `PATH`.

## Decisions

1. **Name.** The project, the pub and npm packages and the command are
   **asciidart**; the repository is `github.com/nsmmrs/asciidart`. It is
   presented as an independent re-implementation, not affiliated with or
   endorsed by the Asciidoctor project.
2. **Compatibility is a ledger, not an identity.** asciidart aims to be a
   drop-in replacement: same documents, attributes, command-line options
   and output. The parity gates (`tool/parity.sh` against the gem, the
   corpus check, the e2e suite shared with the gem) keep running, and every
   difference they report is either zero or a deliberate, documented entry
   in `benchmark/PARITY.md`. "Identical to the gem" stops being a goal in
   itself; a fix that changes output is fine once it is listed there.
3. **What documents see stays the same.** The `asciidoctor` attribute stays
   set (so `ifdef::asciidoctor[]` works) and `asciidoctor-version` reports
   the compatible release (2.0.26). The new `asciidart-version` attribute
   reports asciidart's own version (replacing `asciidoctor-dart-version`).
4. **What names the tool says asciidart.** The HTML generator meta tag and
   the man page header (`Asciidart <version>`), `--version` (`Asciidart
   <version> (compatible with Asciidoctor 2.0.26)`), `--help`, the man page
   (`man/asciidart.adoc`, rewritten in our own words) and the message
   prefix (`asciidart: WARNING: ...`). The parity tools treat either name
   as the same stamp or prefix.
5. **Version claims stay honest** (ADR-0003): asciidart reports the
   Asciidoctor release whose behavior the gates verify, never one they
   don't.

## Consequences

- ADR-0001's "identical output" and "port" wording describes how the
  project began; this ADR replaces it as the policy going forward.
- Tools that scrape `asciidoctor:` message prefixes need to accept
  `asciidart:` as well.
- The local checkout folders keep their old names; only published names
  change.
