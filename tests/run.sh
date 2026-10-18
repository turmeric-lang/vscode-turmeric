#!/usr/bin/env bash
# tests/run.sh -- structure and pattern checks for the TextMate grammar. There
# is no TextMate engine here: it validates the JSON, that the grammar is wired
# into package.json, and each match regex against inputs it must and must not
# match. Python's re is not Oniguruma, so this guards against rot, not
# rendering. Skips (exit 0) when python3 is missing.
set -uo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
fails=0
TMGRAMMAR="$ROOT/syntaxes/turmeric.tmLanguage.json"

# ------------------------------------------------------------- vscode ------
if ! command -v python3 >/dev/null 2>&1; then
    echo "SKIP: python3 not available -- TextMate grammar not exercised"
else
    if python3 - "$TMGRAMMAR" "$ROOT/package.json" <<'PY'
import json, re, sys
gpath, ppath = sys.argv[1], sys.argv[2]
g = json.load(open(gpath))            # raises if malformed
pkg = json.load(open(ppath))
bad = []

grammars = pkg.get("contributes", {}).get("grammars", [])
if not any(x.get("scopeName") == g["scopeName"] for x in grammars):
    bad.append("package.json does not wire up scopeName %r" % g["scopeName"])

repo = g["repository"]
# (rule, text, should_match) -- only constructs where Python re and Oniguruma agree.
cases = [
    ("lang-directive",  "#lang saffron",                  True),
    ("lang-directive",  "#lang turmeric/sweet stringed",  True),
    ("lang-directive",  "(defn f [] 0)",                  False),
    ("doc-comment",     ";;; add -- adds.",               True),
    ("definition",      "(defn add [a b] (+ a b))",       True),
    ("definition",      "(defstruct Point [x : float])",  True),
    ("type-annotation", "(defn f [a : int] : int 0)",     True),
    ("type-annotation", "(defn f [a :int] :int 0)",       True),
    ("param-attribute", "(defn f [^mut w : World] 0)",    True),
    ("number",          "(+ 7.1 2)",                      True),
    ("dispatch",        "#map{:a 1}",                     True),
    # `is?` and `set!` end in a non-word char, so a trailing `\b` matches
    # nothing -- the bug this pair exists to catch.
    ("special-form",    "(is? x Circle)",                 True),
    ("special-form",    "(set! x 1)",                     True),
    ("special-form",    "(with-region f)",                True),
    ("special-form",    "(isotope x)",                    False),
    ("special-form",    "(setter x)",                     False),
    # r7rs-lang-plan R9: the Scheme layer.
    ("scheme-boolean",  "(list #t #false)",               True),
    ("scheme-boolean",  "#tail",                          False),
    ("scheme-char",     "(write #\\space)",               True),
    ("scheme-char",     "#\\x41",                          True),
    ("scheme-number",   "#x1F #e1.5",                     True),
    ("scheme-datum-comment", "#;(skip)",                  True),
    ("scheme-special-form", "(define-library (m))",       True),
    ("scheme-special-form", "(let* ((a 1)) a)",           True),
    ("scheme-special-form", "(beginner x)",               False),
]
for rule, text, want in cases:
    r = repo.get(rule)
    if not r or "match" not in r:
        bad.append("rule %r has no `match`" % rule); continue
    if bool(re.search(r["match"], text)) != want:
        bad.append("%s: %r should%s match" % (rule, text, "" if want else " not"))

# the float literal must be taken whole
m = re.search(repo["number"]["match"], "(+ 7.1 2)")
if not m or m.group(0) != "7.1":
    bad.append("number: 7.1 tokenised as %r" % (m.group(0) if m else None))

# The Scheme layer is scoped to `#lang r7rs`: its region begins only there.
sf = repo.get("scheme-file", {})
if not re.search(sf.get("begin", "(?!)"), "#lang r7rs"):
    bad.append("scheme-file: does not begin at `#lang r7rs`")
for other in ("#lang saffron", "#lang turmeric", "(defn f [] 0)"):
    if re.search(sf.get("begin", "(?!)"), other):
        bad.append("scheme-file: begins at %r" % other)
if g["patterns"][0].get("include") != "#scheme-file":
    bad.append("scheme-file is not the first top-level pattern")

if bad:
    for b in bad: print("       " + b)
    sys.exit(1)
print("ok   vscode: grammar JSON valid, wired up, %d pattern checks pass" % len(cases))
PY
    then :; else
        echo "FAIL vscode: TextMate grammar checks failed"
        fails=$((fails + 1))
    fi
fi

if [ "$fails" -ne 0 ]; then
    echo "vscode-turmeric: $fails check(s) failed"
    exit 1
fi
echo "vscode-turmeric: all checks passed"
