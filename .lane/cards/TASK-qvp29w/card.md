---
id: TASK-qvp29w
title: "Revert converter output changes (html5, docbook5, manpage)"
status: backlog
type: task
priority: 1
labels:
- retarget
parent: EPIC-9frzpm
deps:
- TASK-ncfxdm
created: "2026-10-04T13:42:23.121168Z"
updated: "2026-10-04T13:42:23.121168Z"
---

Reverse behavioral hunks of converter/html5.rb, docbook5.rb, manpage.rb between 30fb8cd5 and gem 2.0.26 in lib/src/html5.dart, docbook5.dart, manpage.dart. E.g. #4160 table width, #2947 quote roles, #4182/#4482 manpage spacing, #4101 thematic break role, Wistia, #4143 reproducible generator, #4804 nohighlight, #3656 link=self, #4311 inline image id. One upstream entry per commit.