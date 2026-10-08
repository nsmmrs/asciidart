# Upstream bug reproductions

One bats file per upstream Asciidoctor issue that the `bugfix` branch
fixes, named after the issue number (`4877.bats` is
[asciidoctor#4877](https://github.com/asciidoctor/asciidoctor/issues/4877)).

Each test is a black-box CLI check, like the e2e suite: it runs the
executable named by `ASCIIDOCTOR_EXE` and asserts on its output. Before a
fix lands, its test must fail on both the Ruby CLI (the gem built from
upstream `main`) and the Ptome CLI; after the fix it passes on
Ptome and still fails on Ruby. Tests named `unchanged: ...` are
guards for the behavior around a fix, which stays as Asciidoctor has it;
they pass on both. `tool/bugfix_check.sh` checks both:

```sh
tool/bugfix_check.sh path/to/ptome path/to/asciidoctor
```

The triage that chose these issues is in
[`doc/upstream-triage.md`](../../doc/upstream-triage.md), and each fix is
listed under the intentional differences in
[`benchmark/PARITY.md`](../../benchmark/PARITY.md).
