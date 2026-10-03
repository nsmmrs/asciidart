# Differential Parity Verdict — ADR-0001 D4 (port/parity-gate, 2026-10-03)

Byte-identical gate: Dart CLI vs Ruby oracle over the fixture corpus,
via `dart/tool/differential.dart` (normalization: version stamps and
timestamps only, per ADR-0001 D4).

## Corpus

31 files per backend run:

- `test/fixtures/**` (`*.adoc`, `*.asciidoc`, recursive): 29 files
- `--extra-file README.adoc` (repo root)
- `--extra-file data/reference/syntax.adoc` (added by this gate task;
  `data/reference` coverage previously missing from the harness default)

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
- Root cause: `dart/lib/src/section.dart` used a private duplicate of
  `InvalidSectionIdCharsRx` with `\w`, which in Dart stays ASCII-only
  even with `unicode: true`. Ruby `CC_WORD` is `\p{Word}`
  (`lib/asciidoctor/rx.rb:263`), which keeps non-ASCII letters
  (`lib/asciidoctor/section.rb:208`).
- Fix: deleted the private duplicate; `Section.generateId` now uses the
  shared unicode-correct `invalidSectionIdCharsRx` from
  `dart/lib/src/rx.dart` (same one `manpage.dart` already used).
- Regression test: `Section.generateId` non-ASCII case in
  `dart/test/model_structural_test.dart`.

Diff count before → after: 1 → 0 per affected backend (html5, docbook5).
