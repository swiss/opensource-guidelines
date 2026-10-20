#!/usr/bin/env bash
#
# Build the whole published site locally.
#
#   tools/render-docs.sh [lang...]
#
# Every tracked .adoc rendered once per language into build/<lang>/, with the
# same per-language index pages and language chooser that CI publishes to
# GitHub Pages.
#
# It shares tools/site-index.sh and tools/site-root.sh with the workflow on
# purpose -- the point of building locally is to see what will be published,
# which a second implementation of the index would quietly stop doing.
#
# Reached through the `render-docs` devenv script, which is also what puts
# `open-govpress` on the PATH this needs.

set -euo pipefail

here=$(dirname "${BASH_SOURCE[0]}")
here=$(cd "${here}" && pwd)
root=$(cd "${here}/.." && pwd)
cd "${root}"

all_languages=(en de fr it rm)

if [[ "$#" -gt 0 ]]; then
    langs=("${@}")
else
    langs=("${all_languages[@]}")
fi

for lang in "${langs[@]}"; do
    case "${lang}" in
        en | de | fr | it | rm) ;;
        *)
            echo "render-docs: unknown language '${lang}' (expected en, de, fr, it or rm)" >&2
            exit 1
            ;;
    esac
done

# `docs/partials/` is excluded: it holds fragments that are `include::`d into
# the documents -- the shared document map, say -- and a fragment is not a
# document. On its own it has no title and no ifeval:: block, so it would render
# as a near-empty PDF and take a row in the language index.
tracked=$(git ls-files '*.adoc' ':!docs/partials/*')

for lang in "${langs[@]}"; do
    # A document may opt out of a language with `:l10n-languages:` in its
    # header; absent means all five. Skipping it here keeps an untranslated
    # document out of that language entirely, rather than rendering a PDF whose
    # body every ifeval:: guard rejected.
    docs=()
    while IFS= read -r doc; do
        [[ -n "${doc}" ]] || continue
        doc_langs=$(sed -n 's/^:l10n-languages:[[:space:]]*//p' "${doc}" | head -1)
        if [[ -z "${doc_langs}" ]] || grep -qw "${lang}" <<<"${doc_langs}"; then
            docs+=("${doc}")
        fi
    done <<<"${tracked}"

    echo "Rendering ${#docs[@]} documents in ${lang}..."
    mkdir -p "build/${lang}"
    open-govpress render --lang "${lang}" -o "build/${lang}" "${docs[@]}"
    ./tools/site-index.sh "${lang}" "build/${lang}"
done

./tools/site-root.sh build
echo "Site built in build/ -- open build/index.html"
