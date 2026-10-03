---
id: CHORE-xx3j8p
title: "lane: add update command (edit deps/priority/labels/description)"
status: doing
type: chore
priority: 3
labels:
- tooling
created: "2026-10-03T07:40:33.819776Z"
updated: "2026-10-03T07:41:41.440277Z"
---


Board management at port scale needs card edits; only add/comment/move exist. Implement lane update <id> [--deps ...] [-p N] [--labels ...] [-d ...] in ~/Work/lane, rebuild, verify with lane doctor.