#!/usr/bin/env bash
#
# Fail on AsciiDoc that does not parse, on cross-references that do not
# resolve, and on citations with no reference entry.
#
#   tools/check-asciidoc.sh [file.adoc...]
#
# With no arguments, checks every tracked .adoc; the git hook passes the files
# it is about to commit.
#
# git-hooks.nix ships no AsciiDoc linter, and the render pipeline is the only
# thing that reads these files -- so without this, a broken include or an
# unterminated block is first noticed by the CI render matrix, several minutes
# and five parallel jobs later. asciidoctor parses in well under a second per
# document, so the same class of mistake can be caught at commit time.
#
# Every document is checked once per language. The bodies are five
# `ifeval::["{lang}" == "<lang>"]` blocks, so a conditional left unterminated in
# the Romansh block is simply invisible while parsing as English, which is what
# a single default-language pass would do.
#
# Runs from the repository root. Both checks below resolve paths from there, and
# it is where prek invokes this in the hook and in CI.

set -euo pipefail

here=$(dirname "${BASH_SOURCE[0]}")
here=$(cd "${here}" && pwd)
root=$(cd "${here}/.." && pwd)
cd "${root}"

# The five languages render-docs builds. A document that opts out of one with
# `:l10n-languages:` still has to parse in it -- the guards just yield an empty
# body -- so there is no reason to read that attribute here.
languages=(en de fr it rm)

files=()
if [[ "$#" -gt 0 ]]; then
    files=("${@}")
else
    tracked=$(git ls-files '*.adoc')
    while IFS= read -r file; do
        [[ -n "${file}" ]] || continue
        files+=("${file}")
    done <<<"${tracked}"
fi

if [[ "${#files[@]}" -eq 0 ]]; then
    exit 0
fi

status=0

# ---------------------------------------------------------------------------
# Parse, convert, and fail on anything asciidoctor diagnoses at INFO or above.
# ---------------------------------------------------------------------------
#
# `--out-file -` with stdout thrown away, not `--out-file /dev/null`: asciidoctor
# special-cases that one path and returns the loaded document *without ever
# converting it* -- lib/asciidoctor/convert.rb reads
#
#     when '/dev/null' then return load input, options
#
# so nothing the converter diagnoses could reach this gate at any
# --failure-level. An unresolved <<xref>> is diagnosed during conversion, which
# is why this used to be documented as out of reach: the symptom was real, the
# explanation was not. Converting for real and discarding the HTML costs nothing
# measurable (2.5s either way across the whole repository), because the parse is
# the expensive half.
#
# `--failure-level=INFO` and `--verbose` are then both needed, for different
# reasons: an unresolved cross-reference is logged at INFO, so INFO has to be
# fatal *and* has to be logged at all. asciidoctor has no --log-level; -v /
# --verbose is its only lever on the logger, and it lowers the threshold to
# DEBUG. WARN stays fatal as before -- asciidoctor otherwise prints
# "unterminated listing block" and still exits 0.
#
# Lowering the threshold to DEBUG also turns on 35 lines per language that
# open-govpress's own extensions provoke ("unknown style for literal block:
# mermaid", "unknown name for block macro: field", ditto "signature"): plain
# asciidoctor has no such extensions, so it says so, once per block. Those are
# filtered out rather than explained away in this comment, because DEBUG sits
# below INFO and can therefore never change the exit code -- the lines are noise
# by construction, and 175 of them per run would train people to stop reading
# this gate's output. The filter keys on the level label, not on the three
# messages, so a fourth open-govpress extension needs no change here and nothing
# that could ever fail the gate is hidden.
#
# One asciidoctor per language rather than per file-and-language: Ruby startup
# dominates (0.29s per invocation, whatever the document's size), so batching the
# whole repository costs 2.5s where 100 separate runs cost 29s. The price is
# paid by exactly one message: the INFO line for an unresolved cross-reference
# reads "possible invalid reference: <key>" and names no file and no line, so a
# batched failure says which reference dangles but not where. That is worth 26
# seconds a commit, because the key is its own locator -- `git grep -n '<<key'`
# lands on it -- while WARN and ERROR, which is nearly everything else, do name
# their file and line.
for lang in "${languages[@]}"; do
    if ! {
        asciidoctor \
            --safe \
            --verbose \
            --failure-level=INFO \
            --attribute lang="${lang}" \
            --out-file - \
            "${files[@]}" 2>&1 >/dev/null
    } | { grep -v ': DEBUG: ' >&2 || true; }; then
        echo "check-asciidoc.sh: failed to check as '${lang}'" >&2
        status=1
    fi
done

# ---------------------------------------------------------------------------
# Every cited reference key has a reference entry defining it.
# ---------------------------------------------------------------------------
#
# The check above cannot do this and no log level makes it: a citation is the
# literal text `[St2024]`, and a reference entry is a description-list term
# `[St2024]::` (or, once the lists are centralised, a bibliography anchor
# `[[[St2024]]]`). Nothing connects the two, so a citation whose entry was never
# written -- or, now that the lists are moving into tagged partials, whose entry
# a `tags=` selector did not select -- renders as a bracketed label pointing at
# nothing, in silence, in asciidoctor and in open-govpress alike.
#
# asciidoctor-reducer resolves the includes and the `ifeval::` guards and prints
# the flattened source, which is the only honest way to ask what a given language
# actually ends up containing: it applies the same tag selection that will
# silently drop an entry, so a mis-tagged include shows up here as the citation
# losing its definition. It ships with the asciidoctor package devenv.nix
# already pulls in.
#
# Always the whole tracked corpus, whatever arguments were passed, because a
# citation and its entry live in different documents: only Em002 and Em002-7
# carry reference lists, and every other document says so in prose ("The
# references ... can be found in the Em002 Strategic Guidelines"). Checking a
# document against its own entries alone would report every citation in Em002-1.
# The flip side is that this cannot catch an entry that went missing from one
# list while another list still defines the key.
marker='// check-asciidoc: file '

manifest=''
tracked=$(git ls-files '*.adoc')
while IFS= read -r file; do
    [[ -n "${file}" ]] || continue
    # Fragments are not documents -- render-docs and site-index.sh exclude them
    # too. They are read through the documents that include them, which is the
    # point: that is where the tag selection happens.
    case "${file}" in
        docs/partials/*) continue ;;
        *) ;;
    esac
    manifest+="${marker}${file}"$'\n'
    manifest+="include::${file}[]"$'\n'
done <<<"${tracked}"

# The classes are negated rather than spelled [[:alpha:]] and [[:alnum:]] so that
# the umlaut in [BöB] is a key character whether awk reads characters (a UTF-8
# locale) or bytes (the C locale a bare CI runner hands it).
#
# A bracketed token is a citation only when what precedes it is prose. The text
# of an inline macro looks identical -- `link:em002-2.pdf[Em002-2]` -- but the
# bracket there follows the macro target, so requiring a blank, a `_`, an opening
# quote or the start of the line in front of it separates the two. A line that is
# nothing but `[...]` is a block attribute list, never a citation.
#
# Inside a footnote the closing bracket is written `\]`, because Asciidoctor ends
# the footnote at the first bare one. The backslash belongs to the escape and not
# to the key, so it is dropped along with the bracket.
program=$(
    cat <<'AWK'
BEGIN {
    keychar  = "[^][:space:],;:=%#*<>&+/\"'?!()|[]"
    keystart = "[^][:space:],;:=%#*<>&+/\"'?!()|.0-9_[-]"
    key      = keystart keychar "*"
    entry_dl = "^\\[" key "\\]::"
    entry_bib = "^\\[\\[\\[" key "\\]\\]\\]"
    citation = "(^|[[:space:]_(\"'])\\[" key "\\]"
}

index($0, marker) == 1 { file = substr($0, length(marker) + 1); next }

# A comment renders as nothing, so a key inside one is not a citation. The
# partials discuss their own keys in their headers, which would otherwise read
# as a dozen citations apiece.
$0 ~ /^\/\/\/\/+[[:space:]]*$/ { commented = !commented; next }
commented { next }
$0 ~ /^\/\// { next }

$0 ~ entry_bib { k = $0; sub(/^\[\[\[/, "", k); sub(/\]\]\].*/, "", k); defined[k] = 1; next }
$0 ~ entry_dl  { k = $0; sub(/^\[/, "", k); sub(/\]::.*/, "", k); defined[k] = 1; next }

$0 ~ /^\[[^]]*\]$/ { next }

{
    rest = $0
    while (match(rest, citation)) {
        k = substr(rest, RSTART, RLENGTH)
        sub(/^.*\[/, "", k)
        sub(/\\?\]$/, "", k)
        if (length(k) > 1 && !((k SUBSEP file) in seen)) {
            seen[k SUBSEP file] = 1
            cited[++n] = k SUBSEP file
        }
        rest = substr(rest, RSTART + RLENGTH)
    }
}

END {
    for (i = 1; i <= n; i++) {
        split(cited[i], part, SUBSEP)
        if (!(part[1] in defined)) print lang "\t" part[2] "\t" part[1]
    }
}
AWK
)

# Keys cited with no reference entry anywhere, deliberately left that way while
# their owner decides what they should point at. Everything else is fatal
# already; delete an entry here the moment its citation is fixed or dropped, and
# the check becomes fatal for it -- a stale entry is reported as such, so the
# list cannot quietly outlive the problem it documents.
#
# Empty, and meant to stay that way: it held OSI (docs/em002-3.adoc) and OSI2019
# (docs/em002-1.adoc) until the owner decided what they should point at, and both
# citations were corrected. Add a key here only to park a citation an owner has
# yet to rule on, one per line with the document and the question, like
#
#     known_unresolved=(
#         Xy2026  # docs/em002-4.adoc -- entry promised for the 2026 revision
#     )
known_unresolved=()

if ! unresolved=$(
    for lang in "${languages[@]}"; do
        printf '%s' "${manifest}" |
            asciidoctor-reducer \
                --attribute lang="${lang}" \
                --attribute doctype=book \
                --output - \
                - |
            awk -v lang="${lang}" -v marker="${marker}" "${program}"
    done
); then
    echo "check-asciidoc.sh: could not flatten the corpus to check citations" >&2
    exit 1
fi

pending=()
while IFS=$'\t' read -r lang file key; do
    [[ -n "${key}" ]] || continue
    if [[ " ${known_unresolved[*]} " == *" ${key} "* ]]; then
        case " ${pending[*]-} " in
            *" ${key} "*) ;;
            *) pending+=("${key}") ;;
        esac
    else
        echo "check-asciidoc.sh: ${file} (${lang}): [${key}] is cited with no reference entry" >&2
        status=1
    fi
done <<<"${unresolved}"

for key in "${known_unresolved[@]}"; do
    case " ${pending[*]-} " in
        *" ${key} "*) ;;
        *)
            echo "check-asciidoc.sh: [${key}] now resolves; drop it from known_unresolved in ${BASH_SOURCE[0]}" >&2
            status=1
            ;;
    esac
done

if [[ "${#pending[@]}" -gt 0 ]]; then
    echo "check-asciidoc.sh: still cited with no reference entry, by agreement: ${pending[*]}" >&2
fi

exit "${status}"
