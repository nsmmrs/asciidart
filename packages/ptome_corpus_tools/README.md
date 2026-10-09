# ptome_corpus_tools

Tools for ptome's corpus (`packages/ptome/test/corpus`, ADR-0022): the
goldens, and the pool, sanitizer, generator and fuzzer that found its cases.
Not published.

- **`goldens/`** makes the goldens: the files the Asciidoctor command line
  writes for each case (see `goldens/README.md`).
- **The rest** built the corpus's first cases: anchors (real documents from
  a large pool, cut down to the parts that reach code, with their words
  replaced, structure kept) and the generator and fuzzer's finds. Those
  commands still write cases in the earlier corpus's layout (`cases/<set>/
  <name>/` with `case.toml` and `versions.toml`, recorded by profiles); port
  them to the flat layout before using them again.

```text
goldens/          generate.rb and a bundle per Asciidoctor release
drivers/ruby/     worker.rb: a long-lived Asciidoctor that converts over NDJSON
sources.toml      the pool's sources
tool/setup.sh     installs the goldens' bundles, the checkouts and gems the pool uses
triage/           fuzz findings
```

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
