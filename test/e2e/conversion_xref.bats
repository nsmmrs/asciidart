#!/usr/bin/env bats
# Black-box conversion cases from features/xref.feature.
# Golden assertions: fixed-fragment assertions on the cross-reference link and
# target markup, derived from the feature's HTML/XML structure expectations.
# Each test maps 1:1 to a feature scenario (same order, same input).

load helpers

bats_require_minimum_version 1.5.0

setup_file() {
  check_exe
}

setup() {
  cd "$BATS_TEST_TMPDIR"
}

@test "xref: to block with explicit reftext to html" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<param-type-t>> to learn how it works.

.Parameterized Type <T>
[[param-type-t,that "<T>" thing]]
****
This sidebar describes what that <T> thing is all about.
****
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#param-type-t">that "&lt;T&gt;" thing</a>'
}

@test "xref: to block with explicit reftext to docbook" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<param-type-t>> to learn how it works.

.Parameterized Type <T>
[[param-type-t,that "<T>" thing]]
****
This sidebar describes what that <T> thing is all about.
****
EOF
  run --separate-stderr -- "$EXE" -e -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<xref linkend="param-type-t"/>'
  assert_contains actual.xml 'xml:id="param-type-t"'
  assert_contains actual.xml 'xreflabel="that &quot;&lt;T&gt;&quot; thing"'
  assert_contains actual.xml '<title>Parameterized Type &lt;T&gt;</title>'
  assert_contains actual.xml '<simpara>This sidebar describes what that &lt;T&gt; thing is all about.</simpara>'
}

@test "xref: to block with explicit reftext with formatting to html" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

There are cats, then there are the <<big-cats>>.

[[big-cats,*big* cats]]
== Big Cats

So ferocious.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#big-cats"><strong>big</strong> cats</a>'
}

@test "xref: to block with explicit reftext with formatting to docbook" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

There are cats, then there are the <<big-cats>>.

[[big-cats,*big* cats]]
== Big Cats

So ferocious.
EOF
  run --separate-stderr -- "$EXE" -e -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml '<xref linkend="big-cats"/>'
  assert_contains actual.xml 'xml:id="big-cats"'
  assert_contains actual.xml 'xreflabel="big cats"'
  assert_contains actual.xml '<title>Big Cats</title>'
}

@test "xref: full to numbered section" {
  cat > input.adoc <<'EOF'
:sectnums:
:xrefstyle: full

See <<sect-features>> to find a complete list of features.

== About

[#sect-features]
=== Features

All the features are listed in this section.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#sect-features">Section 1.1, &#8220;Features&#8221;</a>'
}

@test "xref: short to numbered section" {
  cat > input.adoc <<'EOF'
:sectnums:
:xrefstyle: short

See <<sect-features>> to find a complete list of features.

[#sect-features]
== Features

All the features are listed in this section.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#sect-features">Section 1</a>'
}

@test "xref: basic to unnumbered section" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<sect-features>> to find a complete list of features.

[#sect-features]
== Features

All the features are listed in this section.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#sect-features">Features</a>'
}

@test "xref: basic to numbered section with section-refsig disabled" {
  cat > input.adoc <<'EOF'
:sectnums:
:xrefstyle: full
:!section-refsig:

See <<sect-features>> to find a complete list of features.

[#sect-features]
== Features

All the features are listed in this section.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#sect-features">1, &#8220;Features&#8221;</a>'
}

@test "xref: full to numbered chapter" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:xrefstyle: full

See <<chap-features>> to find a complete list of features.

[#chap-features]
== Features

All the features are listed in this chapter.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#chap-features">Chapter 1, <em>Features</em></a>'
}

@test "xref: short to numbered chapter" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:xrefstyle: short

See <<chap-features>> to find a complete list of features.

[#chap-features]
== Features

All the features are listed in this chapter.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#chap-features">Chapter 1</a>'
}

@test "xref: basic to numbered chapter" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:xrefstyle: basic

See <<chap-features>> to find a complete list of features.

[#chap-features]
== Features

All the features are listed in this chapter.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#chap-features"><em>Features</em></a>'
}

@test "xref: basic to unnumbered chapter" {
  cat > input.adoc <<'EOF'
:doctype: book
:xrefstyle: full

See <<chap-features>> to find a complete list of features.

[#chap-features]
== Features

All the features are listed in this chapter.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#chap-features"><em>Features</em></a>'
}

@test "xref: to chapter with custom chapter-refsig" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:xrefstyle: full
:chapter-refsig: Ch

See <<chap-features>> to find a complete list of features.

[#chap-features]
== Features

All the features are listed in this chapter.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#chap-features">Ch 1, <em>Features</em></a>'
}

@test "xref: full to numbered part" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:partnums:
:xrefstyle: full

[preface]
= Preface

See <<p1>> for an introduction to the language.

[#p1]
= Language

== Syntax

This chapter covers the syntax.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#p1">Part I, &#8220;Language&#8221;</a>'
}

@test "xref: short to numbered part" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:partnums:
:xrefstyle: short

[preface]
= Preface

See <<p1>> for an introduction to the language.

[#p1]
= Language

== Syntax

This chapter covers the syntax.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#p1">Part I</a>'
}

@test "xref: basic to numbered part" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:partnums:
:xrefstyle: basic

[preface]
= Preface

See <<p1>> for an introduction to the language.

[#p1]
= Language

== Syntax

This chapter covers the syntax.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#p1">Language</a>'
}

@test "xref: basic to unnumbered part" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:xrefstyle: full

[preface]
= Preface

See <<p1>> for an introduction to the language.

[#p1]
= Language

== Syntax

This chapter covers the syntax.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#p1">Language</a>'
}

@test "xref: to part with custom part-refsig" {
  cat > input.adoc <<'EOF'
:doctype: book
:sectnums:
:partnums:
:xrefstyle: full
:part-refsig: P

[preface]
= Preface

See <<p1>> for an introduction to the language.

[#p1]
= Language

== Syntax

This chapter covers the syntax.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#p1">P I, &#8220;Language&#8221;</a>'
}

@test "xref: full to numbered appendix" {
  cat > input.adoc <<'EOF'
:sectnums:
:xrefstyle: full

See <<app-features>> to find a complete list of features.

[appendix#app-features]
== Features

All the features are listed in this appendix.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#app-features">Appendix A, <em>Features</em></a>'
}

@test "xref: short to numbered appendix" {
  cat > input.adoc <<'EOF'
:sectnums:
:xrefstyle: short

See <<app-features>> to find a complete list of features.

[appendix#app-features]
== Features

All the features are listed in this appendix.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#app-features">Appendix A</a>'
}

@test "xref: full to appendix with section numbering disabled" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<app-features>> to find a complete list of features.

[appendix#app-features]
== Features

All the features are listed in this appendix.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#app-features">Appendix A, <em>Features</em></a>'
}

@test "xref: full to numbered formal table" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<tbl-features>> to find a table of features.

.Features
[#tbl-features%autowidth]
|===
|Text formatting |Formats text for display.
|===
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#tbl-features">Table 1, &#8220;Features&#8221;</a>'
}

@test "xref: short to numbered formal table" {
  cat > input.adoc <<'EOF'
:xrefstyle: short

See <<tbl-features>> to find a table of features.

.Features
[#tbl-features%autowidth]
|===
|Text formatting |Formats text for display.
|===
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#tbl-features">Table 1</a>'
}

@test "xref: basic to numbered formal table with caption disabled" {
  cat > input.adoc <<'EOF'
:xrefstyle: full
:!table-caption:

See <<tbl-features>> to find a table of features.

.Features
[#tbl-features%autowidth]
|===
|Text formatting |Formats text for display.
|===
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#tbl-features">Features</a>'
}

@test "xref: to numbered formal table with custom caption prefix" {
  cat > input.adoc <<'EOF'
:xrefstyle: full
:table-caption: Tbl

See <<tbl-features>> to find a table of features.

.Features
[#tbl-features%autowidth]
|===
|Text formatting |Formats text for display.
|===
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#tbl-features">Tbl 1, &#8220;Features&#8221;</a>'
}

@test "xref: basic to formal paragraph" {
  cat > input.adoc <<'EOF'
<<terms>> apply.

.Terms and conditions
[#terms]
These are the terms and conditions.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#terms">Terms and conditions</a>'
  assert_contains actual.html 'id="terms"'
  assert_contains actual.html '<div class="title">Terms and conditions</div>'
  assert_contains actual.html '<p>These are the terms and conditions.</p>'
}

@test "xref: full to formal image block" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

Behold, <<tiger>>!

.The ferocious Ghostscript tiger
[#tiger]
image::tiger.svg[Ghostscript tiger]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#tiger">Figure 1, &#8220;The ferocious Ghostscript tiger&#8221;</a>'
  assert_contains actual.html 'id="tiger"'
  assert_contains actual.html '<img src="tiger.svg" alt="Ghostscript tiger">'
  assert_contains actual.html 'Figure 1. The ferocious Ghostscript tiger'
}

@test "xref: short to formal image block" {
  cat > input.adoc <<'EOF'
:xrefstyle: short

Behold, <<tiger>>!

.The ferocious Ghostscript tiger
[#tiger]
image::tiger.svg[Ghostscript tiger]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#tiger">Figure 1</a>'
  assert_contains actual.html 'id="tiger"'
  assert_contains actual.html '<img src="tiger.svg" alt="Ghostscript tiger">'
  assert_contains actual.html 'Figure 1. The ferocious Ghostscript tiger'
}

@test "xref: full to blocks with explicit captions" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<diagram-1>> and <<diagram-2>>.

.Managing Orders
[#diagram-1,caption="Diagram {counter:diag-number}. "]
image::managing-orders.png[Managing Orders]

.Managing Inventory
[#diagram-2,caption="Diagram {counter:diag-number}. "]
image::managing-inventory.png[Managing Inventory]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#diagram-1">Diagram 1, &#8220;Managing Orders&#8221;</a>'
  assert_contains actual.html '<a href="#diagram-2">Diagram 2, &#8220;Managing Inventory&#8221;</a>'
  assert_contains actual.html 'Diagram 1. Managing Orders'
  assert_contains actual.html 'Diagram 2. Managing Inventory'
}

@test "xref: full to block with empty caption" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<ex1>>.

.Title
[#ex1,caption=]
====
content
====
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#ex1">Title</a>'
  assert_contains actual.html 'id="ex1"'
  assert_contains actual.html 'class="exampleblock"'
  assert_contains actual.html '<div class="title">Title</div>'
}

@test "xref: short to blocks with explicit captions" {
  cat > input.adoc <<'EOF'
:xrefstyle: short

See <<diagram-1>> and <<diagram-2>>.

.Managing Orders
[#diagram-1,caption="Diagram {counter:diag-number}. "]
image::managing-orders.png[Managing Orders]

.Managing Inventory
[#diagram-2,caption="Diagram {counter:diag-number}. "]
image::managing-inventory.png[Managing Inventory]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#diagram-1">Diagram 1</a>'
  assert_contains actual.html '<a href="#diagram-2">Diagram 2</a>'
  assert_contains actual.html 'Diagram 1. Managing Orders'
  assert_contains actual.html 'Diagram 2. Managing Inventory'
}

@test "xref: short to block with empty caption" {
  cat > input.adoc <<'EOF'
:xrefstyle: short

See <<ex1>>.

.Title
[#ex1,caption=]
====
content
====
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#ex1">Title</a>'
  assert_contains actual.html 'id="ex1"'
  assert_contains actual.html 'class="exampleblock"'
  assert_contains actual.html '<div class="title">Title</div>'
}

@test "xref: basic to unnumbered formal listing block" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

See <<data>> to find the data used in this report.

.Data
[#data]
....
a
b
c
....
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#data">Data</a>'
}

@test "xref: uses title to refer to formal admonition block" {
  cat > input.adoc <<'EOF'
:xrefstyle: full

Recall in <<essential-tip-1>>, we told you how to speed up this process.

.Essential tip #1
[#essential-tip-1]
TIP: You can speed up this process by pressing the turbo button.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#essential-tip-1">Essential tip #1</a>'
}

@test "xref: from asciidoc table cell to section" {
  cat > input.adoc <<'EOF'
|===
a|See <<_install>>
|===

== Install

Instructions go here.
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_install">Install</a>'
  assert_contains actual.html '<h2 id="_install">Install</h2>'
  assert_contains actual.html '<p>Instructions go here.</p>'
}

@test "xref: using title of target section" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two, continued from <<Section One>>

refer to <<Section One>>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<h2 id="_section_one">Section One</h2>'
  assert_contains actual.html 'id="_section_two_continued_from_section_one"'
  assert_contains actual.html '<a href="#_section_one">Section One</a>'
}

@test "xref: using reftext of target section to html" {
  cat > input.adoc <<'EOF'
[reftext="the first section"]
== Section One

content

== Section Two

refer to <<the first section>>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one">the first section</a>'
}

@test "xref: using reftext of target section to docbook" {
  cat > input.adoc <<'EOF'
[reftext="the first section"]
== Section One

content

== Section Two

refer to <<the first section>>
EOF
  run --separate-stderr -- "$EXE" -e -b docbook5 -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.xml
  assert_contains actual.xml 'xml:id="_section_one"'
  assert_contains actual.xml 'xreflabel="the first section"'
  assert_contains actual.xml '<xref linkend="_section_one"/>'
}

@test "xref: using formatted title of target section" {
  cat > input.adoc <<'EOF'
== Section *One*

content

== Section Two

refer to <<Section *One*>>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one">Section <strong>One</strong></a>'
}

@test "xref: to section whose title contains stem expression" {
  cat > input.adoc <<'EOF'
:stem: latexmath

[#squares]
== Squares (stem:[x^2])

content

== Section Two

refer to <<squares>>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#squares">Squares (\(x^2\))</a>'
}

@test "xref: natural reference not processed in compat mode" {
  cat > input.adoc <<'EOF'
:compat-mode:

== Section One

content

== Section Two

refer to <<Section One>>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#Section One">[Section One]</a>'
}

@test "xref: natural reference not processed when sectids is unset" {
  cat > input.adoc <<'EOF'
:!sectids:

== Section One

content

== Section Two

refer to <<Section One>>
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#Section One">[Section One]</a>'
}

@test "xref: macro text parsed as attributes when signature found" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two

refer to xref:_section_one[role=next]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one" class="next">Section One</a>'
}

@test "xref: macro text not parsed as attributes when signature not found" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two

refer to xref:_section_one[One, Section One]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one">One, Section One</a>'
}

@test "xref: macro uses whole quoted text as link text when signature found" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two

refer to xref:_section_one["Section One == Starting Point"]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one">Section One == Starting Point</a>'
}

@test "xref: macro keeps quoted text literal when signature not found" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two

refer to xref:_section_one["The Premier Section"]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one">"The Premier Section"</a>'
}

@test "xref: macro text not parsed as attributes when no attributes found" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two

refer to xref:_section_one[Section One
= First Section]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one">Section One'
  assert_contains actual.html '= First Section</a>'
}

@test "xref: macro does not parse formatted text as attributes" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two

refer to xref:_section_one[[.role]#Section
One#]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one"><span class="role">Section'
  assert_contains actual.html 'One</span></a>'
}

@test "xref: macro unescapes quotes when text is parsed as attributes" {
  cat > input.adoc <<'EOF'
== Section One

content

== Section Two

refer to xref:_section_one["\"The Premier Section\"",role=spotlight]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_section_one" class="spotlight">"The Premier Section"</a>'
}

@test "xref: xrefstyle overridden for part of document" {
  cat > input.adoc <<'EOF'
:xrefstyle: full
:doctype: book
:sectnums:

== Foo

refer to <<#_bar>>

== Bar
:xrefstyle: short

refer to xref:#_foo[xrefstyle=short]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_bar">Chapter 2, <em>Bar</em></a>'
  assert_contains actual.html '<a href="#_foo">Chapter 1</a>'
}

@test "xref: xrefstyle overridden on a single macro" {
  cat > input.adoc <<'EOF'
:xrefstyle: full
:doctype: book
:sectnums:

== Foo

content

== Bar

refer to <<#_foo>>

refer to xref:#_foo[xrefstyle=short]
EOF
  run --separate-stderr -- "$EXE" -e -o - input.adoc
  [ "$status" -eq 0 ]
  [ "$stderr" = "" ]
  printf '%s\n' "$output" > actual.html
  assert_contains actual.html '<a href="#_foo">Chapter 1, <em>Foo</em></a>'
  assert_contains actual.html '<a href="#_foo">Chapter 1</a>'
}
