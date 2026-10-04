---
id: TASK-j38bqf
title: "Rename ruby* helpers and remove Ruby from user-facing text"
status: backlog
type: task
priority: 2
labels:
- idiomatic
parent: EPIC-k5nzlv
deps:
- EPIC-9frzpm
created: "2026-10-04T13:53:24.446492Z"
updated: "2026-10-04T13:53:24.446492Z"
---

Rename helpers by what they do, keeping behavior identical:
- core_ext.dart: `RubyString` extension, `rubyToInteger` (lenient leading-int parse, e.g. a name like parseLeadingInt), `rubyToDouble`, `rubySplit` (split that drops trailing empty pieces), `_isRubyStripChar`.
- reader.dart: `_rubyToDouble`, `_rubyLines`.
- Review other Ruby-named helpers (`chomp`, `chopLast`, `squeezeChar`, `isNilOrEmpty`, `inspectString`) and rename where a Dart name is clearer.

User-facing text:
- core_ext.dart:182,199 error messages say 'mirrors Ruby NoMethodError'.
- man/asciidoctor.adoc (and the generated lib/src/cli/help_topics.g.dart): `-I` mentions 'the default Ruby load path' and `-r` 'the standard Ruby require'. Both are wrong for a Dart binary. Check the bats e2e suite for any `--help` comparisons this affects.

Done when: `grep -rniE '\bruby' lib` finds only the highlighter, `eruby` and comments; dart analyze is clean; the corpus is still byte-identical.