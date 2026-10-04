---
id: TASK-gtbg2k
title: "Port the remaining CodeRay scanners (Java and others)"
status: backlog
type: task
priority: 3
labels:
- parity
- highlight
created: "2026-10-04T23:52:24.300411Z"
updated: "2026-10-04T23:52:24.300411Z"
---

The corpus check (tool/corpus_parity.dart, benchmark/PARITY.md) leaves 4 of 17,900 conversions different: source blocks in Java with source-highlighter=coderay. Only the Ruby and text scanners are ported (lib/src/highlight/coderay_lexer.dart); any other language fails the whole conversion with 'CodeRay highlighting for language ... needs its scanner port', where the gem highlights it. CodeRay 1.1.3 ships about 25 scanners (c, cpp, css, diff, go, groovy, html, java, java_script, json, lua, php, python, sql, xml, yaml, ...). Options: port them (mechanical StringScanner code, verify with the corpus), or, as a stopgap, fall back to plain output with a warning instead of failing.