#!/usr/bin/env nix-shell
#!nix-shell -i bash -p curl jq python3 nix-prefetch-git nodejs

set -eou pipefail
shopt -s globstar nullglob

packageDir="$(readlink -f "$(dirname "$0")")"

oldVersion="$(
  nix-instantiate --eval --strict \
    --expr "(import <nixpkgs> {}).callPackage ./package.nix {}" \
    -A "version"
)"
newVersion="$(
  curl -s "https://hub.docker.com/v2/repositories/sharelatex/sharelatex/tags" | \
    jq -r '.results | map(.name | select(. | test("^\\d+\\.\\d+.\\d+$")) | split(".") | map(tonumber)) | max | join(".")'
)"

[ "$oldVersion" == "$newVersion" ] && exit

revision="$(
  curl -s "https://hub.docker.com/v2/repositories/sharelatex/sharelatex/tags/$newVersion/images" | \
    jq -r '.[0].layers[].instruction | match("MONOREPO_REVISION=([0-9a-f]+)").captures[0].string'
)"

sourceDir="$(
  nix-prefetch-git --url "https://github.com/overleaf/overleaf" --rev "$revision" --quiet | \
    jq -r '.path'
)"

rm -rf "$packageDir/lockfiles"

"$packageDir/gen-lockfiles.py" \
  "$sourceDir/package-lock.json" \
  --output "$packageDir/lockfiles"
