# Contributing

The bar for every change is unchanged output: Ptome must convert
documents exactly as the Asciidoctor gem built from the vendored upstream
commit (`main` at `30fb8cd5`, `packages/ptome/tool/vendor.sh`) does (ADR-0001, ADR-0017),
unless the difference is deliberate and listed in `benchmark/PARITY.md`
(a fixed upstream bug, with its test in `test/upstream_fixes/`; diagnostics, which
read like a Dart tool's).

## Layout

The repository is a pub workspace ([ADR-0018](adr/0018-ptome-and-the-plain-workspace.md)):
ptome is `packages/ptome`, and the libraries it is built on are
`packages/plain_*`, each published on its own; `packages/ptome_corpus_tools`
makes the test corpus's goldens and is not published. `dart pub get` anywhere
resolves the whole workspace. Paths and commands below are relative to a
package's folder, `packages/ptome` unless they say otherwise.
[RELEASING.md](RELEASING.md) says how each package is released.

## Setup

- Dart SDK 3.13 or later
- For the parity gates: Ruby with the gem built from upstream `main` at
  `30fb8cd5` (`gem build asciidoctor.gemspec` in a checkout of that commit,
  as CI does) and the asciimath gem, no other optional gems, and
  [bats](https://github.com/bats-core/bats-core)
- For the npm package: Node.js 20.19 or later (and Chromium for the browser
  test)

```sh
dart pub get
```

## Checks

From the repository root, the gate in two tiers (ADR-0022):

```sh
tool/gate.sh          # every commit, about 40 s: format, analyze, ptome's
                      # tests but the slow ones, the corpus included
tool/gate.sh full     # before a push: every test with the coverage floor,
                      # API and JavaScript projection checks, the CLI (bats),
                      # the plain_* packages, the Node.js and npm suites
```

The corpus (`test/corpus`, `dart test -t corpus`) checks ptome against the
files the Asciidoctor command line writes for about 1,700 documents. It is
red until compatibility settings close every difference, so the gate holds
it to the cases known red (`test/corpus/red.txt`): a case that newly fails
fails the gate, and one that passes is to be taken off the list
(`dart run tool/corpus_red.dart REPORT.json --update` rewrites it from a
run's JSON report). ptome's fixes of upstream bugs are tested in
`test/upstream_fixes/`.

The full tier also holds the suite's coverage of ptome's code (lines and
branch arms) to `tool/coverage_floor.txt`; new code comes with tests, the
corpus's cases first. Tests that start processes or run long property
checks are tagged `slow` (`dart test -x slow` leaves them out).

The live oracles (the gem's CLI, asciidoctor-epub3 with EPUBCheck, and the
goldens made again from their pinned bundle) and the slow tests on macOS
and Windows run nightly in CI (`.github/workflows/nightly.yml`).

The command line, on a built executable:

```sh
./tool/build-exes.sh
ASCIIDOCTOR_EXE="$PWD/dist/ptome-linux-x64" bats test/e2e/
```

`ASCIIDOCTOR_EXE=test/e2e/bin/asciidoctor-ruby bats test/e2e/` runs the
same suite against the gem; both must pass.

The tests and tools set PDFs and EPUBs in the fonts vendored with
asciidoctor-pdf and asciidoctor-epub3 (`tool/vendored_fonts.dart`), so
their output doesn't depend on the fonts installed. To run the executable
on the same fonts by hand, put their folders in `PTOME_FONT_PATH`:

```sh
export PTOME_FONT_PATH=$PWD/vendor/asciidoctor-pdf/data/fonts:$PWD/vendor/asciidoctor-pdf/icons:$PWD/data/pdf-fonts:$PWD/vendor/asciidoctor-epub3/fonts
```

## Corpus check

A wider comparison with the gem over thousands of real documents (stdout,
warnings and exit codes, four modes each); see `benchmark/PARITY.md`:

```sh
tool/corpus/fetch.sh /tmp/corpus
dart run tool/corpus_parity.dart --exe-a asciidoctor \
  --exe-b dist/ptome-linux-x64 --out /tmp/corpus-results /tmp/corpus
```

Use a gem install without optional gems as `--exe-a`, and run Ptome
with `-a highlightjs-mode=client` (see `benchmark/PARITY.md`). Every
difference it finds deserves a case in the corpus (`test/corpus`).

## The npm package

```sh
./tool/build-npm.sh          # build/npm; never publishes
cd test/npm && npm ci
node --test                  # API, exports, contents, bundler, browser
npm run types                # tsc over typical usage
npm run lint                 # publint and are-the-types-wrong
cd ../.. && dart test -p node
ASCIIDOCTOR_EXE=test/e2e/bin/ptome-node bats test/e2e/
```

The browser test looks for Chromium at `/usr/bin/chromium`; set
`CHROMIUM_PATH` to use another build.

## Layout

- `lib/ptome.dart`, `io.dart`, `cli.dart`: the public libraries
  (`export ... show` lists only), backed by `lib/src/api/`, a typed layer
  over the implementation. The supported API is described in
  `doc/api.md`; a change to it updates `tool/api_surface.txt`
  (`dart run tool/api_check.dart --update`) and `test/api/`, which uses
  only the public libraries.
- `lib/src/`: the implementation (still mostly one Dart file per
  Asciidoctor source file, `parser.dart` for `parser.rb`, ...), plus the CLI
  in `lib/src/cli/`.
- `lib/src/io.dart`: the only access to files, processes and the network
  (VM and JavaScript implementations; `test/platform_seam_test.dart`).
- `lib/src/js/` and `npm/`: the JavaScript bridge and the npm package
  (ADR-0005).
- `tool/`: build scripts and the differential harness.
- `test/e2e/`: the bats suite shared with the gem; `test/corpus/`: the
  black-box corpus ([ADR-0022](adr/0022-the-corpus-is-the-gate.md)).
- `adr/`: decisions.

## Embedded data

Files taken from Asciidoctor (its stylesheets, locales, syntax reference and
test fixtures) live under `vendor/asciidoctor/`, unchanged and pinned to an
upstream revision; see `vendor/README.md`. `tool/vendor.sh` recreates them
(`--check` verifies them). Documents of our own go in the corpus.

`lib/src/data.g.dart` embeds the vendored locales and stylesheets so the
package never reads them at run time, and `lib/src/cli/help_topics.g.dart`
embeds the man page and syntax reference for `-h`. Both are generated;
`tool/vendor.sh` regenerates them. The man page is written in
`man/ptome.adoc`; after changing it, rebuild `man/ptome.1` (with
Ptome itself) and the embedded copy:

```sh
tool/build-man.sh
dart test test/cli/help_topics_test.dart
```

## Pull requests

Keep each change focused, with a test. For a behavior change, show that the
gem agrees: a corpus case (its goldens are the gem's files), or an e2e
test, makes it permanent; a fix of a bug the gem has goes in
`test/upstream_fixes/`.
