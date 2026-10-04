---
id: BUG-fwc380
title: "Parser uses partial substitutions where Asciidoctor applies full ones (wrong section IDs)"
status: done
type: bug
priority: 1
labels:
- parity
created: "2026-10-04T14:32:08.747599Z"
updated: "2026-10-04T15:04:28.363669Z"
---



Repro: `== A -- B` gets id="_a_b" in the Dart port but id="_ab" in Asciidoctor 2.0.26 (the gem builds the ID from the fully substituted title, so the replacement-produced &#8201;&#8212;&#8201; is stripped). Cause: parser.dart still routes through porting-era 'TEMP-SEAM (parser)' helpers (_titleText, _subSpecialchars, _subAttributes, _applyHeaderSubs, _applyAttributeValueSubs, _parseAttributes, _resolveSubs, _commitSubs, the quote-credit partial subs) that only apply specialcharacters + attributes, instead of the real substitutors/AbstractBlock.title. Fix: route them to the real substitutions, delete the seams, and add the affected constructs to test/parity (headings with replacements/quotes/macros, quote credits, auto-generated IDs). Verify with tool/parity.sh. Found while rewording parser comments (TASK-b98cxf).