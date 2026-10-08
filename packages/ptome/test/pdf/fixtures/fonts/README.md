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

`notoserif-features.ttf` is Noto Serif 2.015 (© 2022 The Noto Project
Authors, SIL Open Font License 1.1), subset to Basic Latin with its
`onum`, `smcp`, `liga` and `kern` features (as in plain_pdf's test fonts).

`libertinus-scripts.otf` is Libertinus Serif Regular 7.051 (© 2012-2024
The Libertinus Project Authors, SIL Open Font License 1.1, from
typst/typst-assets), subset to Basic Latin with its `sups` and `subs`
features, for typographic superscripts:

```sh
pyftsubset LibertinusSerif-Regular.otf --unicodes=U+0020-007E \
  --layout-features=sups,subs --name-IDs='*' \
  --output-file=libertinus-scripts.otf
```
