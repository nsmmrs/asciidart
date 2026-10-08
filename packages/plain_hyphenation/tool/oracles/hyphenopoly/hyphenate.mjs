// The Hyphenopoly oracle for test/oracles_test.dart: reads
// {"lang", "left", "right", "words"} as JSON on standard input and prints
// the words hyphenated with "-", as JSON.
import {readFile} from "node:fs/promises";
import hyphenopoly from "hyphenopoly";

const chunks = [];
for await (const chunk of process.stdin) chunks.push(chunk);
const {lang, left, right, words} = JSON.parse(Buffer.concat(chunks));
const hyphenator = hyphenopoly.config({
    "hyphen": "-",
    "leftminPerLang": {[lang]: left},
    "loader": (file, patDir) => readFile(new URL(file, patDir)),
    "minWordLength": 1,
    "require": [lang],
    "rightminPerLang": {[lang]: right}
});
const hyphenate = await hyphenator.get(lang);
process.stdout.write(JSON.stringify(words.map((word) => hyphenate(word))));
