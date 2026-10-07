# ADR-0016: Using Every Core, Without Changing a Byte

**Status:** Final. Decided on 2026-10-07 (lane EPIC-syydcx, branch
`multicore`).

## Context

On master (3d1b837) the Hypermedia Systems book's PDF takes 3.8 s on one
core; Typst 0.15.1 compiles its edition in 3.9 s on twelve threads (8 s
of user time). Measurements of asciidart's pipeline (the research behind
the epic, kept outside the repository) found that about half of the 3.8 s
is work repeated on one core (the whole book laid out three times,
paragraphs wrapped five times each, every grammar compiled for one
listing), and that most of the rest is independent: image encoding,
stream compression, the layout of chapters that start on a new page.

Dart's means are isolates. Isolates in one group share a heap, so
messages between them are copies (except immutable strings and deeply
immutable objects), and a collection stops them all: work that keeps a
large heap alive scaled 1.6x on six isolates against 3.0x on six
processes. Shared-memory threads are not available on stable Dart (the
`--experimental-shared-data` flag aborts the VM; `dart:concurrent` doesn't
compile). On JavaScript, `dart:isolate` doesn't run at all.

## Decision

1. **Repeated work goes first.** Before anything runs in parallel, the
   work done more than once is done once: line breaks are cached, the
   index and the footnotes no longer lay out the whole book again, the
   highlighter compiles a grammar when it needs it. Parallel code then
   doesn't duplicate waste.

2. **The output doesn't depend on the number of workers.** Every result
   is the same, byte for byte, with one worker or twelve, finishing in any
   order. The serial path stays, as the reference and as the JavaScript
   path; a harness (`tool/jobs_check.dart`) compares the two on the book,
   the PDF fixtures and the corpus.

3. **Order is decided on the main isolate.** Object numbers, page
   numbers, footnote numbers, glyph use and the order things are written
   in are assigned there, in document order; workers compute values that
   are put in the places already decided.

4. **Only plain data crosses.** Bytes, strings, numbers and records of
   them go to workers and come back; never closures, layout boxes or
   libpdf objects (they hold closures, identity-keyed state and mutable
   caches a copy would split). A worker that needs the document rebuilds
   it from the source and the options.

5. **The transport is replaceable.** The pool (`Parallel`) has a serial
   backend, an isolate backend and a process backend (the native
   executable as its own worker), behind one protocol of plain data;
   which one runs a kind of work is a measured default, not a design
   constraint. Jobs are pulled by idle workers, not dealt in advance.

6. **Defaults.** Workers: the physical cores (allocation-heavy work
   scales worse on SMT siblings); the `jobs` attribute sets them (`-a
   jobs=4`, `1` for none). A document converted with in-process extensions, or
   inside an outer `-j` batch, runs serially (workers wouldn't have the
   extensions; nested pools oversubscribe the cores).

## Consequences

- The PDF path gets an asynchronous finishing step where worker results
  are awaited; the synchronous API keeps the serial path.
- libpdf gains ways to take precomputed payloads (an image's streams, a
  page's content bytes and resources, glyph use to merge) so that the work
  can happen elsewhere.
- Every change on the branch passes the byte-identity harness before it
  is committed.

## Measured (2026-10-07)

What the epic built, on the Hypermedia Systems PDF (6 cores, 12
threads; `tool/jobs_check.dart`, byte-identical at 1, 2, 6 and 12
workers, results shuffled):

| Step | HS PDF |
|---|---|
| master (3d1b837) | 3.78 s |
| line breaks kept, index and footnote passes resumed from clean pages | 2.90 s |
| PNG images encoded on the pool during the walk and layout | 2.29 s |
| page content streams compressed on the pool | 2.19 s |

Chapter-chunk workers were measured before being built
(`tool/spike_chunks.dart`: each worker parses and walks the book, then
lays out every Nth chunk between page breaks):

| Workers | Isolates: wall, peak MB, slowest walk | Processes: wall, peak MB (sum), slowest walk |
|---|---|---|
| 1 | 1360 ms, 147, 734 ms | 1388 ms, 148, 695 ms |
| 2 | 1196 ms, 200, 794 ms | 1198 ms, 322, 773 ms |
| 4 | 1341 ms, 287, 1069 ms | 1293 ms, 948, 975 ms |
| 6 | 1503 ms, 330, 1288 ms | 1432 ms, 1854, 1131 ms |
| 12 | 2227 ms, 602, 2075 ms | 2297 ms, 7020, 1692 ms |

Every worker repeats the parse and the walk (about half of its work),
and that walk slows down 1.5–3x as workers are added, processes as much
as isolates: the limit here is the machine's memory bandwidth and clock,
not the shared heap. Processes take 4–12x the memory. The best case
(two workers) gains about 10% over laying everything out on one core,
before the stitching a real implementation needs (page offsets, labels,
the index, footnote numbers, painting, glyph use). Chapter-chunk workers
are therefore not built; the work that remains on the main isolate
(parse and walk 0.7 s, layout 0.75 s, painting 0.25 s) is a matter for
serial speed. If a different machine changes the numbers, the spike
tool measures it again.
