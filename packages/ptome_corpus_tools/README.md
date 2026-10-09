# ptome_corpus_tools

The tools that build ptome's black-box corpus, `packages/ptome/test/corpus`:
AsciiDoc documents with the output each implementation gives them. ptome's
own test suite reads the corpus (`test/corpus_test.dart`, one test per case
and format, a few seconds); this package only writes it, and is never
published.

Cases come from three places:

- **anchor**: real documents from a large pool, cut down to the parts that
  reach code, with their words replaced (structure kept). Their output is
  known to be right, so they catch drift while bugs get fixed.
- **found**: documents from the random generator and fuzzer that exposed a
  bug or reached code nothing else did.
- **curated**: hand-written cases, such as the reproducers of fixed bugs.

The case format is described in `packages/ptome/test/corpus/README.md`.
Here:

```text
drivers/ruby/     worker.rb: a long-lived Asciidoctor that converts over NDJSON
sources.toml      the pool's sources
tool/setup.sh     clones the Ruby profiles' checkouts and installs their gems
triage/           fuzz findings and the log differences regen reports
```

Each (case, format) pair is one test, with id `<case>#<format>`. A ptome
result that differs from Asciidoctor main must carry a `divergence` note in
`versions.toml` (a link to the upstream bug ptome fixes); `regen` fails
otherwise.

## Use

```sh
tool/setup.sh                       # once: Asciidoctor checkouts + gems in ~/.cache/ascii-docs
dart run bin/corpus.dart regen      # convert every case with every profile, record results
dart run bin/corpus.dart regen -p ptome   # only ptome's results (after a deliberate change)
dart run bin/corpus.dart regen --check    # verify instead of writing
```

`regen` takes `-p <profile>` and case-id prefixes to limit what it runs.
It records each ptome PDF's comparison with the gem's (`pixels`), with
poppler's `pdftoppm`, and fails when a ptome PDF or EPUB changes with the
directory it is converted from. It runs from ptome's package directory,
as ptome's tests do.
Run it from anywhere in the workspace; it finds the corpus.

## Building the corpus

```sh
# The pool (sources.toml): fetched, indexed, measured; never committed.
dart run bin/corpus.dart pool fetch
dart run bin/corpus.dart pool capture      # inputs Asciidoctor's own tests convert
dart run bin/corpus.dart pool index
dart run bin/corpus.dart pool measure      # per-conversion Ruby coverage, output hashes
dart run bin/corpus.dart pool stats        # unions and the set cover
dart --branch-coverage bin/corpus.dart pool dart-cov -f html5 \
  --first ~/.cache/ascii-docs/pool/ruby-cover.txt   # ptome elements beyond the Ruby cover

# Anchors: chosen, cut down, sanitized, verified, written to cases/anchor.
dart run bin/corpus.dart anchor --lanes 6
dart run bin/corpus.dart regen anchor

# The generator and fuzzer.
dart run bin/corpus.dart gen 42            # the document seed 42 generates
dart run bin/corpus.dart fuzz --seconds 600 -j 8
dart run bin/corpus.dart triage            # minimize findings, list them

# Gates.
dart run bin/corpus.dart oracles           # invariants hold on every recorded output
dart run bin/corpus.dart coverage --gate   # Ruby: reached or excluded
dart --branch-coverage bin/corpus.dart dart-coverage --gate   # ptome
```

Sanitizing replaces every word of prose (titles, paragraphs, cells, prose
attribute values, code identifiers) with a pseudo-word of the same length,
case pattern and script, one to one over the document's vocabulary, and
keeps markup, punctuation, digits, attribute and macro names, targets and
URLs. A sanitized document must reach every line and branch the original
did in both Ruby profiles, convert to output with the original's letter
shape, and still agree between ptome and Asciidoctor main. Words whose
replacement breaks that stay original and are listed in the case's
`kept-words`.

Checkouts, gems, the raw pool and fuzzer state live in
`$ASCII_DOCS_CACHE` (default `~/.cache/ascii-docs`) and are never
committed.
