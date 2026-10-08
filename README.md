# ascii-docs

A corpus of AsciiDoc documents with the output each implementation gives
them, and the tools that build it. The suite should reach every line and
branch of asciidart and Asciidoctor, and still run in seconds.

Cases come from three places:

- **anchor**: real documents from a large pool, cut down to the parts that
  reach code, with their words replaced (structure kept). Their output is
  known to be right, so they catch drift while bugs get fixed.
- **found**: documents from the random generator and fuzzer that exposed a
  bug or reached code nothing else did.
- **curated**: hand-written cases, such as the reproducers of fixed bugs.

## Layout

```text
profiles.toml     the implementations recorded: Asciidoctor 2.0.26, Asciidoctor main, asciidart
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
asciidart result that differs from Asciidoctor main must carry a
`divergence` note in `versions.toml` (a link to the upstream bug asciidart
fixes); `regen` fails otherwise.

## Use

```sh
tool/setup.sh                        # once: Asciidoctor checkouts + gems in ~/.cache/ascii-docs
dart run bin/ascii_docs.dart regen   # convert every case with every profile, record results
dart run bin/ascii_docs.dart regen --check   # verify instead of writing
dart run bin/ascii_docs.dart test    # asciidart in-process against its recorded results
dart test                            # the same, one package:test test per case and format
```

`regen` takes `-p <profile>` and case-id prefixes to limit what it runs.
Checkouts, gems, the raw pool and fuzzer state live in
`$ASCII_DOCS_CACHE` (default `~/.cache/ascii-docs`) and are never
committed.
