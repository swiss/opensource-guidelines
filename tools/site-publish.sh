#!/usr/bin/env bash
#
# Overlay a freshly rendered site onto the accumulated published tree.
#
#   tools/site-publish.sh <site-dir> <work-dir>
#
# GitHub Pages deployments are whole-site snapshots: `actions/deploy-pages`
# replaces everything each time and offers no way to read back what is already
# published. Keeping older builds around therefore needs somewhere to remember
# them between runs, and that somewhere is the `site-history` branch -- cloned
# here, overlaid with the build that was just rendered, and pushed back. The
# caller then uploads the whole of <work-dir> as the Pages artifact, so the
# deployment stays a snapshot while its *contents* accumulate.
#
# Where the build lands depends on the ref:
#
#   refs/tags/<tag>   -> tags/<tag>/       kept forever, root untouched
#   refs/heads/main   -> commits/<short>/  pruned to $KEEP_COMMITS, and the root
#
# The root keeps meaning "current head of main", which is what the site has
# always meant. A tag archives itself without disturbing it.
#
# Environment:
#   GITHUB_REPOSITORY  owner/repo, used to build the push URL
#   GITHUB_REF_TYPE    `branch` or `tag`
#   GITHUB_REF_NAME    branch or tag name
#   GITHUB_SHA         commit being published
#   GITHUB_RUN_ID      recorded in build-meta.txt, for tracing a build back
#   GH_TOKEN           token with contents:write
#   KEEP_COMMITS       how many main builds to retain (default 10)
#   SITE_REMOTE        override the push URL (tests point this at a bare repo)
#   SITE_BRANCH        override the accumulator branch (default site-history)
#
# Never run this under `set -x`: the push URL carries the token.

set -euo pipefail

site="${1:?usage: site-publish.sh <site-dir> <work-dir>}"
work="${2:?usage: site-publish.sh <site-dir> <work-dir>}"

here=$(dirname "${BASH_SOURCE[0]}")
here=$(cd "${here}" && pwd)

: "${GITHUB_REF_TYPE:?GITHUB_REF_TYPE is required}"
: "${GITHUB_REF_NAME:?GITHUB_REF_NAME is required}"
: "${GITHUB_SHA:?GITHUB_SHA is required}"

branch="${SITE_BRANCH:-site-history}"
keep="${KEEP_COMMITS:-10}"
run="${GITHUB_RUN_ID:-unknown}"

case "${keep}" in
    ''|*[!0-9]*|0)
        echo "site-publish.sh: KEEP_COMMITS must be a positive integer, got '${keep}'" >&2
        exit 1
        ;;
    *) ;;
esac

[[ -d "${site}" ]] || { echo "site-publish.sh: no such directory: ${site}" >&2; exit 1; }

if [[ -n "${SITE_REMOTE:-}" ]]; then
    remote="${SITE_REMOTE}"
else
    : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
    : "${GH_TOKEN:?GH_TOKEN is required}"
    # The token is interpolated at run time, so the literal here is a URL shape
    # rather than a credential. ripsecrets only honours the pragma on the line
    # it is attached to, hence the trailing comment.
    remote="https://x-access-token:${GH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" # pragma: allowlist secret
fi

# Which slot this build occupies, and whether it also becomes the root.
short="${GITHUB_SHA:0:8}"
case "${GITHUB_REF_TYPE}" in
    tag)
        slot="tags/${GITHUB_REF_NAME}"
        update_root=0
        ;;
    branch)
        [[ "${GITHUB_REF_NAME}" = "main" ]] || {
            echo "site-publish.sh: refusing to publish branch '${GITHUB_REF_NAME}'" >&2; exit 1; }
        slot="commits/${short}"
        update_root=1
        ;;
    *)
        echo "site-publish.sh: unexpected GITHUB_REF_TYPE '${GITHUB_REF_TYPE}'" >&2
        exit 1
        ;;
esac

# Only the files are wanted, never the branch's history -- see the force-push at
# the bottom for why. A missing branch is the normal first run, not an error.
rm -rf "${work}"
if git clone --quiet --depth 1 --branch "${branch}" "${remote}" "${work}" 2>/dev/null; then
    echo "cloned ${branch}"
else
    echo "${branch} does not exist yet, starting an empty tree"
    mkdir -p "${work}"
fi
rm -rf "${work}/.git"

# The root holds the languages and the chooser; clearing them first is what
# makes a document that was deleted from the sources disappear from the site
# rather than linger as an orphaned PDF. `commits/`, `tags/` and `archive.html`
# are deliberately left in place -- they are the accumulated part.
if [[ "${update_root}" = 1 ]]; then
    rm -rf \
        "${work}"/en \
        "${work}"/de \
        "${work}"/fr \
        "${work}"/it \
        "${work}"/rm \
        "${work}"/index.html
    cp -a "${site}"/. "${work}"/
    echo "updated the site root"
fi

rm -rf "${work:?}/${slot}"
mkdir -p "${work}/${slot}"
cp -a "${site}"/. "${work}/${slot}"/
echo "archived the build as ${slot}"

# Taken from the commit rather than from the clock, so re-rendering the same
# commit reproduces the same metadata instead of reshuffling the archive order.
date=$(git log -1 --format=%cI "${GITHUB_SHA}" 2>/dev/null || echo "")
epoch=$(git log -1 --format=%ct "${GITHUB_SHA}" 2>/dev/null || echo "0")
subject=$(git log -1 --format=%s "${GITHUB_SHA}" 2>/dev/null || echo "")

printf '%s\t%s\n' \
    ref     "${GITHUB_REF_NAME}" \
    type    "${GITHUB_REF_TYPE}" \
    sha     "${GITHUB_SHA}" \
    short   "${short}" \
    date    "${date}" \
    epoch   "${epoch}" \
    subject "${subject}" \
    run     "${run}" \
    > "${work}/${slot}/build-meta.txt"

# Prune main builds to the newest $keep. Tags are never pruned: a release needs
# a URL that keeps working. Ordering is by the recorded commit date, since the
# directory names are hashes and sort arbitrarily.
if [[ -d "${work}/commits" ]]; then
    metas=$(find "${work}/commits" -mindepth 2 -maxdepth 2 -name build-meta.txt)

    dated=""
    while IFS= read -r meta; do
        [[ -n "${meta}" ]] || continue
        meta_epoch=$(awk -F'\t' '$1 == "epoch" { print $2; exit }' "${meta}")
        meta_dir=$(dirname "${meta}")
        dated+=$(printf '%s\t%s\n' "${meta_epoch}" "${meta_dir}")$'\n'
    done <<<"${metas}"

    stale=()
    if [[ -n "${dated}" ]]; then
        pruned=$(printf '%s' "${dated}" | sort -rn -t$'\t' -k1,1 | tail -n "+$((keep + 1))")
        while IFS=$'\t' read -r _ stale_dir; do
            [[ -n "${stale_dir}" ]] || continue
            stale+=("${stale_dir}")
        done <<<"${pruned}"
    fi

    for stale_dir in ${stale+"${stale[@]}"}; do
        rm -rf "${stale_dir}"
        pruned_name=$(basename "${stale_dir}")
        echo "pruned ${pruned_name}"
    done
fi

"${here}/site-archive.sh" "${work}"

# Regenerate the chooser so it picks up the archive link. Skipped when the root
# is still empty, which happens if a tag is pushed before main has ever built --
# a chooser listing no languages would be worse than none at all.
for lang in en de fr it rm; do
    if [[ -d "${work}/${lang}" ]]; then
        "${here}/site-root.sh" "${work}"
        break
    fi
done

# One parentless commit, force-pushed. PDFs are re-rendered on every run and so
# are new blobs even when their content is unchanged; keeping history would add
# the full weight of the site to the branch every time, and deleting a pruned
# directory at the tip would reclaim none of it. The branch is derived output,
# so discarding its history costs nothing that cannot be re-rendered.
git -c init.defaultBranch=publish init -q "${work}"
git -C "${work}" add -A
git -C "${work}" \
    -c user.name='github-actions[bot]' \
    -c user.email='41898282+github-actions[bot]@users.noreply.github.com' \
    -c commit.gpgsign=false \
    commit -q -m "Publish ${GITHUB_REF_NAME} (${short})"
git -C "${work}" push -q --force "${remote}" "HEAD:refs/heads/${branch}"
echo "pushed ${slot} to ${branch}"
