<!-- Filed from spike TASK-2df9vp (subagent regexp-gap-spike, read-only research). Required reading for all port workers touching regexes. -->

Research complete. All evidence gathered read-only; no files written. Deliverable follows.

---

# Ruby → Dart RegExp Gap Catalog — Asciidoctor Port

**Top finding:** the port is very feasible — Dart `RegExp` is JavaScript-semantics (verified via [api.dart.dev RegExp](https://api.dart.dev/dart-core/RegExp-class.html)), and this codebase already contains its own JS-compatibility catalog in the form of `RUBY_ENGINE == 'opal'` branches. Port workers should treat those branches as authoritative: **port the opal variant of the 4 branched patterns, fix the `\p{…}` char-class constants (invalid names in Dart), apply the mechanical flag rules, and hand-roll `StringScanner`.** Everything else ports nearly verbatim. Details below.

**Method.** Read in full: `lib/asciidoctor/rx.rb` (728 lines), `lib/asciidoctor/attribute_list.rb`, `lib/asciidoctor/helpers.rb`, `QUOTE_SUBS`/`REPLACEMENTS`/CC defs in `lib/asciidoctor.rb`. Grep-surveyed all of `lib/` for `(?…)` group extensions, `\p{}`, `\A\Z\z\G\R\K\X\h`, possessive/atomic groups, conditionals, inline/scoped flags, `/i`/`/x`, `Regexp.*`, `MatchData`, `$~ $& $' $`` $n $+`, `=~ !~`, `match/match?/scan/gsub/sub/split/partition/tr/squeeze/delete`. Verified Dart behavior via web fetch of [RegExp](https://api.dart.dev/dart-core/RegExp-class.html), [RegExp constructor](https://api.dart.dev/dart-core/RegExp/RegExp.html), [RegExpMatch](https://api.dart.dev/dart-core/RegExpMatch-class.html), [MDN Unicode property escapes](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Regular_expressions/Unicode_character_class_escape), and Dart SDK changelog/issues (lookbehind since 2.3). Negative results below ("none") are from exhaustive grep, not sampling.

---

## 1. BLOCKER — must rewrite (naive port throws `FormatException` or silently miscompiles)

### B1. `\p{Alpha}`, `\p{Alnum}`, `\p{Blank}`, `\p{Word}` are invalid in Dart — touches ~45 patterns
- Defined `lib/asciidoctor.rb:434-437`, interpolated into nearly every `Rx` constant.
- MDN-verified: a lone `\p{…}` name must be a `General_Category` value or an ECMA spec binary property (`Alphabetic`, `White_Space`, …). `Alpha`, `Alnum`, `Blank`, `Word` are POSIX/UTS#18-Annex-C names — **not valid**. Failure mode is double-bad: *without* `unicode:true`, JS/Dart treats `\p` as identity escape = literal `p` (**silent catastrophic miscompile**, e.g. `[^\p{Word}-]` becomes "not one of `p{Word}-`"); *with* `unicode:true`, it throws `FormatException`.
- **Rewrite (Unicode-preserving, recommended):**
  - `\p{Alpha}` → `\p{Alphabetic}` + `unicode:true` (EXACT — same Unicode property; only Unicode-version drift between Ruby's Onigmo and Dart's engine).
  - `\p{Alnum}` → **must split the Ruby alias** (`CC_ALNUM`/`CG_ALNUM` are the same string in Ruby but need different Dart fragments): in-class → `\p{Alphabetic}\p{Decimal_Number}` (adjacent = union, e.g. `[\p{Alphabetic}\p{Decimal_Number}_.:...]`); standalone → `(?:\p{Alphabetic}|\p{Decimal_Number})`. Near-exact (Ruby Alnum = letters + decimal digits).
  - `\p{Blank}` → `[ \t]` (EXACT — Ruby Blank is space+tab only). Used standalone only: `rx.rb:525/527` (InlineLinkRx), `converter/manpage.rb:30` (WrappedIndentRx).
  - `\p{Word}` → `\w` + `unicode:true` (NEAR-EXACT on both sides of the aisle: works identically in-class `[\w…]` and standalone; JS-unicode-`\w` = Alphabetic+Mark+Decimal_Number+Connector_Punctuation+Join_Control ≈ Ruby word chars; edge diffs only in Cf/format chars).
- ASCII-only fallback (probable Asciidoctor.js parity, NOT recommended): skip `unicode:true`, map to `\w`/`[A-Za-z]`/`[A-Za-z0-9]`/`[ \t]`. Cost: non-ASCII author names, IDs, e-mails diverge from Ruby. (I attempted to retrieve Asciidoctor.js's proven JS mappings via GitHub API/grep.app; rate-limited/blocked — marked unconfirmed.)

### B2. `\A` and `\Z` anchors — unsupported
- Sites: `rx.rb:142` (AttributeEntryPassMacroRx), `rx.rb:723` (UriSniffRx), `converter/html5.rb:33-34` (SvgPreambleRx, SvgStartTagRx), `converter/manpage.rb:23` (LiteralBackslashRx `/\A\\|…/`), `rx.rb:586` (`(\Z)` in InlinePassRx compat variant). Without `unicode:true`, `\A` silently means literal `A`.
- **Rewrite:** for the first four, **port the adjacent opal `^` variant** (`rx.rb:140,721`, `html5.rb:30-31`) with NO `multiLine` (Dart `^`/`$` without multiLine = string anchors = exact `\A`/`\z` equivalent). manpage `:23` → `RegExp(r'^\\|(\u001b)?\\')`, no flags. For `rx.rb:586` `(\Z)` (no opal variant exists): → `((?=\n?(?![\s\S])))` — zero-width, captures empty, preserves group numbering ($2), and is correct even with `multiLine:true` (a naive `(\n?$)` would wrongly match at every line end under multiLine).

### B3. Identity escapes that throw under `unicode:true` (required by B1)
- `rx.rb:464` InlineEmailRx `[\\>:/]` — `\>` is invalid under `u` flag (`>` is not a SyntaxCharacter). → bare `>` (always literal in a class). **Construction-time `FormatException` otherwise.**
- `lib/asciidoctor.rb:453,455,459` QUOTE_SUBS (double, single, monospaced constrained) — `` \` `` (escaped backtick) ×6, invalid under `u`. → bare `` ` ``. Same consequence.
- Audit of all other escapes: `\-` occurs only inside classes (allowed); `\#` in `rx.rb:245` is a Ruby-literal `#` escape, not a regex escape; `\/`, `\<`, `\'`, `\_`, `\,`, `\;`, `\:`, `\=` etc. do not occur in any pattern; `\c`/`\f` lookalikes in `manpage.rb:25-26,32` are literal backslash+letter troff text (`\\c`, `\\f`), portable verbatim.

### B4. InlineLinkRx backreference-to-unset-group — MUST port the opal variant
- Ruby form `rx.rb:527` uses `\2(...)&gt;` where group 2 is `()` that only participates on one alternation branch. Ruby: backref to non-participating group *fails*; Dart/JS: *matches empty* → different language. The codebase documents this itself (`rx.rb:524`: "In JavaScript, a back reference succeeds if not set; invert the logic").
- **Port `rx.rb:525` (opal) verbatim** (group numbering is identical: `$1,prefix $2,marker $3,scheme … $8`), with `multiLine:true` (for `(^|…)`) + `unicode:true` (for `\w`-from-Word). Keep `[\s\S]` for `CC_ALL` (R4), no `dotAll` needed. Call sites `substitutors.rb:537-633` (`$1,$3,$6`) then behave identically.

### B5. Replacement strings use Ruby `\1`/`\2` — Dart uses `$1`
- Sites: `lib/asciidoctor/load.rb:45` (`'\1'+NULL`, `'\1'`), `substitutors.rb:971` (`#{PASS_START}\\1#{PASS_END}`), `converter/manpage.rb:678` (`\\1..\2`), `manpage.rb:735` (`'\1'`), `syntax_highlighter/pygments.rb:34,42,44,47` (`PreTagCs`, `LinenoSpanTagCs` = `'…\1…'` templates). In Dart `\1` in a replacement inserts a literal control char.
- **Rule:** mechanical `\n` → `$n` (`'<pre>$1</pre>'`, `'${passStart}$1${passEnd}'`, `'$1\n$2'`). Only `\1`,`\2` occur; no `\k<>`, `\&`, `` \` ``, `\'` in replacements.

### B6. `gsub` with Hash replacement — no Dart equivalent
- `substitutors.rb:171,177`: `text.gsub SpecialCharsRx, SpecialCharsTr` (`SpecialCharsRx=/[<&>]/`, `SpecialCharsTr` map, defined `:8-9`). → `text.replaceAllMapped(specialCharsRx, (m) => specialCharsTr[m.group(0)]!)`. Only two sites, both in `sub_specialchars`.

### B7. `StringScanner` — no Dart equivalent (only user: `attribute_list.rb`)
- Used API (all in `attribute_list.rb:52-216`): `::StringScanner.new`, `scan` (NameRx `:207`, delimiter-boundary `:211`, quote-boundary `:215`), `skip` (`:199,:203`), `peek 1` (`:99,:186`), `get_byte` (`:102,:105,:114,:120`), `unscan` (`:115,:131`), `eos?` (`:72,:109`), `string` (`:110`). See §4 for the full replacement contract.

### B8. `String#split` differs from Dart in three ways — helpers required
- (a) **Limit arg** — Dart `split` has none. Sites: `parser.rb:792,803` (`split ', ',2`), `substitutors.rb:220` (`split ':',3`), `parser.rb:1972` (`split nil,3`), `converter/html5.rb:1056,1091` (`split '/',2`), `:1096` (`split ',',2`). Helper: `indexOf`-loop, max-n parts, last part = unsplit remainder.
- (b) **Whitespace splits** — `abstract_node.rb:197,252` bare `split`, `parser.rb:1972` `split nil`: Ruby strips leading runs and drops trailing empties. `trim().split(RegExp(r'\s+'))` (+ limit helper for the `,3` case).
- (c) **Trailing empties** — Dart *keeps* them (`'a,'.split(',')` → `['a','']`); Ruby limit-less split *drops* them. Divergent sites: `parser.rb:1956` (`split AuthorDelimiterRx` — trailing `;` would yield a phantom empty author), `substitutors.rb:388` (`items.split(delim)` → `submenus.pop` could pop `''`), `parser.rb:244`, `document.rb:1053`, `substitutors.rb:367` (guarded), `attribute_list.rb:156` (guarded by `unless opt.empty?`). Helper `rubySplit` that drops trailing empties for limit-less splits. `split …, -1` sites (`parser.rb:2478`, `reader.rb:930,933,946,949`, all `split LF,-1`) match Dart's default exactly. Regex-split capture rule: Dart never includes groups; Ruby includes *capturing* groups — `AuthorDelimiterRx` (`rx.rb:31`) is already non-capturing, keep it that way.

### B9. `^`/`$` are line anchors in Ruby, string anchors in Dart by default
- **Blanket rule (exact, always safe): any pattern whose source contains `^` or `$` (including via `CC_EOL`) gets `multiLine:true`.** Ruby code can never rely on string-only `^` (it uses `\A` for that), so this is semantics-preserving on both single- and multi-line inputs. Patterns where it is load-bearing (multi-line input): `TagDirectiveRx` (`rx.rb:108`, `(?=$…)` on raw `each_line` lines incl. `\n`), `CalloutScanRx` (`:374`, `text.scan` multi-line, `parser.rb:1139`), `CalloutSourceRx` (`:376`, multi-line gsub, `substitutors.rb:925`), `HardLineBreakRx` (port Ruby form `rx.rb:628` + multiLine — the opal `:625` adds `/m` for exactly this reason), `InlineAnchorScanRx` (`:447`), REPLACEMENTS #5 (`asciidoctor.rb:501`, `^|$`), all constrained QUOTE_SUBS (`(^|…)`), both InlinePassRx (`:585-586`), InlineLinkRx-opal (`(^|…)`). Footnote: JS `^` also matches after `\r`/`\u2028\u2029`, Ruby only after `\n` — negligible (inputs are `\n`-split, rstripped lines).

## 2. WORKAROUND-OK — supported with flag/rewrite

- **W1. Ruby `/m` flag** → mechanical: `/m` affects *only* `.` in Ruby, so `/m` ⟺ `dotAll:true` exactly. Recommended primary form is flag-free token swap: `CC_ALL` → `[\s\S]`, `CC_ANY` → `[^\n]` (exact, including the `\r`/`\u2028\u2029` corner where JS `.` without dotAll differs from Ruby `.`). `/m`-with-no-dot patterns (`TagDirectiveRx`) need only multiLine. Literal-dot-with-`/m` occurs only in skipped Ruby branches (`:142`, html5 `:33`) and `WrapperTagRx` (`pygments.rb:154` `(.*)` → `([\s\S]*)`).
- **W2. Lookbehind** — sole site `syntax_highlighter/pygments.rb:149` `StyledLinenoSpanTagRx (?<=^|<span></span>)`. Dart VM supports lookbehind (2.3+, SDK changelog/issues verified); web builds depend on the browser. **Recommend the rewrite** (used at `:42` with the `\1` template `:146`): `RegExp(r'(^|<span></span>)<span style="[^"]+">( *\d+) ?</span>')`, replacement `'$1<span class="linenos">$3</span>'`. The `rx.rb:694` TODO confirms the codebase otherwise deliberately avoids lookbehind.
- **W3. InlinePassRx `\2` unset-backref** (`rx.rb:585`) — `(?=(\[)|\+)` then `\2(…)`. Diverges from Ruby only on pathological inputs (requires ` x-…]` crafted text); Asciidoctor.js ships this pattern verbatim into JS. **Port verbatim** (do *not* "fix" to `\[` — that would introduce a *new* divergence on the `\\(?=\[)` path).
- **W4. `\b`** — 5 sites (`rx.rb:108,464`; `html5.rb:25`; `substitutors.rb:60`; `pygments.rb:154`). Dart `\b` is ASCII-only even under `unicode:true`; Ruby is Unicode-aware. All sites abut ASCII (`tag::`, TLDs, HTML tags) — negligible.
- **W5. `\s` superset** — JS `\s` adds NBSP etc. over Ruby's ASCII `[ \t\r\n\f\v]`. Not negligible after all: the corpus parity check (`tool/corpus_parity.dart`) found French text with a no-break space before `:` converting differently. **Rule (R16):** write Ruby's `\s` as `[ \t\n\v\f\r]` and `\S` as `[^ \t\n\v\f\r]` (inside a class, ` \t\n\v\f\r`); keep `[\s\S]` for any character. Likewise Ruby's `strip`/`lstrip`/`rstrip` remove only ASCII whitespace and NUL: use `trimAscii`/`trimLeftAscii`/`trimRightAscii` (`ruby_semantics.dart`), never `String.trim`.
- **W6. `.` vs `\r`** — mooted by the W1 `[^\n]`/`[\s\S]` recommendation.
- **W7. Empty groups** — `(?:|…)`, `(|…)`, `(|--)` (CalloutRx — always participates, so `\1`/`\3` backrefs are safe), `extensions.rb:657` `'(){0}'` (group stays unset → Dart `group(1)==null`, same as Ruby nil). All valid Dart.
- **W8. Dynamic construction** — `rx.rb:372,378` (CalloutRxMap + `Regexp.escape`), `table.rb:484` (`/#{::Regexp.escape sep}/`), `extensions.rb:657` (interpolated name/format). → string interpolation + `RegExp.escape` (both docs-verified). Preserve group numbering (Map variants shift groups; call-site indexes already account for it — `substitutors.rb:1368-1378`).
- **W9. Named groups from user extension regexps** — `substitutors.rb:313,316` (`$~.names`, `$~[:target]`, `$~[:content]`). → `m.groupNames` / `m.namedGroup('target')` (docs-verified, incl. throws-on-unknown semantics matching the `rescue nil`). No named-group *definitions* exist in lib's own patterns (verified).
- **W10. Match-context vars** — `$&` (whole match, ~40 sites) → `group(0)`; `$'` (`parser.rb:774` admonition strip, `:1301` `$'.lstrip` reftext fallback) → `input.substring(m.end)`; `` $` `` (`parser.rb:1189` `$`.count LF`) → `input.substring(0,m.start)` + newline count; `pre_match/post_match` (`parser.rb:2385,2539`) → same substrings; `$n` (full site list verified in parser/reader/document/substitutors/converters) → nullable `group(n)`; `match.to_a` (`parser.rb:1976`) → `[for (i=1..groupCount) group(i)]`. `$+` never used; `` $` `` only once.
- **W11. Anchored scan** — `matchAsPrefix` is Dart's primitive for it (docs-verified) — basis for §4.
- **W12. Unicode-version drift** — Onigmo vs Dart property tables may differ on newest code points; accept.
- **W13. `\uXXXX`** — `rx.rb:275,285` (`\u2022`), `?\u0096`/`?\u0097` PASS markers, `?\u001b` manpage ESC, `?\u0018`/`?\u007f` CAN/DEL, `?\0` NULL: all valid in Dart strings and (for `\u2022`) patterns, both modes.
- **W14. `match` with position arg, `Regexp.new/compile/union`** — none occur (verified); all `.match`/`.match?` calls are single-argument.

## 3. SUPPORTED — port verbatim (modulo `#{…}`→`${…}`, `/…/,%r(…)`→raw strings)
`(?:…)` (all), `(?=…)`/`(?!…)` (all, incl. `(?!^)` in RevisionInfoLineRx, nested/quantified lookaheads in CalloutRx), captures, backrefs to participating groups (`\1`–`\8`, incl. `\1\2\1` in `MarkdownThematicBreakRx`/`ExtLayoutBreakRx`, `\4` in InlinePassMacroRx, `\5?`/`\7` in InlinePassRx), alternation, greedy/lazy quantifiers, classes/negation/ranges, `\d\D` and `\s\S` (as R16), `\n\r\t`, `^$`+multiLine, `.` per W1. **Verified absent from all of lib/:** possessive/atomic `(?>`, `*+`), conditionals `(?(`, comments `(?#`, inline/scoped flags `(?i)`/`(?i:)`, `/i`, `/x`, `\z`, `\G`, `\R`, `\K`, `\X`, `\h`, POSIX `[::]`, `!~`, `sub!`/`gsub!`, `str[rx]`/`slice(rx)`/`index(rx)`, `partition(rx)`. No `coding:` magic comments; encoding work is byte-level BOM handling (`helpers.rb:85-134`), not regex.

## 4. Rewrite rules for port workers
- **R1** Constants: `CC_ALL→[\s\S]`, `CC_ANY→[^\n]`, `CC_EOL→$`, `CG_BLANK→` tab plus the Unicode space separators (Ruby's `\p{Blank}`, see `cgBlank`; once listed here as `[ \t]`, which the corpus check disproved), Alpha→`\p{Alphabetic}`, Alnum→split fragments (B1), Word→`\w`.
- **R2** Any pattern containing `\w`-from-Word or `\p{…}` gets `unicode:true`. (List: AuthorInfoLineRx, AttributeEntry/ReferenceRx, InvalidAttributeNameCharsRx, BlockAnchor/AttributeList/AttributeLineRx, SetextSectionTitleRx, InlineSectionAnchorRx, InvalidSectionIdCharsRx, CustomBlockMacroRx, all four InlineAnchorRx, InlineEmailRx, InlineFootnoteMacroRx, MacroNameRx, InlineMenuMacroRx, InlineMenuRx, both InlinePassRx, InlineXrefMacroRx, UriSniffRx, InlineLinkRx, QUOTE_SUBS ×12, REPLACEMENTS #5/#9, attribute_list NameRx. Everything else: no `unicode`.)
- **R3** Any pattern containing `^`/`$` gets `multiLine:true` (B9; always safe).
- **R4** `/m` → nothing (covered by R1 token swap); only `WrapperTagRx` needs its literal `(.*)`→`([\s\S]*)`.
- **R5** Port the **opal** branch of InlineLinkRx, AttributeEntryPassMacroRx, UriSniffRx, SvgPreambleRx/SvgStartTagRx; port the **Ruby** branch of HardLineBreakRx (+multiLine). (Rationale: opal branches exist exactly where JS semantics differ — backref-to-unset, `\A`, `^`.)
- **R6** `\A`→`^` (no multiLine); `(\Z)`→`((?=\n?(?![\s\S])))` (B2).
- **R7** Scrub `\>`→`>` (`rx.rb:464`), `` \` ``→`` ` ``×6 (`asciidoctor.rb:453,455,459`).
- **R8** `=~`→`firstMatch` (groups used) / `hasMatch` (boolean); `match?`→`hasMatch`; `.match`→`firstMatch!`.
- **R9** `gsub(rx){}`→`replaceAllMapped`, `gsub(rx,str)`→`replaceAll` with R10, `gsub(rx,hash)`→R11, `sub`→`replaceFirst[Mapped]`, `scan{}`→`for (m in rx.allMatches(t))`. Capture groups to locals at callback top (Dart has no clobberable `$~` — strictly safer).
- **R10** Replacement `\1`→`$1`, `\2`→`$2` (B5 site list).
- **R11** `gsub SpecialCharsRx, SpecialCharsTr` → `replaceAllMapped` + map lookup.
- **R12** `$~`→pass the `Match`; `$&`→`group(0)`; `$n`→`group(n)` (nullable — preserve the exact `if/elsif` guard structure, e.g. `extract_passthroughs` `$3.length` at `substitutors.rb:1047` is safe only inside the `$4`-truthy branch); `$'`/`` $` ``/`pre_match`/`post_match`→`substring(m.end)`/`substring(0,m.start)`; `match.to_a`→group list; `$~.names`/`$~[:s]`→`groupNames`/`namedGroup`.
- **R13** `split` → §B8 helpers (limit / whitespace / trailing-empty rules); keep split-regexes capture-free.
- **R14**Interpolate with `${…}`; wrap user input in `RegExp.escape`; prefer raw strings `r'…'`.
- **R15** `StringScanner` → §5 scanner; `partition`/`tr`/`delete`/`squeeze`/`chop`/`chomp`/`succ`/`unpack`/`byteslice`/`str.count`/`sprintf`/`%`-format → small helpers (§6); multi-arg `start_with?`/`end_with?` (8+ sites, e.g. `parser.rb:573,600,2060,2122`) → `startsWithAny`/`endsWithAny`; `slice(i,len)`→`substring(i,i+len)`; `str[0]`→same; `.chr`→`[0]` (astral edge noted); `each_line` keeps `\n`, `split('\n')` drops it — mind in `prepare_source_string` port.

## 5. StringScanner replacement strategy (Dart)
Single small `AttrScanner` class suffices — only `attribute_list.rb` uses it, with a tightly bounded contract:
- State: `input`, `pos`. `scan(RegExp)` = `matchAsPrefix(input, pos)` (docs-verified primitive), advance to `m.end` on hit, return `m.group(0)` else null. `skip(RegExp)` = same but return match *length* (`int?`) — load-bearing at `:108` (`((name = scan_name) && skip_blank) || 0`).
- `peek(1)` = next *char* (or empty at EOS — `:99` `case peek` must not crash at EOS); `get_byte` = consume one char, null at EOS (`:120` `when nil`). All `get_byte`/`peek`/`unscan` sites handle ASCII only (quotes, `=`, `,`), so UTF-16-unit stepping is exact here.
- `unscan` is always called immediately after one `get_byte` (`:115,:131`) → `pos -= 1`, but implement a one-deep last-advance stack for safety.
- `eos?` = `pos >= input.length`; `string` = `input` (`:110` `rstrip.end_with?(delimiter)`).
- The four patterns port as: `NameRx→RegExp(r'\w[\w-]*', unicode:true)`, `BlankRx→RegExp(r'[ \t]+')`, `SkipRx→RegExp(r'[ \t]*(,|$)', multiLine:true)`, BoundaryRx quot/apos/comma verbatim with `[^\n]` dots + multiLine (multi-line macro contents make non-greedy `.*?` + lookahead the exact Ruby behavior).
- No backtracking across methods is needed: the parser is a single deterministic loop (`parse` `:64-78`).

## 6. Companion String-API notes (co-located with regex call sites)
`tr` single-char (`substitutors.rb:1350`, `parser.rb:1980-91`, `cli/*`) → `replaceAll`; `delete ' '/DEL` (`attribute_list.rb:155`, `document.rb:264`, `substitutors.rb:264-267`) → `replaceAll(c,'')`; `squeeze(' '/DEL)` (`document.rb:118`, `docbook5.rb:644`, `substitutors.rb:262`) → collapse-runs helper; `chop` (`substitutors.rb:364`, `parser.rb:994`, `table.rb:528`) → drop-last-char; `chomp` (helpers, `manpage.rb:678`) → drop-one-trailing-`\n`/suffix; `succ` (`helpers.rb:326`) → Ruby-succ helper; `unpack/byteslice/bytesize/force_encoding` (helpers BOM path, `cli/options.rb:97`) → `utf8.encode/decode`; `sprintf`/`sub_placeholder` (`substitutors.rb:1468`) → interpolation. `is_delimited_block?` (`parser.rb:976-1011`) and `uniform?` (`:2777`) are pure string loops — no regex action.

## 7. Residual risks & recommended verification
1. `\p{Alphabetic}`/`\p{Decimal_Number}`/`\w`-unicode exactness vs Onigmo — validate with the repo's attribute/author/i18n tests, esp. accented author names (`AuthorInfoLineRx`), non-ASCII IDs, `InvalidSectionIdCharsRx`.
2. `\w`-unicode Join_Control edge (`\u200c\u200d` as word chars) — one test with ZWJ in an attribute name settles it.
3. `split AuthorDelimiterRx` trailing-`;` case and menu `a,`-trailing-delimiter case — add unit tests for the B8 helpers.
4. `CalloutExtractRxMap` group-shift parity — covered by callout tests; keep pattern text identical.
5. This environment has Dart SDK 3.13.5 (`mise` flutter bin) but the task forbade writing files, so no executable probes were run — every Dart claim above is docs- or spec-verified as cited; a port worker should still run a one-time constructor smoke test (`FormatException` sweep over all ported patterns) since several failures are construction-time.