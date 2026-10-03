---
id: TASK-0jrdqj
title: "Port main-module constants (asciidoctor.rb top-level)"
status: done
type: task
priority: 2
labels:
- phase-1
- constants
parent: EPIC-ckgkd2
created: "2026-10-03T09:32:30.154929Z"
updated: "2026-10-03T09:49:26.628086Z"
---



All ~40 top-level constants -> constants.dart (skip CG/CC, SafeMode, LF, version). Replace 5 temp copies in reader.dart. Value tests generated from ruby -e dumps. Prevents future temp-dupe collisions. No barrel edits.