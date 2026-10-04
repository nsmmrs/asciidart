---
id: TASK-p0qg86
title: "Browser support: browser export condition, in-memory I/O, Playwright smoke + bundler check"
status: done
type: task
priority: 2
labels:
- npm
- js
- browser
parent: EPIC-2qq14f
deps:
- TASK-s39q3t
created: "2026-10-04T13:59:03.837203Z"
updated: "2026-10-04T18:42:05.705030Z"
---



browser.mjs wrapper as the package.json `browser` condition, no node:* imports. Behavior: in-memory only; file includes behave like missing files; a JS IncludeProcessor (TASK-9dh25p) is the supported way to supply include content. URI includes unsupported (no sync fetch) — document.

Tests: Playwright spec test/npm/browser.spec.mjs loads build/npm/browser.mjs in headless Chromium, converts the probe corpus inline (secure mode), compares with VM-generated goldens. Bundler check: `esbuild --bundle --platform=browser` on a one-line consumer succeeds with no Node-builtin errors.