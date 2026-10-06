# Test fonts

`yrsa-regular-latin.ttf` and `yrsa-italic-latin.ttf` are Yrsa Regular and
Italic (Rosetta Type, https://github.com/rosettatype/yrsa-rasa), under the
SIL Open Font License 1.1 (`OFL.txt`), subset to Basic Latin with their
`liga` and `kern` features:

```sh
pyftsubset Yrsa-Regular.ttf --unicodes=U+0020-007E \
  --layout-features=liga,kern --name-IDs='*' \
  --output-file=yrsa-regular-latin.ttf
```

The modern PDF engine's tests set text in them (ligatures, GPOS kerning).
