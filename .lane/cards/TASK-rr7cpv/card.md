---
id: TASK-rr7cpv
title: "Remove Ruby-only CLI options (-r, -I, --eruby, -w)"
status: done
type: task
priority: 2
labels:
- cli
created: "2026-10-04T14:58:41.305415Z"
updated: "2026-10-04T17:49:29.880434Z"
---


User decision 2026-10-04: remove -r/--require, -I/--load-path, --eruby and -w/--warnings; they become unknown options. Update usage text, man page (regenerate .1 + help topics), CliOptions/Invoker/parallel plumbing, tests and e2e; README points to init-config for custom code.