use std::io::{self, BufRead, Write};

fn main() {
    let stdin = io::stdin();
    let mut out = io::BufWriter::new(io::stdout());
    for line in stdin.lock().lines() {
        let line = line.unwrap();
        let mut parts = line.split(' ');
        let iso = parts.next().unwrap();
        let left: usize = parts.next().unwrap().parse().unwrap();
        let right: usize = parts.next().unwrap().parse().unwrap();
        let word = parts.next().unwrap();
        let bytes: [u8; 2] = iso.as_bytes().try_into().unwrap();
        let lang = hypher::Lang::from_iso(bytes).expect(iso);
        let syllables: Vec<&str> =
            hypher::hyphenate_bounded(word, lang, left, right).collect();
        writeln!(out, "{}", syllables.join("-")).unwrap();
    }
}
