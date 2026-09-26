#!/usr/bin/env bash
#
# Write the index of archived builds at the root of the published site.
#
#   tools/site-archive.sh <dir>
#
# <dir> is the accumulated site tree, which holds a copy of every build that is
# still retained:
#
#   <dir>/tags/<tag>/          a released version, kept forever
#   <dir>/commits/<short>/     a build of main, pruned to the newest few
#
# Each of those carries the `build-meta.txt` that site-publish.sh wrote, and
# this page is generated purely by reading them back -- so a build that was
# pruned from the tree disappears from the listing by construction, and no
# separate bookkeeping file can drift out of sync with what is actually there.

set -euo pipefail

dir="${1:?usage: site-archive.sh <dir>}"

escape() { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'; }

# escape(), but for a value already in hand rather than on stdin. Pulled out of
# the format arguments below because `"$(printf ... | escape)"` inside a command
# substitution hides the exit status of everything in the pipe.
escaped() {
    local value="$1" out
    out=$(printf '%s' "${value}" | escape)
    printf '%s' "${out}"
}

# Read one `key<TAB>value` field out of a build-meta.txt.
meta_field() {
    local file="$1" key="$2"
    awk -F'\t' -v k="${key}" '$1 == k { sub(/^[^\t]*\t/, ""); print; exit }' "${file}"
}

# Emit the <li> entries for one archive directory, newest first.
#
# Sorting is on the `epoch` field rather than on the directory name: commit
# directories are named by hash, which has no useful order, and tags sort by
# release date rather than by the accident of their spelling.
emit_entries() {
    local subdir="$1" rows=() metas name epoch sorted
    local meta date subject subdir_html name_html subject_html when_html

    [[ -d "${dir}/${subdir}" ]] || return 0

    metas=$(find "${dir}/${subdir}" -mindepth 2 -maxdepth 2 -name build-meta.txt | sort)

    while IFS= read -r meta; do
        [[ -f "${meta}" ]] || continue
        name=$(dirname "${meta}")
        name=$(basename "${name}")
        epoch=$(meta_field "${meta}" epoch)
        rows+=("${epoch:-0}	${name}	${meta}")
    done <<<"${metas}"

    [[ ${#rows[@]} -gt 0 ]] || return 0

    sorted=$(printf '%s\n' "${rows[@]}" | sort -rn -t'	' -k1,1)

    while IFS=$'\t' read -r _ name meta; do
        [[ -n "${meta}" ]] || continue
        date=$(meta_field "${meta}" date)
        subject=$(meta_field "${meta}" subject)
        subdir_html=$(escaped "${subdir}")
        name_html=$(escaped "${name}")
        subject_html=$(escaped "${subject}")
        when_html=$(escaped "${date%T*}")
        printf '  <li><a href="%s/%s/"><span class="build"><span class="ref">%s</span><span class="subject">%s</span></span><span class="when">%s</span></a></li>\n' \
            "${subdir_html}" \
            "${name_html}" \
            "${name_html}" \
            "${subject_html}" \
            "${when_html}"
    done <<<"${sorted}"
}

{
    cat <<'HTML'
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Archived builds &#8212; Open Source Guidelines</title>
<style>
  :root { color-scheme: light dark;
    --link: #0b57d0; --rule: rgba(128,128,128,.3); --wash: rgba(11,87,208,.08); }
  @media (prefers-color-scheme: dark) {
    :root { --link: #8ab4f8; --wash: rgba(138,180,248,.12); }
  }
  body { margin: 0 auto; padding: 3rem 1rem 4rem; max-width: 40rem;
    font: 16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif; }
  h1 { font-size: 1.5rem; margin: 0 0 .5rem; }
  h2 { font-size: .8rem; text-transform: uppercase; letter-spacing: .06em;
    opacity: .55; margin: 2.5rem 0 .25rem; font-weight: 600; }
  p.lead { margin: 0 0 1rem; opacity: .7; font-size: .9rem; }
  p.empty { margin: .5rem 0 0; opacity: .5; font-size: .85rem; }
  ul { list-style: none; margin: 0; padding: 0; }
  li { border-top: 1px solid var(--rule); }
  li:last-child { border-bottom: 1px solid var(--rule); }
  li a { display: flex; align-items: center; gap: .75rem;
    padding: .8rem .5rem .8rem .25rem; text-decoration: none; color: inherit;
    font-variant-numeric: tabular-nums; }
  li a .build { flex: 1; }
  li a .ref { display: block; color: var(--link); text-decoration: underline;
    text-underline-offset: .18em; }
  li a .when { opacity: .55; font-size: .8rem; }
  li a .subject { display: block; font-size: .75rem; opacity: .6; margin-top: .15rem; }
  li a::after { content: "\203A"; color: var(--link); font-size: 1.25em;
    line-height: 1; opacity: .8; }
  li a:hover, li a:focus-visible { background: var(--wash); }
  li a:hover .ref { text-decoration-thickness: 2px; }
  a:focus-visible { outline: 2px solid var(--link); outline-offset: -2px; }
  nav { margin-top: 2.5rem; font-size: .85rem; }
  nav a { color: var(--link); }
</style>
<h1>Archived builds</h1>
<p class="lead">Each entry is the complete set of documents, in all languages, as
they stood at that point. Released versions are kept permanently; builds of the
main branch are kept for the most recent commits only.</p>
HTML

    echo '<h2>Releases</h2>'
    tags=$(emit_entries tags)
    if [[ -n "${tags}" ]]; then
        printf '<ul>\n%s\n</ul>\n' "${tags}"
    else
        echo '<p class="empty">No release has been tagged yet.</p>'
    fi

    echo '<h2>Recent builds of main</h2>'
    commits=$(emit_entries commits)
    if [[ -n "${commits}" ]]; then
        printf '<ul>\n%s\n</ul>\n' "${commits}"
    else
        echo '<p class="empty">No build has been archived yet.</p>'
    fi

    cat <<'HTML'
<nav><a href="./">&#8592; All languages</a></nav>
</html>
HTML
} > "${dir}/archive.html"

echo "wrote ${dir}/archive.html"
