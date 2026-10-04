---
id: EPIC-9frzpm
title: Retarget master to Asciidoctor 2.0.26
status: doing
type: epic
priority: 1
labels:
- retarget
created: "2026-10-04T13:42:23.064622Z"
updated: "2026-10-04T13:42:39.670719Z"
---


Master was ported from upstream main @ 30fb8cd5 (2.1.0.alpha.0, unreleased). Retarget to real 2.0.26 behavior, verified byte-identical against the published gem. The 2.1 work is preserved on branch `2.1.0` (769d164). References: gem 2.0.26 sources under ~/.local/share/mise/installs/ruby/4.0.7/lib/ruby/gems/4.0.0/gems/asciidoctor-2.0.26; main side ~/Work/ports/asciidoctor @ 30fb8cd5 (read-only). Checklist: upstream CHANGELOG 'Unreleased' section (~60 entries). Ruby lib delta ~1960 lines / 36 files.