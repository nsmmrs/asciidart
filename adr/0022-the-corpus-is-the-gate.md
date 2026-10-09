# ADR-0022: The Corpus Is the Black-Box Gate

**Status:** Accepted on 2026-10-09. Amends [ADR-0017](0017-follow-main-fix-bugs.md) decision 3.

## Context

ptome's behavior was checked from the outside by five suites with five
harnesses: the parity documents and Asciidoctor's fixtures diffed against
the gem's CLI (`tool/parity.sh`, on the native and the Node.js CLI), the
upstream bug reproductions in bats (`test/bugfix`, `tool/bugfix_check.sh`
running each on both CLIs), the deliberate differences in bats
(`test/divergences`), and the ascii-docs corpus in its own repository. Each
needed a built executable and the gem at check time; together they made the
gate slow.

## Decision

1. **One corpus** (`packages/ptome/test/corpus`): documents with the result
   each implementation gives them (Asciidoctor 2.0.26, Asciidoctor main,
   ptome), recorded in advance. ptome's test suite reads it
   (`test/corpus_test.dart`) on the Dart VM and on Node.js, in seconds,
   with neither the gem nor an executable.
2. **The tools that write it** are `packages/ptome_corpus_tools` (not
   published): they run the gem, record results, and refuse a ptome result
   that differs from Asciidoctor main without a divergence note.
3. **A fixed upstream bug is a corpus case** in `curated/bugfix`, named after
   the issue, recorded on the gem (whose result shows the bug) and on ptome
   (with the divergence note). A behavior around the fix that must not move
   is a case whose ptome result equals the gem's. Deliberate differences
   that aren't upstream bugs are in `curated/divergence`; documents of our
   own that pin parity are in `curated/parity`; Asciidoctor's own fixtures,
   converted as the CLI does, are in `curated/asciidoctor-fixtures`.
4. **Results don't depend on the machine**: the case directory and the
   working directory are normalized, the clock and the home directory are
   fixed, PDFs and EPUBs are set in the vendored fonts only, and the
   recorder converts each binary result again from another directory and
   fails if it changes.
5. The CLI end-to-end suite (`test/e2e`, bats) stays: it checks the command
   line itself, which the corpus doesn't.

## Consequences

- `test/bugfix`, `test/divergences`, `test/parity`, `tool/bugfix_check.sh`
  and `tool/parity.sh` are removed; their tests are corpus cases, each
  checked against the assertions of the test it replaces.
- Recording needs the gem (the tools' `setup.sh`); checking doesn't.
- PDF results are byte hashes, which depend on the platform's compression:
  they are checked on the Dart VM only.
