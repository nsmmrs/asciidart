# ADR-0022: The Corpus: ptome Against Asciidoctor's Own Files

**Status:** Accepted on 2026-10-09, and simplified the same day (this
text). Amends [ADR-0017](0017-follow-main-fix-bugs.md) decision 3.

## Context

ptome's behavior was checked from the outside by several suites with
several harnesses (the parity documents against the gem's CLI, the upstream
bug reproductions and deliberate differences in bats, the ascii-docs
corpus), each needing the gem and a built executable at check time. The
first corpus that replaced them recorded every implementation's results
(three Asciidoctor profiles and ptome's own), logs, divergence notes and
page comparisons: more bookkeeping than the question it answers.

## Decision

1. **A flat list of cases** (`packages/ptome/test/corpus/<case>/`): the
   document (`input.adoc`) with the files it reads, an optional `case.yml`
   (formats, safe mode, doctype, attributes, provenance), and the
   **goldens**: the literal files the Asciidoctor command line writes for
   it, in `expected/<release>/<format>/`. Only the latest stable release
   is generated (`asciidoctor-2.0.26`: Asciidoctor 2.0.26, asciidoctor-pdf
   2.3.27, asciidoctor-epub3 2.3.0); a later release gets a folder of its
   own beside it.
2. **Every case is a whole document**, as `asciidoctor input.adoc` writes it,
   with the attributes in `goldens.yml` (a fixed clock and home) and the
   case's own.
3. **ptome converts each case the same way**, with `asciidoctor-compat`.
   - **Text formats** (html5, xhtml5, docbook5, manpage) match the golden
     file's bytes; the only normalization is the generator's name in its
     stamp.
   - **PDF and EPUB** are compared by what can be seen: a PDF's pages,
     rendered at 50 dpi, pixel for pixel; an EPUB's files, byte for byte.
     That comparison is expensive, so the hash of the last ptome file found
     equal is kept (`ptome.yml`): the test passes at once on that hash, and
     a new file that compares equal replaces it.
4. **Compatibility is settings of the engine.** Where ptome's output
   differs, the fix is a value of a setting of the modern engine (or a new
   setting) that `asciidoctor-compat` sets for that format, never a mode
   that switches the engine. The corpus is red until every difference is
   closed; it runs as a job of its own (`dart test -t corpus`), and the
   rest of the suite without it.
5. **ptome's deliberate differences are not in the corpus.** A fix of a bug
   Asciidoctor still has, or another deliberate difference, is a folder of
   `test/upstream_fixes` with what ptome's output must contain
   (`upstream_fixes_test.dart`).
6. **Goldens come from the gem's own command-line code**
   (`packages/ptome_corpus_tools/goldens/generate.rb`, in the bundle pinned
   in `goldens/<release>/Gemfile.lock`, with the optional gems for what
   ptome implements: asciimath, text-hyphen). Each case is converted from
   two directories, and a result that differs between them is refused; a
   conversion that fails has no golden; a release's goldens are not
   rewritten without `--replace`.

## Consequences

- No profiles, divergence notes, logs or ptome results are recorded;
  diagnostics are not compared (their wording is ptome's own).
- The corpus started with 1,679 cases and 1,854 goldens, from the earlier
  corpus (anchors from real documents, the fuzzer's finds, Asciidoctor's
  fixtures, asciidoctor-pdf's spec documents, our parity documents).
- The EPUB goldens hold the fonts asciidoctor-epub3 embeds (about 450 KB
  each).
