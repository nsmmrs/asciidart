---
id: TASK-dv2cr4
title: "Dart-native diagnostics: drop Ruby-ecosystem wording"
status: done
type: task
priority: 2
labels:
- cli
created: "2026-10-04T14:58:41.337495Z"
updated: "2026-10-04T18:00:08.902037Z"
---



User decision 2026-10-04: parity is about converted output only; diagnostics must read like a Dart tool. Reword gem-availability messages ("optional gem 'asciimath' is not available", "required gem ... is not available", "cannot load such file"), LoadError/NoMethodError/RuntimeError-style text, and print error messages without Dart class prefixes (absorbs BUG-jlr4kn). Update PARITY.md: stderr wording is intentionally not matched.