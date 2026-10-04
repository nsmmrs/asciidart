# ADR-0003: Target the Latest Stable Asciidoctor Release

**Status:** Final — accepted by user 2026-10-04.

## Context

The port was made from upstream `main` at `30fb8cd5` (2026-09-01), whose
version string is `2.1.0.alpha.0`. Upstream has not released 2.1; the latest
release is 2.0.26. Upstream's CHANGELOG lists about 60 unreleased changes
on `main`, several of them parse-level (tilde open blocks, level-0 special
sections, attribute name rules). A first release that reported 2.0.26 while
behaving like `main` would misdescribe itself, and its parity claim could
not be checked against any published gem.

## Decisions

1. `master` matches **Asciidoctor 2.0.26** byte for byte. The 2.1 changes
   were reverted one upstream issue at a time, using the 2.0.26 gem sources
   and the upstream `v2.0.26` test suite as the reference.
2. The oracle is the published gem (`gem install asciidoctor -v 2.0.26`).
   `tool/parity.sh` runs the fixture corpus and the parity corpus
   (`test/parity`) on all three backends; CI runs it on every push.
3. `Asciidoctor.version` (and so `{asciidoctor-version}`, the generator
   meta tag and `--version`) reports the matched upstream release.
   The package's own version is exposed separately.
4. The 2.1.0.alpha.0 port is kept unchanged on the `2.1.0` branch. When
   upstream releases 2.1, port its delta onto `master` (that branch is a
   head start, not a merge source to take blindly) and move the oracle pin.

## Consequences

- Users get the behavior of the Asciidoctor they can install today, and
  every compatibility claim is checked by CI against that release.
- Moving to a new upstream release means bumping the gem pin in CI,
  porting the delta, and growing `test/parity` with documents that cover
  the new behavior.
