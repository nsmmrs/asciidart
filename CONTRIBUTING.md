# Contributing

The bar for every change is unchanged output: asciidart must convert
documents exactly as the Asciidoctor 2.0.26 gem does (ADR-0001, ADR-0003),
unless the difference is deliberate and listed in `benchmark/PARITY.md`
(diagnostics, for one, read like a Dart tool's).

## Setup

- Dart SDK 3.13 or later
- For the parity gates: Ruby with the gem
  (`gem install asciidoctor -v 2.0.26 && gem install coderay pygments.rb`)
  and [bats](https://github.com/bats-core/bats-core)
- For the npm package: Node.js 20.19 or later (and Chromium for the browser
  test)

```sh
dart pub get
```

## Checks

```sh
dart analyze --fatal-infos .
dart format --output=none --set-exit-if-changed .
dart test                   # the library and CLI tests
dart run tool/api_check.dart  # the public API is closed and matches tool/api_surface.txt
```

Parity with the gem, on a built executable:

```sh
./tool/build-exes.sh
ASCIIDOCTOR_EXE="$PWD/dist/asciidart-linux-x64" bats test/e2e/
./tool/parity.sh dist/asciidart-linux-x64
```

`ASCIIDOCTOR_EXE=test/e2e/bin/asciidoctor-ruby bats test/e2e/` runs the
same suite against the gem; both must pass.

## Corpus check

A wider comparison with the gem over thousands of real documents (stdout,
warnings and exit codes, four modes each); see `benchmark/PARITY.md`:

```sh
tool/corpus/fetch.sh /tmp/corpus
dart run tool/corpus_parity.dart --exe-a asciidoctor \
  --exe-b dist/asciidart-linux-x64 --out /tmp/corpus-results /tmp/corpus
```

Use a gem install whose only optional gem is CodeRay as `--exe-a`. Every
difference it finds deserves a reproducer in `test/parity/`.

## The npm package

```sh
./tool/build-npm.sh          # build/npm; never publishes
cd test/npm && npm ci
node --test                  # API, exports, contents, bundler, browser
npm run types                # tsc over typical usage
npm run lint                 # publint and are-the-types-wrong
cd ../.. && dart test -p node
ASCIIDOCTOR_EXE=test/e2e/bin/asciidart-node bats test/e2e/
./tool/parity.sh test/e2e/bin/asciidart-node
```

The browser test looks for Chromium at `/usr/bin/chromium`; set
`CHROMIUM_PATH` to use another build.

## Layout

- `lib/asciidart.dart`, `io.dart`, `cli.dart`: the public libraries
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
- `tool/`: build scripts, the parity gate and the differential harness.
- `test/e2e/`: the bats suite shared with the gem; `test/parity/`: extra
  parity documents.
- `adr/`: decisions.

## Embedded data

Files taken from Asciidoctor (its stylesheets, locales, syntax reference and
test fixtures) live under `vendor/asciidoctor/`, unchanged and pinned to an
upstream revision; see `vendor/README.md`. `tool/vendor.sh` recreates them
(`--check` verifies them). Documents of our own go in `test/parity/`.

`lib/src/data.g.dart` embeds the vendored locales and stylesheets so the
package never reads them at run time, and `lib/src/cli/help_topics.g.dart`
embeds the man page and syntax reference for `-h`. Both are generated;
`tool/vendor.sh` regenerates them. The man page is written in
`man/asciidart.adoc`; after changing it, rebuild `man/asciidart.1` (with
asciidart itself) and the embedded copy:

```sh
tool/build-man.sh
dart test test/cli/help_topics_test.dart
```

## Pull requests

Keep each change focused, with a test. For a behavior change, show that the
gem agrees: a fixture in `test/parity/` or an e2e test makes it permanent.
