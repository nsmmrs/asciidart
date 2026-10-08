# Releasing

Each package of the workspace is released on its own, with its own version
and tag ([ADR-0018](adr/0018-ptome-and-the-plain-workspace.md)):
`<package>-v<version>`, such as `plain_pdf-v0.1.0` or `ptome-v0.1.0`.
Pushing a tag publishes that package to pub.dev
(`.github/workflows/publish_<package>.yml`), through pub.dev's automated
publishing from GitHub Actions: no token is stored anywhere, and pub.dev
checks that the tag's version is the package's.

## Order

A package is released after the siblings it depends on:

1. plain_compression, plain_unicode, plain_math
2. plain_fonts (on plain_compression), plain_hyphenation (on
   plain_compression)
3. plain_typesetting (on plain_fonts, plain_math, plain_unicode),
   plain_highlighting (on plain_unicode)
4. plain_pdf (on plain_compression, plain_fonts, plain_math,
   plain_typesetting, plain_unicode)
5. ptome (on all of them)

## Once: the publisher and the first versions

These steps are done by hand, by the owner, and some can't be undone.

1. Create the verified publisher **Anticomplex** on pub.dev
   (https://pub.dev/create-publisher) for the domain `anticomplex.net`,
   verified through Google Search Console.
2. Publish the first version of each package, in the order above, from a
   personal account: in `packages/<package>`, `dart pub publish`.
3. Transfer each package to the Anticomplex publisher (the package's
   Admin tab on pub.dev). The transfer can't be undone.
4. On each package's Admin tab, enable automated publishing from GitHub
   Actions: repository `nsmmrs/ptome`, tag pattern
   `<package>-v{{version}}`, and require the GitHub Actions environment
   `pub.dev`.
5. In the repository's settings, give the `pub.dev` environment required
   reviewers, so a pushed tag waits for an approval before publishing.

## Each release

1. In the package: set `version:` (no `-dev`), and turn the changelog's
   "unreleased" heading into the version.
2. In the siblings that depend on it, raise the constraint (`^0.1.0`) if
   the release is needed.
3. Check that it would publish: `tool/publish_check.sh <package>` (CI runs
   it for every package). Then run the package's tests, and for ptome the
   full gate (CONTRIBUTING.md).
4. Commit, push, and tag: `git tag <package>-v<version>` and
   `git push origin <package>-v<version>`. The workflow publishes it once
   the `pub.dev` environment is approved.

ptome's tag also runs `release-check.yml`, which checks the tag against
the pubspec and the npm package and dry-runs both registries. The npm
package is published by hand (`tool/build-npm.sh`, then `npm publish` in
`build/npm`).
