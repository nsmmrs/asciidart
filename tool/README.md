# Differential harness (`tool/differential.dart`)

Byte-identical parity gate (ADR-0001, D4). Runs **two** asciidoctor
executables over the fixture corpus plus `README.adoc`, normalizes version
stamps and timestamps, and reports per-file unified diffs. Exits nonzero on
any mismatch.

## Quick start

```sh
cd dart
dart pub get

# Repo Ruby CLI vs itself: must be 100% identical (exit 0).
RUBY="ruby -Ilib bin/asciidoctor"
dart run tool/differential.dart --exe-a "$RUBY" --exe-b "$RUBY"

# Injected-diff check: html5 vs docbook5 must fail with per-file diffs.
dart run tool/differential.dart --exe-a "$RUBY" --exe-b "$RUBY" \
  --backend-a html5 --backend-b docbook5
```

Both commands run from `dart/`; the repo root is auto-detected. Exe child
processes run with the repo root as their working directory, so use
root-relative (`ruby -Ilib bin/asciidoctor`) or absolute exe paths.

Later this same harness compares the gem exe against the Dart exe:

```sh
dart run tool/differential.dart \
  --exe-a "ruby -Ilib bin/asciidoctor" \
  --exe-b "build/asciidoctor"
```

## Options

| Option | Default | Meaning |
| --- | --- | --- |
| `--exe-a`, `--exe-b` | (required) | Exe path or full command line (POSIX-style quoting, e.g. `"ruby -Ilib bin/asciidoctor"`). |
| `--backend` | `html5` | Backend for both exes. |
| `--backend-a`, `--backend-b` | `--backend` | Per-exe backend override. |
| `--root` | auto-detect | Repo root. |
| `--corpus-dir` | `test/fixtures` | Corpus dir, relative to `--root` unless absolute (scanned recursively). |
| `--extra-file` | `README.adoc`, `data/reference/syntax.adoc` | Extra corpus file(s), repeatable, relative to `--root` unless absolute. |
| `--extensions` | `adoc,asciidoc` | Comma-separated corpus extensions. |
| `--context` | `3` | Unified-diff context lines. |
| `--max-diff-lines` | `200` | Max diff lines printed per file (rest truncated). |
| `--timeout-secs` | `60` | Per-conversion timeout; a timeout marks the file as differing. |
| `--out-dir` | temp dir | Write raw per-exe outputs here (`a/<rel>`, `b/<rel>`). |
| `--keep-outputs` | off | Keep the temp output dir (always kept on mismatch). |
| `--filter` | — | Only convert files whose path contains this string. |
| `-q`, `--quiet` | off | Only print diffs and the summary. |
| `-h`, `--help` | — | Print usage. |

## Exit codes

| Code | Meaning |
| --- | --- |
| `0` | All corpus files converted identically. |
| `1` | At least one file differed (diffs printed to stdout). |
| `2` | Harness error: bad usage, missing corpus, or an exe would not start. |

## What each exe must support

Every corpus file is converted as:

```sh
<exe...> -b <backend> -o - -q <absolute-input-path>
```

with `TZ=UTC` and `SOURCE_DATE_EPOCH=0` in the environment and the repo
root as the working directory. So each exe must accept `-b`, `-o -`
(stdout), `-q`, and a positional input file. Only stdout (plus the exit
code) feeds the verdict; stderr is drained and ignored.

## Normalization (narrow, per ADR-0001 D4)

Before comparison, each output is normalized:

- line endings (`\r\n`, `\r` → `\n`);
- `Asciidoctor <version>` stamps (HTML generator meta, manpage header);
- the HTML footer `Last updated <datetime>` line;
- the manpage `Date:` header and `.TH` date field.

Content-derived dates (e.g. `revdate`) are **not** normalized;
`docdate`/`doctime` determinism comes from the fixed `SOURCE_DATE_EPOCH`
exported to both children. There is no cosmetic-diff allowlist: anything
else that differs fails the gate.

## Output

Per file, either `ok <rel-path>` or a `DIFF <rel-path>` block with the
reason (exit-code mismatch, timeout) and a unified diff capped at
`--max-diff-lines`. A summary line closes the run, e.g.
`differential: all 28 files identical` or
`differential: 25 identical, 3 differ (28 total)`. On mismatch the raw
per-exe outputs are preserved and their directory is printed.

## Self-check

`test/differential/selfcheck.bats` keeps this harness honest without any
Dart port: Ruby-vs-Ruby identity, html5-vs-docbook5 detection, unified-hunk
rendering, and version-stamp normalization. Run it with:

```sh
bats test/differential/selfcheck.bats
```
