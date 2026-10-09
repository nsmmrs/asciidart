# ascii-docs

A corpus of AsciiDoc documents with the output each implementation gives
them, and the tools that build it. The suite should reach every line and
branch of ptome and Asciidoctor, and still run in seconds.

Cases come from three places:

- **anchor**: real documents from a large pool, cut down to the parts that
  reach code, with their words replaced (structure kept). Their output is
  known to be right, so they catch drift while bugs get fixed.
- **found**: documents from the random generator and fuzzer that exposed a
  bug or reached code nothing else did.
- **curated**: hand-written cases, such as the reproducers of fixed bugs.

## Layout

```text
profiles.toml     the implementations recorded: Asciidoctor 2.0.26, Asciidoctor main, ptome
defaults.toml     options every case starts from (fixed clock, safe mode, embedded output)
cases/<set>/<name>/
  case.toml       description, provenance, features, formats, options, attributes
  input.adoc      the document (one input, converted to each listed format)
  fixtures/       files it includes or references (base directory: the case directory)
  expected/       <format>.<hash>.<ext>: each distinct output once, by content hash
  versions.toml   [<format>.<profile>] output = "<hash>" | error = "...", log, divergence
drivers/ruby/     worker.rb: a long-lived Asciidoctor that converts over NDJSON
tool/setup.sh     clones the Ruby profiles' checkouts and installs their gems
```

Each (case, format) pair is one test, with id `<case>#<format>`. An
ptome result that differs from Asciidoctor main must carry a
`divergence` note in `versions.toml` (a link to the upstream bug ptome
fixes); `regen` fails otherwise.

## Use

```sh
tool/setup.sh                        # once: Asciidoctor checkouts + gems in ~/.cache/ascii-docs
dart run bin/ascii_docs.dart regen   # convert every case with every profile, record results
dart run bin/ascii_docs.dart regen --check   # verify instead of writing
dart run bin/ascii_docs.dart test    # ptome in-process against its recorded results
dart test                            # the same, one package:test test per case and format
```

`regen` takes `-p <profile>` and case-id prefixes to limit what it runs.

## Building the corpus

```sh
# The pool (sources.toml): fetched, indexed, measured; never committed.
dart run bin/ascii_docs.dart pool fetch
dart run bin/ascii_docs.dart pool capture      # inputs Asciidoctor's own tests convert
dart run bin/ascii_docs.dart pool index
dart run bin/ascii_docs.dart pool measure      # per-conversion Ruby coverage, output hashes
dart run bin/ascii_docs.dart pool stats        # unions and the set cover
dart --branch-coverage bin/ascii_docs.dart pool dart-cov -f html5 \
  --first ~/.cache/ascii-docs/pool/ruby-cover.txt   # ptome elements beyond the Ruby cover

# Anchors: chosen, cut down, sanitized, verified, written to cases/anchor.
dart run bin/ascii_docs.dart anchor --lanes 6
dart run bin/ascii_docs.dart regen anchor

# The generator and fuzzer.
dart run bin/ascii_docs.dart gen 42            # the document seed 42 generates
dart run bin/ascii_docs.dart fuzz --seconds 600 -j 8
dart run bin/ascii_docs.dart triage            # minimize findings, list them

# Gates.
dart run bin/ascii_docs.dart oracles           # invariants hold on every recorded output
dart run bin/ascii_docs.dart coverage --gate   # Ruby: reached or excluded
dart --branch-coverage bin/ascii_docs.dart dart-coverage --gate   # ptome
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
