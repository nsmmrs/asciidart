# Goldens

`generate.rb` writes the corpus's goldens (`packages/ptome/test/corpus`):
for each case and each format in its `case.yml`, the file the Asciidoctor
command line writes, in `<case>/expected/<release>/<format>/`.

```sh
cd packages/ptome_corpus_tools/goldens
export BUNDLE_GEMFILE=$PWD/asciidoctor-2.0.26/Gemfile \
  BUNDLE_PATH=~/.cache/ascii-docs/bundle-asciidoctor-2.0.26
bundle install
bundle exec ruby generate.rb -j 8 ../../ptome/test/corpus          # every case
bundle exec ruby generate.rb ../../ptome/test/corpus my-new-case   # one case
```

Each release is a bundle of its own (`<release>/Gemfile`, `Gemfile.lock`):
Asciidoctor, asciidoctor-pdf and asciidoctor-epub3 at the release, with the
optional gems for what ptome implements (asciimath, text-hyphen) and no
others (no Rouge, Pygments or CodeRay: ptome behaves as Asciidoctor does
without them).

A case is converted as `asciidoctor -b <backend> -D <dir> input.adoc` (the
gem's own command-line code, `Asciidoctor::Cli::Invoker`), with the
attributes of the corpus's `goldens.yml` and the case's, from two copies of
the case in different directories; a result that differs between them (a
path in the output) is refused. A conversion that fails writes no golden.
Existing goldens are kept unless `--replace`.
