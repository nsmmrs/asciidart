// layout/flow/footnote.typ: footnote-ref
// (Not in the suite: a fixed height, as the twin's page.)
#set page(height: 100pt)
// Test references to footnotes.
A footnote #footnote[Hi]<fn> \
A reference to it @fn
