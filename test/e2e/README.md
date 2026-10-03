# Black-box end-to-end suite

Started per ADR-0001 D6, before any porting begins. These tests exercise the
command-line executable as a black box (no in-process Ruby): they are the
conformance contract the Dart port must satisfy.

## Running

```sh
# against the in-repo Ruby CLI (default subject under test)
bats test/e2e/

# against a future Dart executable
ASCIIDOCTOR_EXE=/path/to/asciidoctor-dart bats test/e2e/
```

`ASCIIDOCTOR_EXE` must point at an executable file; every test file fails fast
in `setup_file` when it is missing. Requires bats >= 1.5 (`run
--separate-stderr`); verified with bats 1.13.0.

## Layout

- `bin/asciidoctor-ruby` — shim that execs the repo Ruby CLI (`bin/asciidoctor`).
- `helpers.bash` — subject resolution (`ASCIIDOCTOR_EXE`), `check_exe`, and
  fixed-string assertion helpers with failure dumps.
- `conversion_open_block.bats` — from `features/open_block.feature` (5 tests).
- `conversion_pass_block.bats` — from `features/pass_block.feature` (3 tests).
- `conversion_text_formatting.bats` — from `features/text_formatting.feature`
  (3 tests).
- `conversion_xref.bats` — from `features/xref.feature` (51 tests, 1:1 with
  the feature scenarios, including the `@wip` part-refsig case, which passes).
- `cli_backends_doctypes.bats` — backends (html5/docbook5/manpage), doctypes,
  embedded output (from `test/invoker_test.rb`).
- `cli_output_files.bats` — output routing: default naming, `-o`/`--out-file`
  incl. STDOUT `-`, trailing-newline rules, `-D`/`-R`, multiple inputs, globs.
- `cli_attributes.bats` — `-a`/`--attribute` assignment variants.
- `cli_modes_options.bats` — safe modes, `-B`, `--log-level`,
  `--failure-level`, `-q`, `-v`, `--trace`, `-t`.
- `cli_help_version_errors.bats` — help topics, version, stdin input, CLI
  error paths (from `test/options_test.rb` + `test/invoker_test.rb`).

## Conventions

- Hermetic: each test runs with cwd set to its own `BATS_TEST_TMPDIR`;
  all inputs are generated inline; no network, no repo writes.
- Golden assertions for embedded conversion output go through `-e -o -`
  (stdout) and are compared byte-exact (`diff -u`) or as fixed `grep -F`
  fragments translated from the feature files' Slim structure notation.
- Deliberately excluded as Ruby-implementation-specific (not portable to the
  Dart CLI): `-r/--require`, `-I/--load-path`, `-T/--template-dir`,
  `-E/--template-engine`, `--eruby`, `-w/--warnings`, and `-o /dev/null`
  (which skips conversion in the Ruby implementation).
