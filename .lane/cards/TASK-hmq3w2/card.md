---
id: TASK-hmq3w2
title: Remote URI fetching via async prefetch API
status: backlog
type: task
priority: 2
labels:
- io
deps:
- TASK-67yl6b
created: "2026-10-04T14:58:41.356987Z"
updated: "2026-10-04T14:58:41.356987Z"
---

User decision 2026-10-04: add async loadAsync/convertAsync (and file variants) that convert, collect the remote URIs the conversion needed (allow-uri-read includes, data-uri remote images), fetch them (dart:io HttpClient on the VM; fetch on JS via the EPIC-2qq14f I/O seam), and re-run with the cache until no new URI is needed. Sync API unchanged for local content; uncached remote content keeps today's behavior. Honor cache-uri. Tests with a local HTTP server; parity probe against the gem for remote includes.