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
- Asciidoctor: 2.1.0.alpha.0 (repo HEAD `5a6568f`, `ruby -Ilib`)

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

Each iteration shells `ruby -Ilib bin/asciidoctor -b <backend> -o <tmpfile> <doc>`
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
