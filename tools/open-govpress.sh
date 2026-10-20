#!/usr/bin/env bash
#
# Run the open-govpress CLI that renders these .adoc documents to PDF.
#
#   tools/open-govpress.sh render <file.adoc>... -o out.pdf
#
# Not meant to be called directly: the `open-govpress` devenv script is the way
# in, and it supplies the environment below from Nix. The logic lives here
# rather than in devenv.nix so that shellcheck and editorconfig-checker can see
# it -- shell embedded in a Nix string is invisible to both.
#
# Always run under xvfb-run: Electron has no headless mode and the packaged
# binary refuses to render without a display (exit code 5). xvfb-run makes this
# work the same way whether or not the calling shell has a real display, which
# keeps local dev and CI identical.
#
# Downloads and extracts the release tarball on first use rather than at
# `enterShell` time, so entering the shell stays fast when nobody needs to
# render anything, and caches both under open-govpress/ (gitignored) so repeat
# invocations don't re-fetch or re-extract.
#
# Environment (all set by the devenv wrapper):
#   GOVPRESS_VERSION    release version, also the directory name in the tarball
#   GOVPRESS_URL        release asset to download
#   GOVPRESS_SHA256     expected checksum of that asset
#   GOVPRESS_FHS        FHS-env wrapper the dynamically-linked binary needs
#   GOVPRESS_XVFB_RUN   xvfb-run binary
#   GOVPRESS_CURL       curl binary
#   GOVPRESS_SHA256SUM  sha256sum binary

set -euo pipefail

: "${GOVPRESS_VERSION:?GOVPRESS_VERSION is required}"
: "${GOVPRESS_URL:?GOVPRESS_URL is required}"
: "${GOVPRESS_SHA256:?GOVPRESS_SHA256 is required}"
: "${GOVPRESS_FHS:?GOVPRESS_FHS is required}"
: "${GOVPRESS_XVFB_RUN:?GOVPRESS_XVFB_RUN is required}"
: "${GOVPRESS_CURL:?GOVPRESS_CURL is required}"
: "${GOVPRESS_SHA256SUM:?GOVPRESS_SHA256SUM is required}"

here=$(dirname "${BASH_SOURCE[0]}")
here=$(cd "${here}" && pwd)
root=$(cd "${here}/.." && pwd)
cd "${root}"

cache_dir="${root}/open-govpress/.cache"
archive="${cache_dir}/open-govpress-${GOVPRESS_VERSION}-linux-x64.tar.gz"
extract_dir="${root}/open-govpress/.extracted"
bin="${extract_dir}/open-govpress-${GOVPRESS_VERSION}/open-govpress"

if [[ ! -x "${bin}" ]]; then
    mkdir -p "${cache_dir}" "${extract_dir}"

    if [[ ! -f "${archive}" ]]; then
        # Download to .part and rename, so an interrupted download cannot be
        # mistaken for a complete one on the next run.
        "${GOVPRESS_CURL}" -fL --retry 3 -o "${archive}.part" "${GOVPRESS_URL}"
        mv "${archive}.part" "${archive}"
    fi

    echo "${GOVPRESS_SHA256}  ${archive}" | "${GOVPRESS_SHA256SUM}" -c -
    tar xzf "${archive}" -C "${extract_dir}"
fi

exec "${GOVPRESS_FHS}" "${GOVPRESS_XVFB_RUN}" -a "${bin}" --no-sandbox "${@}"
