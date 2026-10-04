---
id: TASK-ncfxdm
title: "Revert data, stylesheets and man page to 2.0.26"
status: done
type: task
priority: 1
labels:
- retarget
parent: EPIC-9frzpm
created: "2026-10-04T13:42:23.103579Z"
updated: "2026-10-04T13:44:03.080042Z"
---



Copy gem data/ (stylesheets, locale/attributes.adoc, reference/syntax.adoc) and man/ over the repo; drop data/locale/attributes-sl.adoc. Regenerate lib/src/data.g.dart and lib/src/cli/help_topics.g.dart (tool/embed_data.dart + dart format). Tests: stylesheets_test, cli/help_topics_test.