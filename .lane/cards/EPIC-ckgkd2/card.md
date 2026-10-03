---
id: EPIC-ckgkd2
title: "Dart rewrite of Asciidoctor (dart-sass model)"
status: done
type: epic
priority: 2
labels:
- rewrite
created: "2026-10-03T06:08:56.087512Z"
updated: "2026-10-03T19:54:43.148827Z"
---


Make Dart the canonical Asciidoctor implementation: pub package + standalone native CLI + npm JS build. Ruby is the behavioral oracle (48 lib files, ~19.3k LOC, 2876 minitest blocks, 75 fixtures). HTML5 first, then docbook5/manpage. PDF/EPUB3 out of scope (separate gems).