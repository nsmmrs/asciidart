# Differential Parity Verdict — ADR-0001 D4 (port/parity-gate, 2026-10-03)

Byte-identical gate: Dart CLI vs Ruby oracle over the fixture corpus,
via `tool/differential.dart` (normalization: version stamps and
timestamps only, per ADR-0001 D4).

## Corpus

31 files per backend run:

- `test/fixtures/**` (`*.adoc`, `*.asciidoc`, recursive): 29 files
- (pre-split runs also passed `--extra-file README.adoc`; the Ruby README
  left with the repo split, so the default corpus is now fixtures +
  `data/reference/syntax.adoc`)
- `--extra-file data/reference/syntax.adoc` (added by this gate task;
  `data/reference` coverage previously missing from the harness default)

## Post-split re-verification (2026-10-03)

After the repo split (package at root, Ruby sources removed), re-ran all
three backends against the pre-split 2.1.0.alpha.0 oracle:
32/32 identical each (32 = 31 fixtures + `data/reference/syntax.adoc`;
the dropped `README.adoc` was the Ruby README).

Note: the latest published gem (2.0.26) is NOT byte-identical — its default
stylesheet and CLI surface predate 2.1 (`--log-level` missing). The e2e
suite probes for `--log-level` and skips those 3 tests against gem oracles.

## Method

From `dart/`:

```sh
RUBY="test/e2e/bin/asciidoctor-ruby"
DART="test/e2e/bin/asciidoctor-dart"
dart run tool/differential.dart --exe-a "$RUBY" --exe-b "$DART" --backend html5
dart run tool/differential.dart --exe-a "$RUBY" --exe-b "$DART" --backend docbook5
dart run tool/differential.dart --exe-a "$RUBY" --exe-b "$DART" --backend manpage
```

Each file is converted as `<exe> -b <backend> -o - -q <input>` with
`TZ=UTC` and `SOURCE_DATE_EPOCH=0`.

## Verdict: PASS — 93/93 identical (31 files × 3 backends)

| Backend | Identical | Differ |
| ------- | --------: | -----: |
| html5 | 31 | 0 |
| docbook5 | 31 | 0 |
| manpage | 31 | 0 |

## Divergence found and fixed (1)

Before the fix, html5 and docbook5 each showed 1 diff
(`test/fixtures/encoding.adoc`); manpage output contains no section IDs
for this file and was unaffected.

- Symptom: `Überschrift` section got `id="_überschrift"` (Ruby) vs
  `id="_berschrift"` (Dart) — Dart dropped the non-ASCII `ü`.
- Root cause: `lib/src/section.dart` used a private duplicate of
  `InvalidSectionIdCharsRx` with `\w`, which in Dart stays ASCII-only
  even with `unicode: true`. Ruby `CC_WORD` is `\p{Word}`
  (`lib/asciidoctor/rx.rb:263`), which keeps non-ASCII letters
  (`lib/asciidoctor/section.rb:208`).
- Fix: deleted the private duplicate; `Section.generateId` now uses the
  shared unicode-correct `invalidSectionIdCharsRx` from
  `lib/src/rx.dart` (same one `manpage.dart` already used).
- Regression test: `Section.generateId` non-ASCII case in
  `test/model_structural_test.dart`.

Diff count before → after: 1 → 0 per affected backend (html5, docbook5).
