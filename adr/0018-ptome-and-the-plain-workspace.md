# ADR-0018: ptome, and the plain_* Libraries in One Pub Workspace

**Status:** Final. Decided by the user on 2026-10-08. Supersedes the naming
decision of [ADR-0006](0006-asciidart.md); its compatibility-ledger policy
stays.

## Context

The project was named asciidart (ADR-0006). The name reads close to
AsciiDoc®, a registered trademark of the Eclipse Foundation, whose
guidelines forbid putting a project mark in a product name. It also puts
"dart" in front of users who never see Dart. Nothing has been published
under it, so renaming costs nothing.

Its libraries lived in their own repositories (compression, fonts, libpdf,
hilite) and depended on each other through commit-pinned `git:`
dependencies. pub.dev accepts none of those, so nothing above compression
could be published, and every cross-repository change took a chain of
manual ref bumps. Two of the names could not be published anyway: pub.dev
treats `fonts` as too similar to `font` and `libpdf` as too similar to
`lib_pdf`.

Background: `reports/Rename ideas for asciidart.md` (names and trademark
rules), `reports/Dart guidance on umbrella packages.md` (dart.dev on
packages, versioning, re-exports and workspaces) and
`reports/Pure Dart extraction opportunities.md` (what to extract and in
which order).

## Decisions

1. **The product is Ptome** ("plain text tome"; a tome with a silent p,
   like pterodactyl). It is *Ptome* in prose and in the stamps the tool
   writes: `--version`, the HTML generator meta tag, the man page header.
   It is `ptome` for the command, the pub and npm packages, the message
   prefix (`ptome: WARNING: ...`) and identifiers (`{ptome-version}`,
   `PTOME_*` environment variables, `ptome.yml`). The rename is a clean
   break: no `asciidart` aliases. The repository is `nsmmrs/ptome`.
   ptome is described as "a processor for AsciiDoc® documents, compatible
   with Asciidoctor", never as AsciiDoc-compliant or certified (no
   AsciiDoc TCK release exists yet).
2. **Libraries are named `plain_<obvious noun>`.** The prefix stands for
   what they share: pure Dart, written from the specification, the same
   bytes on every platform, statically typed, tested against outside
   oracles. compression becomes `plain_compression`, fonts `plain_fonts`,
   libpdf `plain_pdf`, hilite `plain_highlighting`; new packages are
   `plain_unicode`, `plain_hyphenation`, `plain_math` and
   `plain_typesetting`.
3. **Names are checked against pub.dev's own similarity rules**, not just
   for a 404: every name in `https://pub.dev/api/package-names` (gzip)
   reduced with pub-dev's `reducePackageName` (case, underscores), with
   its singular/plural and homoglyph variants, and the reserved list. All
   the names above passed on 2026-10-08.
4. **One repository, one pub workspace.** `nsmmrs/ptome` holds every
   package under `packages/`: `packages/ptome` and `packages/plain_*`. The
   root `pubspec.yaml` is not a package (`name: _`, `publish_to: none`),
   as dart.dev's workspace documentation shows; it declares
   `workspace: [packages/*]`, and each member has `resolution: workspace`.
   One lockfile, one analysis context.
5. **History comes along.** Each library repository is imported with
   `git filter-repo --to-subdirectory-filter packages/<name>` and merged
   with unrelated histories. Its tags are prefixed with the package name
   (`plain_pdf-...`), which also keeps the per-repository copies of
   `hs-golden-parity-2026-10-06` apart. The old repositories are archived
   with a pointer to their folder in `nsmmrs/ptome`, not deleted.
6. **Versions are independent per package**, as in dart-lang/core: each
   package has its own version, CHANGELOG and tag pattern
   (`plain_pdf-v{{version}}`). Siblings depend on each other with wide
   caret constraints.
7. **Publishing goes through the Anticomplex verified publisher**
   (domain anticomplex.net). A new package's first upload comes from a
   personal account and is transferred to the publisher right after (the
   transfer cannot be undone). Each package has its own automated
   publishing workflow. The company identity lives in the publisher,
   never in package names.
8. **Rules for the libraries:**
   - no package re-exports a sibling (plain_pdf stops re-exporting
     `OpenTypeFont` and `FontFormatException`; ptome depends on
     plain_fonts directly);
   - no build hooks or FFI in the low layers; a native fast path goes in a
     separate package, so its hook reaches only code that opts in;
   - platform-specific code goes behind conditional imports with a stub
     (as plain_fonts' `platform/none.dart`, `vm.dart`, `js.dart`);
   - dependencies stay minimal: Dart-team packages, plus `xml` in
     plain_pdf (its SVG reader), until plain_math gives it a typed MathML
     tree; any further outside dependency needs an ADR.
9. **The libraries move to their own repository later**, for example
   `nsmmrs/plain_dart`, once they gain outside users or their own release
   pace, or once library issues crowd ptome's tracker. ptome reaching 1.0
   does not trigger the split on its own. The split extracts `packages/`
   with history, re-points automated publishing and repository URLs, and
   removes the folders from ptome in an ordinary commit, so the
   repository links of published versions keep working.

## Consequences

- The local checkout folder (`~/Work/ports/asciidoctor-dart`) and the
  work cache (`~/.cache/asciidart-work`) keep their names; published names
  change. History (CHANGELOG entries, ADR-0001 to 0017, past benchmark
  reports) keeps "asciidart" where it describes the past.
- Tools that read message prefixes or generator stamps accept `ptome:` and
  `Ptome <version>` alongside the earlier names.
- Paths in `tool/`, `npm/`, CI and the docs move under `packages/ptome`.
- CI resolves each package alone against its siblings' hosted versions as
  well as inside the workspace, where siblings always resolve locally and
  a missing version bump would go unnoticed.
