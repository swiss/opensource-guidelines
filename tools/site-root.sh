#!/usr/bin/env bash
#
# Write the language chooser at the root of the published site.
#
#   tools/site-root.sh <dir>
#
# Lists only the language directories that were actually built, so a language
# whose render job failed is absent rather than a dead link.

set -euo pipefail

dir="${1:?usage: site-root.sh <dir>}"

# Endonyms, left untranslated by convention: a reader looking for their own
# language recognises its own name, not its name in someone else's.
label_of() {
    case "${1}" in
        en) echo "English" ;;
        de) echo "Deutsch (Schweiz)" ;;
        fr) echo "Français (Suisse)" ;;
        it) echo "Italiano (Svizzera)" ;;
        rm) echo "Rumantsch (Svizra)" ;;
        *)  echo "${1}" ;;
    esac
}

{
    cat <<'HTML'
<!doctype html>
<html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Open Source Guidelines</title>
<style>
  :root { color-scheme: light dark;
    --link: #0b57d0; --rule: rgba(128,128,128,.3); --wash: rgba(11,87,208,.08); }
  @media (prefers-color-scheme: dark) {
    :root { --link: #8ab4f8; --wash: rgba(138,180,248,.12); }
  }
  body { margin: 0 auto; padding: 3rem 1rem 4rem; max-width: 34rem;
    font: 16px/1.6 system-ui, -apple-system, "Segoe UI", sans-serif; }
  h1 { font-size: 1.5rem; margin: 0 0 .5rem; }
  p.lead { margin: 0 0 2.5rem; opacity: .7; font-size: .9rem; }
  ul { list-style: none; margin: 0; padding: 0; }
  li { border-top: 1px solid var(--rule); }
  li:last-child { border-bottom: 1px solid var(--rule); }
  li a { display: flex; align-items: baseline; gap: .75rem;
    padding: .9rem .5rem .9rem .25rem; text-decoration: none; color: inherit; }
  li a .name { flex: 1; color: var(--link); text-decoration: underline;
    text-underline-offset: .18em; }
  li a .code { opacity: .55; font-size: .8rem; text-transform: uppercase;
    letter-spacing: .04em; }
  /* The chevron says "this row goes somewhere" even before the pointer
    arrives, which the hover tint alone could not. */
  li a::after { content: "\203A"; color: var(--link); font-size: 1.25em;
    line-height: 1; opacity: .8; }
  li a:hover, li a:focus-visible { background: var(--wash); }
  li a:hover .name { text-decoration-thickness: 2px; }
  a:focus-visible { outline: 2px solid var(--link); outline-offset: -2px; }
  footer { margin-top: 2.5rem; font-size: .8rem; }
  footer p { margin: 0 0 .6rem; }
  footer p.note { opacity: .65; }
  footer a { color: var(--link); }
</style>
<h1>Open Source Guidelines</h1>
<p class="lead">Tools for publishing open source software in the Swiss Federal
Administration. Choose a language.</p>
<ul>
HTML

    for lang in en de fr it rm; do
        [[ -d "${dir}/${lang}" ]] || continue
        label=$(label_of "${lang}")
        printf '  <li><a href="%s/"><span class="name">%s</span><span class="code">%s</span></a></li>\n' \
            "${lang}" "${label}" "${lang}"
    done

    cat <<'HTML'
</ul>
<footer>
<p class="note">The German, French, Italian and Romansh versions are unreviewed
translations. The binding versions are published in the official languages by
the Federal Chancellery.</p>
HTML

    # Only on the published site, where site-archive.sh has written the listing.
    # A pull request build has no archive, and a dead link would be worse than
    # no link at all.
    if [[ -f "${dir}/archive.html" ]]; then
        printf '<p><a href="archive.html">Earlier builds and releases &#8594;</a></p>\n'
    fi

    cat <<'HTML'
</footer>
</html>
HTML
} > "${dir}/index.html"

echo "wrote ${dir}/index.html"
