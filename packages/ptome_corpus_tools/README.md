# ptome_corpus_tools

Tools for ptome's corpus (`packages/ptome/test/corpus`, ADR-0022): the
goldens, and the pool, sanitizer, generator and fuzzer that found its cases.
Not published.

- **`goldens/`** makes the goldens: the files the Asciidoctor command line
  writes for each case (see `goldens/README.md`).
- **The rest** finds cases: anchors (real documents from a large pool, cut
  down to the parts that reach code, with their words replaced, structure
  kept) and the generator and fuzzer's finds. Each is written as a case of
  the corpus (`<name>/input.adoc` with the files it reads, and `case.yml`:
  source, formats, safe mode, doctype, attributes), and its goldens are
  made at once with `goldens/generate.rb`.

```text
goldens/          generate.rb and a bundle per Asciidoctor release
drivers/ruby/     worker.rb: a long-lived Asciidoctor that converts over NDJSON
profiles.toml     the Asciidoctor checkouts the tools run, and ptome's settings
sources.toml      the pool's sources
tool/setup.sh     installs the goldens' bundles, the checkouts and gems the pool uses
triage/           fuzz findings, the oracle baseline
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

# Anchors: chosen, cut down, sanitized, verified, written as cases with
# their goldens (<source>-<name>-<format>-<hash>).
dart run bin/corpus.dart anchor --lanes 6

# The generator and fuzzer.
dart run bin/corpus.dart gen 42            # the document seed 42 generates
dart run bin/corpus.dart fuzz --seconds 600 -j 8
dart run bin/corpus.dart triage            # minimize findings, list them
dart run bin/corpus.dart promote           # queued finds that reach new code, as cases

# A handmade case, with its goldens.
dart run bin/corpus.dart add list-explicit-start doc.adoc -f html5 -f docbook5

# Gates.
dart run bin/corpus.dart oracles           # invariants hold on every text golden
dart run bin/corpus.dart coverage --gate   # Ruby: reached or excluded
dart --branch-coverage bin/corpus.dart dart-coverage --gate   # ptome
```

Sanitizing replaces every word of prose (titles, paragraphs, cells, prose
attribute values, code identifiers) with a pseudo-word of the same length,
case pattern and script, one to one over the document's vocabulary, and
keeps markup, punctuation, digits, attribute and macro names, targets and
URLs. A sanitized document must reach every line and branch the original
did in both Ruby profiles, convert to output with the original's letter
shape, and still agree between ptome (with `asciidoctor-compat`) and
Asciidoctor 2.0.26. Words whose
replacement breaks that stay original and are listed in the case's
`kept-words`.

Checkouts, gems, the raw pool and fuzzer state live in
`$ASCII_DOCS_CACHE` (default `~/.cache/ascii-docs`) and are never
committed.
