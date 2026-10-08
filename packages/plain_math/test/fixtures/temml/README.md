# Temml's screen tests

`expressions.json` is the LaTeX of the tables in Temml's screen test pages
(`test/katex-tests.md`, `test/mozilla-tests.md` and `test/LaTeXML-tests.md`
at Temml commit `4ffdf0e56577c426375d0b2818f8895edb5e5030`), written by
`tool/temml_corpus.dart`:

```sh
dart run tool/temml_corpus.dart path/to/temml/test
```

The pages collect the examples of KaTeX's screenshotter tests, the Mozilla
MathML torture test and LaTeXML's tests. Temml (© 2020 Ron Kok) and KaTeX
(© 2013-2020 Khan Academy and other contributors) are under the MIT
License:

> Permission is hereby granted, free of charge, to any person obtaining a
> copy of this software and associated documentation files (the
> "Software"), to deal in the Software without restriction, including
> without limitation the rights to use, copy, modify, merge, publish,
> distribute, sublicense, and/or sell copies of the Software, and to permit
> persons to whom the Software is furnished to do so, subject to the
> following conditions:
>
> The above copyright notice and this permission notice shall be included
> in all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
> OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
> MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN
> NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
> DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR
> OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE
> USE OR OTHER DEALINGS IN THE SOFTWARE.
