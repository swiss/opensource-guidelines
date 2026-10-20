#!/usr/bin/env bash
#
# Write the listing page for one language directory of the published site.
#
#   tools/site-index.sh <lang> <dir>
#
# Lists the PDFs that are actually present in <dir>, which is what implements
# "a document that has no translation in this language is omitted": the render
# step never produced the file, so nothing links to it.
#
# Each entry is labelled with the document's title *in that language*, read out
# of the source's `ifeval::["{lang}" == "<lang>"]` block rather than from the
# filename.

set -euo pipefail

lang="${1:?usage: site-index.sh <lang> <dir>}"
dir="${2:?usage: site-index.sh <lang> <dir>}"

# `back` labels the link to the language chooser. A bare arrow gave no clue
# where it led, or that it led anywhere.
case "${lang}" in
    en) heading="Tools for Publishing Open Source Software"
        lead="Automatically rendered from the AsciiDoc sources in this repository."
        back="All languages" ;;
    de) heading="Hilfsmittel zur Veröffentlichung von Open-Source-Software"
        lead="Automatisch aus den AsciiDoc-Quellen dieses Repositorys gerendert."
        back="Alle Sprachen" ;;
    fr) heading="Outils pour la publication de logiciels open source"
        lead="Généré automatiquement à partir des sources AsciiDoc de ce dépôt."
        back="Toutes les langues" ;;
    it) heading="Strumenti per la pubblicazione di software open source"
        lead="Generato automaticamente dai sorgenti AsciiDoc di questo repository."
        back="Tutte le lingue" ;;
    rm) heading="Meds per publitgar software open source"
        lead="Generà automaticamain a partir da las funtaunas AsciiDoc da quest repositori."
        back="Tut las linguas" ;;
    *)  echo "site-index.sh: unknown language '${lang}'" >&2; exit 1 ;;
esac

escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# escape(), but for a value already in hand rather than on stdin. Pulled out of
# the format arguments below because `"$(printf ... | escape)"` inside a command
# substitution hides the exit status of everything in the pipe.
escaped() {
    local value="$1" out
    out=$(printf '%s' "${value}" | escape)
    printf '%s' "${out}"
}

# The title for this language, or the bare filename if the source has no block
# for it (which the render step should already have prevented).
doc_title() {
    local src="$1" title stem
    title=$(awk -v lang="${lang}" '
        /^ifeval::\["\{lang\}" == "/ { inblock = ($0 ~ "\"" lang "\"]$"); next }
        /^endif::\[\]/              { inblock = 0; next }
        inblock && /^= /            { sub(/^= /, ""); print; exit }
    ' "${src}")
    if [[ -z "${title}" ]]; then
        stem=$(basename "${src}" .adoc)
        title="${stem}"
    fi
    printf '%s' "${title}"
}

# basename -> source path, so a rendered PDF can be traced back to its document.
# `docs/partials/` is excluded: it holds fragments that are `include::`d into
# the documents, and a fragment has no PDF of its own to trace back to.
declare -A source_of
adoc_files=$(git ls-files '*.adoc' ':!docs/partials/*')
while IFS= read -r src; do
    [[ -n "${src}" ]] || continue
    stem=$(basename "${src}" .adoc)
    source_of["${stem}"]="${src}"
done <<<"${adoc_files}"

heading_html=$(escaped "${heading}")
lead_html=$(escaped "${lead}")
back_html=$(escaped "${back}")

{
    cat <<HTML
<!doctype html>
<html lang="${lang}">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${heading_html}</title>
<style>
  :root { color-scheme: light dark;
    --link: #0b57d0; --rule: rgba(128,128,128,.3); --wash: rgba(11,87,208,.08); }
  @media (prefers-color-scheme: dark) {
    :root { --link: #8ab4f8; --wash: rgba(138,180,248,.12); }
  }
  body { margin: 0 auto; padding: 2rem 1rem 4rem; max-width: 46rem;
    font: 16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif; }
  h1 { font-size: 1.5rem; line-height: 1.3; margin: 0 0 .5rem; }
  p.lead { margin: 0 0 2rem; opacity: .7; font-size: .9rem; }
  ul { list-style: none; margin: 0; padding: 0; }
  li { border-top: 1px solid var(--rule); }
  li:last-child { border-bottom: 1px solid var(--rule); }
  li a { display: flex; align-items: center; gap: .75rem;
    padding: .8rem .5rem .8rem .25rem; text-decoration: none; color: inherit; }
  li a .doc { flex: 1; }
  li a .title { display: block; color: var(--link); text-decoration: underline;
    text-underline-offset: .18em; }
  li a .name { display: block; font-size: .75rem; opacity: .6; margin-top: .15rem; }
  /* A badge rather than a chevron: these rows hand over a file, they do not
    navigate, and the reader deserves to know which before clicking. */
  li a .kind { flex: none; font-size: .7rem; font-weight: 600; letter-spacing: .06em;
    color: var(--link); border: 1px solid currentColor; border-radius: .25rem;
    padding: .05rem .35rem; opacity: .8; }
  li a:hover, li a:focus-visible { background: var(--wash); }
  li a:hover .title { text-decoration-thickness: 2px; }
  a:focus-visible { outline: 2px solid var(--link); outline-offset: -2px; }
  nav { margin-top: 2.5rem; font-size: .85rem; }
  nav a { color: var(--link); }
</style>
<h1>${heading_html}</h1>
<p class="lead">${lead_html}</p>
<ul>
HTML

    # index first, then the documents in natural order (em002, em002-1, em002-2-1, …).
    pdf_list=$(cd "${dir}" && find . -maxdepth 1 -type f -name '*.pdf' | sort -V)
    ordered=()
    [[ -f "${dir}/index.pdf" ]] && ordered+=("index.pdf")
    while IFS= read -r pdf; do
        # find prints ./name; the prefix comes straight back off.
        pdf="${pdf#./}"
        [[ -n "${pdf}" ]] || continue
        [[ "${pdf}" = "index.pdf" ]] && continue
        ordered+=("${pdf}")
    done <<<"${pdf_list}"

    for pdf in ${ordered+"${ordered[@]}"}; do
        stem="${pdf%.pdf}"
        src="${source_of[${stem}]:-}"
        if [[ -n "${src}" ]]; then
            label=$(doc_title "${src}")
        else
            label="${stem}"
        fi
        pdf_html=$(escaped "${pdf}")
        label_html=$(escaped "${label}")
        printf '  <li><a href="%s"><span class="doc"><span class="title">%s</span><span class="name">%s</span></span><span class="kind">PDF</span></a></li>\n' \
            "${pdf_html}" \
            "${label_html}" \
            "${pdf_html}"
    done

    cat <<HTML
</ul>
<nav><a href="../">&#8592; ${back_html}</a></nav>
</html>
HTML
} > "${dir}/index.html"

echo "wrote ${dir}/index.html ($((${#ordered[@]})) documents)"
