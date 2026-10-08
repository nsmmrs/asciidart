// layout/flow/footnote.typ: footnote-space-collapsing
// (Not in the suite: a fixed height, as the twin's page.)
#set page(height: 100pt)
// Test space collapsing before footnote.
A#footnote[A] \
A #footnote[A]
