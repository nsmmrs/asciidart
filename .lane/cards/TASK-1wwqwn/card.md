---
id: TASK-1wwqwn
title: "Revert CLI, extensions API and highlighter changes"
status: done
type: task
priority: 1
labels:
- retarget
parent: EPIC-9frzpm
created: "2026-10-04T13:42:23.157308Z"
updated: "2026-10-04T14:04:19.327021Z"
---



Reverse behavioral hunks of cli/options.rb, cli/invoker.rb, extensions.rb, syntax_highlighter*.rb, rouge_ext.rb, logging.rb, load.rb, convert.rb, asciidoctor.rb. E.g. #3868 --log-level, #3569 --sourcemap, #4425 -r splitting, #2895 handles?(doc, target), #2973 safe navigation, #3641/#4130 Rouge linenums, #3526 SafeMode.valueForName. Keep Dart-only additions (Mustache templates, init-config, -j).