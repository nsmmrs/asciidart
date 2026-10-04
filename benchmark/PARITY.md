# Differential Parity Verdict

Byte-identical gate (ADR-0001 D4): the Dart CLI against the Asciidoctor
**2.0.26** gem, via `tool/differential.dart` (normalization: version stamps
and timestamps only). `master` targets 2.0.26 per
[ADR-0003](../adr/0003-target-latest-stable.md); the earlier port of
upstream `main` (2.1.0.alpha.0) is preserved on the `2.1.0` branch.

## Corpus

- `test/fixtures/**` (`*.adoc`, `*.asciidoc`, recursive) plus
  `data/reference/syntax.adoc`: 32 files per backend.
- `test/parity/**` plus `data/reference/syntax.adoc`: 9 files per backend.
  These pin the places where 2.0.26 differs from upstream `main` (tilde
  open blocks, ordered list starts, `link=self`, front matter, table and
  manpage layout, ...); see [`test/parity/README.md`](../test/parity/README.md).

## Method

From the repository root, with the gem on `PATH`
(`gem install asciidoctor -v 2.0.26`):

```sh
tool/build-exes.sh
tool/parity.sh dist/asciidoctor-linux-x64
```

`tool/parity.sh` runs both corpora on html5, docbook5 and manpage. Each file
is converted as `<exe> -b <backend> -o - -q <input>` with `TZ=UTC` and
`SOURCE_DATE_EPOCH=0`. CI runs the same script on every push
(`dart-exe-e2e` job).

## Verdict (2026-10-04): PASS — 123/123 identical

| Corpus | html5 | docbook5 | manpage |
| --- | --: | --: | --: |
| fixtures | 32/32 | 32/32 | 32/32 |
| parity | 10/10 | 10/10 | 10/10 |

Warnings on stderr were compared by hand over the parity corpus and match
too (the harness passes `-q`). The e2e suite (`test/e2e/`, 128 tests) passes
with no skips against both the Dart CLI and the gem.

## Known intentional differences

- Fatal errors are reported as one `asciidoctor: FAILED: <message>` line in
  plain wording, without Ruby exception classes, gem names or `Processing
  aborted.` (for example `asciidoctor: FAILED: failed to load <stdin>:
  missing converter for backend 'pdf'`). Log messages (warnings, errors)
  keep Asciidoctor's wording. Library callers catch `AsciidoctorException`.
- A reader that closes stdout early (`asciidoctor -o - doc.adoc | head`)
  ends the run quietly with exit code 0; the gem reports a broken pipe.
- The `cache-uri` attribute has no effect (the gem requires the
  `open-uri-cached` gem for it); remote content is read each time.
- An unknown CLI option prints Ruby's `Did you mean?` hint only in Ruby;
  that suggestion engine depends on the Ruby version (see the notes at the
  top of `lib/src/cli/options.dart`).
- Dart-only features (Mustache templates, `init-config`, `-j/--jobs`) have
  no Ruby counterpart.
- `--help` and `-h manpage` describe `-T` and `-E` as they work in this
  build (Mustache templates) instead of mentioning tilt and gems.
- The Ruby-only options `-r/--require`, `-I/--load-path`, `--eruby` and
  `-w/--warnings` do not exist here and are rejected as unknown options;
  extensions are compiled into a custom binary instead (see
  `asciidoctor init-config`). `-q` silences log messages only, since there
  are no script warnings.
