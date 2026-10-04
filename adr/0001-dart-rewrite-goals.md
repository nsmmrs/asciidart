# ADR-0001: Dart Rewrite Project Goals

**Status:** Final — accepted by user (see acceptance quote).

## Context (researched, not asked)

- Repo: Asciidoctor Ruby gem, v2.1.0.alpha.0, `main` branch.
- Claim under test: "A fast ... text processor and publishing toolchain, written in Ruby"
  (gemspec description; `README.adoc:54`).
- Port surface: 48 lib files, ~19.3k LOC. Biggest: `parser.rb` (2,801),
  `extensions.rb` (1,551), `substitutors.rb` (1,549), `document.rb` (1,404),
  `converter/html5.rb` (1,385), `reader.rb` (1,375).
- Oracle: 2,876 minitest blocks, ~7.6k asserts, 75 fixtures, 4 cucumber
  `.feature` files; CI matrix (JRuby, MRI 2.7/3.0/3.4, TruffleRuby, macOS).
- Built-in backends: html5, docbook5, manpage. PDF/EPUB3 are separate gems.
- Distribution model: dart-sass (canonical Dart implementation; pub package +
  standalone native exes + npm JS build).
- Execution tracker: lane board `asciidoctor-dart` (EPIC-ckgkd2 + 15 cards).

## Decisions

### D1. True objective — SETTLED (b)

Full canonical Dart replacement; commit now. No intermediate spike gate:
the project proceeds through all port phases to a Dart-first Asciidoctor.

### D2. Success measure — SETTLED (2)

Parity + proven speed win required: 100% fixture-corpus parity on all
three backends, CLI flag parity, pub + standalone exes + npm shipped,
AND the AOT binary must beat Ruby 3.4 on the benchmark corpus —
otherwise the project fails. The speed premise is a gate, not a hope.

### D3. Scope — SETTLED (1)

Everything in-repo is in scope for v1: all three backends, CLI,
extensions framework, all 6 syntax-highlighter adapters (each with an
implemented strategy), and the Tilt-template spike resolved by building
an adapter or port — not a gap note. Out of scope: PDF/EPUB3 converters
and AsciidoctorJ/JS-class counterparts (separate repos/gems, unchanged).
These are downstream consumer projects, not parts of this repo; the port
covers every converter this repo ships (html5, docbook5, manpage).

### D4. Compatibility stance — SETTLED (1)

Byte-identical output on the corpus, narrow normalization only (version
stamps, timestamps). No cosmetic-diff allowlist: downstream users must
not observe any change. Checked by the differential harness.

### D5. Fate of the Ruby implementation — SETTLED (custom)

Upstream Ruby project is not controlled by us; its fate doesn't matter.
In this repo, the only implementation will be the Dart one. Ruby sources
are kept only as long as needed for reference; benchmarks and oracle
comparisons can use a downloaded asciidoctor gem exe instead.

### D6. E2E methodology (bats-first) — SETTLED (accepted)

Researched: no black-box CLI suite exists. The 4 cucumber `.feature`
files run in-process (`step_definitions.rb` requires the lib and calls
`Asciidoctor.convert` directly); `invoker_test.rb` instantiates
`Cli::Invoker` in-process (no subprocess/shell-out); no bats/shellspec
suite exists anywhere in the repo. Proposal: before beginning the port,
port the existing e2e coverage (cucumber scenarios + invoker/options
cases) to a bats suite runnable against ANY cli implementation (gem exe
vs Dart exe), so parity and speed are judged without bias. This becomes
the new phase-0 gate alongside the differential harness.

## Scope contract — ACCEPTED

- **Artifact boundary (in scope):** Dart pub package source (full port of
  all 48 lib files: parser, document model, substitutors,
  html5/docbook5/manpage converters, extensions, CLI, all 6 highlighter
  adapters, implemented template-converter solution); bats e2e suite
  (ported pre-port, runnable against gem exe and Dart exe); differential
  test harness + ported corpus evidence; benchmark report (gem exe vs
  Dart VM vs AOT exe vs JS); CI workflow + release build tooling (exe
  archives per OS/arch, JS bundle — built and tested, NOT published);
  build-from-source docs; this ADR; lane board tracking.
- **Artifact classes out of scope:** registry publishing (pub listing,
  npm package, GitHub releases uploads — deferred to later); upstream
  Ruby project (releases, maintenance, its README/gemspec claims);
  PDF/EPUB3 converters and AsciidoctorJ/JS-class counterparts (separate
  repos); long-term retention of Ruby sources in this repo (temporary
  reference only).
- **Done means:** (1) bats e2e suite green against BOTH gem exe and Dart
  exe; (2) full fixture corpus byte-identical (narrow normalization) on
  html5 + docbook5 + manpage vs gem oracle; (3) CLI flag parity verified;
  (4) extensions + highlighter suites green per D3; (5) template-converter
  solution implemented; (6) AOT binary beats Ruby 3.4 gem exe on
  benchmark corpus (else the project fails per D2); (7) CI green and
  release artifacts build reproducibly (unpublished); (8) this ADR Final;
  lane epic closed.
- **Deferred stages:** registry publishing (pub/npm/releases); npm
  package name/scope and repo-split timing stay open as lane-board
  follow-ups (TASK-bpvxxh, TASK-n1447f); each needs its own decision
  before any future publishing step. The JS bundle became the npm package
  `asciidoctor-dart`: see [ADR-0005](0005-js-build.md).
- **Acceptance quote:** "accept" — chat, 2026-10-03 07:28 UTC.
