# Changelog

## 0.1.0-dev (unreleased)

- Line breaking (UAX #14, Unicode 18.0.0), moved from plain_pdf with its
  history; it passes LineBreakTest.txt.
- Full case mapping (Unicode 17.0.0), generated from UnicodeData.txt and
  SpecialCasing.txt: `upperCase`, and `lowerCase` with or without the
  Final_Sigma rule, checked against Ruby 4.0.7 and Node.js for every code
  point. It replaces ptome's Ruby-generated table and plain_highlighting's
  use of the platform's tables.
