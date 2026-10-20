#!/usr/bin/env bash
# Generate the "four Cs" gear graphic, one SVG per language, into
# docs/assets/four-cs/.
#
# Why a generator rather than ten hand-written files: the graphic is four gears
# whose geometry is identical in every language and whose only translated parts
# are the "(Use)" gloss on Consumption and, in the `cases` variant, the two case
# labels. Ten copies of the same 60 teeth would drift the first time anyone
# nudged a radius.
#
# Why SVG rather than the PNGs this replaced: the labels become real text, so
# they are translatable, greppable and selectable in the PDF, and the file is a
# few kB instead of 200. The PNGs had no editable source in the repository at
# all -- this script is that source.
#
# The four C-words are deliberately NOT translated. `Consumption`,
# `Contribution`, `Collaboration` and `Creation` are terms of art -- the German,
# French, Italian and Romansh bodies all use them untranslated ("die 4 C", "les
# 4 C", "ils 4 C"), so translating them here would contradict the prose. The
# framing words around them are ordinary prose and are translated, including in
# the accessible name.
#
# Usage: tools/make-four-cs-svg.sh          # regenerate every file
set -euo pipefail

here=$(dirname "$0")
cd "${here}/.."

out_dir="docs/assets/four-cs"
mkdir -p "${out_dir}"

# Colours are read off the bitmaps this replaces, so the figure keeps its
# familiar look. They are the figure's own, not CD Bund tokens: this is a cited
# graphic, not a chart the project styles.
col_collab="#9e2b25"
col_consum="#7ba63f"
col_contrib="#2f6fa8"
col_create="#dd8127"

font='Liberation Sans, Helvetica, Arial, sans-serif'

# gear <cx> <cy> <r> <width> <teeth> <colour> <fill>
# A gear is an annulus plus N tooth rectangles placed by `rotate()`, which keeps
# the script free of trigonometry.
gear() {
    awk -v cx="$1" -v cy="$2" -v r="$3" -v w="$4" -v n="$5" -v c="$6" -v fill="$7" '
    BEGIN {
        printf "  <circle cx=\"%s\" cy=\"%s\" r=\"%s\" fill=\"%s\" stroke=\"%s\" stroke-width=\"%s\"/>\n", cx, cy, r, fill, c, w
        tw = r * 0.30; th = w * 0.62
        for (i = 0; i < n; i++) {
            a = 360.0 * i / n
            printf "  <rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" rx=\"%.2f\" fill=\"%s\" transform=\"rotate(%.3f %s %s)\"/>\n", \
                cx - tw / 2, cy - r - w / 2 - th + 1, tw, th + 2, tw * 0.18, c, a, cx, cy
        }
    }'
}

# emit <lang> <use-gloss> <name-lead> <case-a> <case-b>
# A non-empty <case-a> adds the divider variant used by Em002-5.
emit() {
    local lang="$1" use="$2" lead="$3" case_a="${4:-}" case_b="${5:-}"
    local name="four-cs" title="${lead}: Consumption, Contribution, Collaboration, Creation"
    if [[ -n "${case_a}" ]]; then
        name="four-cs-cases"
    fi

    {
        printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 620 600" width="620" height="600" role="img" aria-label="%s">\n' "${title}"
        printf '  <title>%s</title>\n' "${title}"

        # Collaboration is the gear the other three turn inside, so it is drawn
        # first and left unfilled.
        gear 290 312 232 40 14 "${col_collab}" none
        gear 192 196 124 42 12 "${col_consum}" "#ffffff"
        gear 479 206  84 34 10 "${col_contrib}" "#ffffff"
        gear 428 462  67 30 10 "${col_create}" "#ffffff"

        printf '  <text x="192" y="190" text-anchor="middle" font-family="%s" font-size="26" font-weight="bold" fill="#000000">Consumption</text>\n' "${font}"
        printf '  <text x="192" y="222" text-anchor="middle" font-family="%s" font-size="22" fill="#000000">(%s)</text>\n' "${font}" "${use}"
        printf '  <text x="479" y="215" text-anchor="middle" font-family="%s" font-size="24" font-weight="bold" fill="#000000">Contribution</text>\n' "${font}"
        printf '  <text x="428" y="470" text-anchor="middle" font-family="%s" font-size="21" font-weight="bold" fill="#000000">Creation</text>\n' "${font}"
        printf '  <text x="380" y="348" text-anchor="middle" font-family="%s" font-size="24" font-weight="bold" fill="#000000">Collaboration</text>\n' "${font}"

        if [[ -n "${case_a}" ]]; then
            printf '  <line x1="372" y1="8" x2="372" y2="592" stroke="#e00000" stroke-width="5"/>\n'
            printf '  <text x="250" y="34" text-anchor="middle" font-family="%s" font-size="26" font-weight="bold" fill="#000000">%s</text>\n' "${font}" "${case_a}"
            printf '  <text x="500" y="34" text-anchor="middle" font-family="%s" font-size="26" font-weight="bold" fill="#000000">%s</text>\n' "${font}" "${case_b}"
        fi

        printf '</svg>\n'
    } > "${out_dir}/${name}.${lang}.svg"
    echo "wrote ${out_dir}/${name}.${lang}.svg"
}

emit en "Use"         "The four Cs"
emit de "Nutzung"     "Die 4 C"
emit fr "utilisation" "Les 4 C"
emit it "uso"         "Le 4 C"
emit rm "utilisaziun" "Ils 4 C"

emit en "Use"         "The four Cs" "case a)"  "case b)"
emit de "Nutzung"     "Die 4 C"     "Fall a)"  "Fall b)"
emit fr "utilisation" "Les 4 C"     "cas a)"   "cas b)"
emit it "uso"         "Le 4 C"      "caso a)"  "caso b)"
emit rm "utilisaziun" "Ils 4 C"     "cas a)"   "cas b)"
