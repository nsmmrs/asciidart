# ADR-0017: Follow Asciidoctor's Development Version, and Fix Its Bugs

**Status:** Final. Decided by the user on 2026-10-07; supersedes
[ADR-0003](0003-target-latest-stable.md).

## Context

ADR-0003 kept `master` byte-identical to the Asciidoctor 2.0.26 release,
with the port of upstream `main` on a `2.1.0` branch (re-implemented on
master's architecture, identical to the gem built from `main` at
`30fb8cd5`) and fixes for bugs Asciidoctor still has on a `bugfix` branch
on top of it. Three branches meant every change was merged forward twice,
and the release the project waited for (2.1) has no date. asciidart is
its own project (ADR-0015 and the rebrand): compatible with Asciidoctor,
not tied to its release schedule.

## Decisions

1. `master` takes the `2.1.0` and `bugfix` branches: it is compatible with
   Asciidoctor's development version (upstream `main` at `30fb8cd5`,
   reporting 2.1.0.alpha.0 as `{asciidoctor-version}`), and it fixes the
   upstream bugs listed in `benchmark/PARITY.md`.
2. The last commit that matched the 2.0.26 release byte for byte is tagged
   `asciidoctor-2.0.26-parity`, so that output can always be had again.
3. The oracle is the gem built from the vendored upstream commit; every
   difference from it is either listed in `benchmark/PARITY.md` (a fixed
   upstream bug, with a test in `test/bugfix/` that fails on the gem and
   passes here) or a bug. Moving the vendored commit forward is an ordinary
   change, gated like any other.
4. There is one development branch, `master`.

## Consequences

- Documents see the behavior of Asciidoctor's main line, plus the fixes;
  users who need 2.0.26's exact output use the tag.
- Compatibility is still checked byte for byte in CI, against the gem built
  from the pinned upstream commit instead of a published gem.
