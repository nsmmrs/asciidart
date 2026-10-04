---
id: TASK-nc7zn5
title: "Revert parser, document, reader and substitution compliance changes"
status: done
type: task
priority: 1
labels:
- retarget
parent: EPIC-9frzpm
created: "2026-10-04T13:42:23.142329Z"
updated: "2026-10-04T13:57:39.870281Z"
---



Reverse behavioral hunks of parser.rb, document.rb, reader.rb, substitutors.rb, table.rb, abstract_*.rb, section.rb, inline.rb, attribute_list.rb, path_resolver.rb, helpers.rb, rx.rb. E.g. #1121 tilde open blocks, #4151 level-0 special section, #4147/#4306 attribute names, #3881 table strips, #3252/#2218 olist start, #4139/#2618 section id/toclevels, #4300/#3437 front matter, #3661 asset dir, #4814/#2262/#4873 TOC/parts, #2284 remote include warning, #3313 linenums, #4442 cxx, #3220 Inline#text alias.