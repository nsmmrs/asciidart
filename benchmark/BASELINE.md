# Ruby Baseline — ADR-0001 D2 Speed Verdict

The AOT binary must beat these Ruby CLI end-to-end wall-clock medians
(process spawn + convert, output to a temp file).

Note: `benchmark/benchmark.rb` was inspected but is not runnable as-is
(it requires a network download, the `erubis` gem, and the legacy
`Compliance.markdown_syntax` API), so this baseline uses the CLI-loop
method below. At these corpus sizes the ~60 ms Ruby startup dominates;
the D2 comparison is CLI-to-CLI, so startup-inclusive timing is correct.

## Machine

- CPU: AMD Ryzen 5 7540U w/ Radeon 740M Graphics (12 threads)
- RAM: 14 GB (6 GB available at run time)
- OS: Linux lapmaxxer 7.2.5-3-omarchy x86_64
- Ruby: `ruby 4.0.7 (2026-09-15 revision 229531a6cf) +PRISM [x86_64-linux]`
- Asciidoctor: 2.1.0.alpha.0 (measured pre-split at repo HEAD `5a6568f` via in-repo Ruby; reproduce now with the gem exe)

## Corpus (fixed)

| Label | File | Size |
| ----- | ---- | ---- |
| small | `test/fixtures/basic.adoc` | 86 B |
| medium | `test/fixtures/lists.adoc` | 1431 B |
| large | `benchmark/sample-data/mdbasics.adoc` | 7840 B |

Backends: `html5`, `docbook5`.

## Method

From the repo root, 3 warmup + 21 timed iterations per doc/backend cell:

```sh
ruby benchmark/baseline.rb --iterations 21 --warmup 3
```

Each iteration shells `asciidoctor -b <backend> -o <tmpfile> <doc>`
and records wall-clock time (`CLOCK_MONOTONIC`); the reported value is the
median of the 21 samples.

## Baseline medians (2026-10-03, run 1)

| Doc \ backend | html5 | docbook5 |
| ------------- | ----- | -------- |
| small | 74.0 ms | 68.9 ms |
| medium | 66.4 ms | 64.6 ms |
| large | 65.3 ms | 64.7 ms |

## Reproducibility (2026-10-03, run 2, fresh clean shell)

```sh
env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/local/bin TERM=xterm bash -c 'cd <repo-root> && ruby benchmark/baseline.rb --iterations 21 --warmup 3'
```

(Run with `<repo-root>` = this branch checkout; a bare `env -i` needs
`PATH` to include `ruby`.)

| Doc \ backend | html5 (run 2) | docbook5 (run 2) |
| ------------- | ------------- | ---------------- |
| small | 66.0 ms | 58.4 ms |
| medium | 61.6 ms | 60.5 ms |
| large | 74.2 ms | 73.9 ms |

A third confirmation run gave 65.1 / 64.2 / 66.6 / 65.6 / 67.2 / 64.7 ms
(same cell order), matching run 1 closely.

Variance: run-2 medians differ from run 1 by −15%…+14% (absolute deltas
≤ 10.5 ms); run 3 differs by −7%…+3%. The run-2 large cells drifted up
under transient machine load (samples up to 113.8 ms). Across all three
runs every cell median falls in the 58–75 ms band, typically 64–69 ms —
the baseline reproduces within noise. A D2 verdict should require the
AOT binary to beat these medians by a margin clearly above this ±~15%
noise band.

## Dart results (2026-10-03, parity gate, port/parity-gate)

Same corpus × backend matrix, same method (3 warmup + 21 timed CLI
end-to-end iterations per cell, median reported), timed back-to-back via
`benchmark/bench-exe.rb --exe ...` so Ruby, Dart VM, and AOT share one
harness. Ruby re-run fresh in the same session (matches the baseline
band above); Dart VM = `dart run bin/asciidoctor.dart` (JIT,
per-spawn startup); AOT = `tool/build-exes.sh` output
(`asciidoctor-linux-x64`, Dart SDK 3.13.5).

```sh
ruby benchmark/bench-exe.rb --exe 'asciidoctor'
ruby benchmark/bench-exe.rb --exe 'dart run bin/asciidoctor.dart'
ruby benchmark/bench-exe.rb --exe /tmp/dist/asciidoctor-linux-x64
```

| Doc \\ backend | Ruby html5 | Dart VM html5 | AOT html5 | Ruby docbook5 | Dart VM docbook5 | AOT docbook5 |
| ------------- | ---------: | -----------: | --------: | ------------: | ---------------: | -----------: |
| small | 71.7 ms | 1032.9 ms | 8.9 ms | 62.3 ms | 944.4 ms | 7.1 ms |
| medium | 63.7 ms | 855.8 ms | 12.3 ms | 62.0 ms | 870.6 ms | 11.2 ms |
| large | 65.0 ms | 861.8 ms | 17.8 ms | 62.7 ms | 847.5 ms | 18.0 ms |

Speedup multiples (median Ruby / median AOT, higher is better for Dart):

| Doc \\ backend | html5 | docbook5 |
| ------------- | ----: | -------: |
| small | 8.06x | 8.77x |
| medium | 5.18x | 5.54x |
| large | 3.65x | 3.48x |

Dart VM (`dart run`) is ~13–15x slower than Ruby per spawn — JIT + package
startup dominates; it is a dev-mode runner, not a D2 candidate.

**D2 verdict: PASS.** The AOT binary beats Ruby on every cell by
3.48x–8.77x, far above the ±~15% noise band.

## JS target: not run

`dart compile js bin/asciidoctor.dart` fails: `lib/src/document.dart`
declares `static const int _maxInt63 = 9223372036854775807`, which
"can't be represented exactly in JavaScript". Changing the saturation
constant would alter VM integer semantics (a parity risk), so per the
parity-gate task the JS target is recorded as not-run rather than fixed
here. (Node v26.8.1 is installed; compilation itself is the blocker.)

## Throughput (steady state, in-process)

The CLI numbers above are dominated by process startup at those corpus
sizes. `benchmark/throughput.dart` measures the engine itself: a ~294 KB
document (mdbasics + the syntax reference + `sample.adoc`, ×20) converted
in-process with `safe`, `doctype: book`, standalone; 5 warmups, median of 15.

```sh
dart compile exe benchmark/throughput.dart -o /tmp/throughput && /tmp/throughput
```

Ruby comparison: the same corpus and options through
`Asciidoctor.convert` (gem 2.0.26, Ruby 4.0.7, mean of 15 after 3 warmups).

| Impl (2026-10-04) | html5 | docbook5 | manpage |
| --- | --: | --: | --: |
| Ruby | 81.6 ms | 82.8 ms | 121.1 ms |
| Ruby + YJIT | 56.6 ms | 56.2 ms | 91.5 ms |
| Dart AOT, before perf work (`39e4201`) | 89.0 ms | 90.6 ms | 134.3 ms |
| Dart AOT, after perf work (`2286244`) | 41.3 ms | 40.4 ms | 53.4 ms |

Per step (html5 / manpage, same machine, `perf/throughput` branch):

| Commit | Change | html5 | manpage |
| --- | --- | --: | --: |
| `7b201c9` | baseline | 89.0 ms | 134.3 ms |
| `1d1c992` | `rstrip`/`lstrip` as code-unit scans | 75.8 ms | 112.4 ms |
| `5c37af6` | literal guards on quote/replacement rules | 43.9 ms | 85.4 ms |
| `80273f4` | quote guards need the closing delimiter | 42.0 ms | 82.0 ms |
| `f95b862` | literal guards on manpage `manify` regexes | 43.7 ms | 70.6 ms |
| `f860409` | single-pass manpage character references | 43.0 ms | 54.3 ms |
| `2286244` | callout scan pre-check | 41.3 ms | 53.4 ms |

Run-to-run noise is about ±2 ms. Every step was checked byte-identical
against an AOT build of `39e4201` with `tool/differential.dart` on all
three backends (fixtures, `syntax.adoc` and the throughput corpus).

Net: 2.2x (html5), 2.2x (docbook5) and 2.5x (manpage) faster than before,
and faster than Ruby + YJIT on every backend. CLI startup-dominated cells
are unchanged (small html5 9.3 -> 9.2 ms); the `large` CLI cell (8 KB)
went from 17.6 to 14.8 ms.
