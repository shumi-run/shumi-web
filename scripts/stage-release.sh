#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[ "$#" -eq 2 ] && [ -f "$1" ] || fail "Usage: sh $0 path/to/shumi-tui-VERSION-TARGET.tar.gz RELEASE_TAG"
archive=$1
tag=$2
name=${archive##*/}
bundle=${name%.tar.gz}
case "$name" in
    shumi-tui-*-x86_64-unknown-linux-gnu.tar.gz) target=x86_64-unknown-linux-gnu ;;
    shumi-tui-*-aarch64-unknown-linux-gnu.tar.gz) target=aarch64-unknown-linux-gnu ;;
    shumi-tui-*-x86_64-apple-darwin.tar.gz) target=x86_64-apple-darwin ;;
    shumi-tui-*-aarch64-apple-darwin.tar.gz) target=aarch64-apple-darwin ;;
    *) fail "Unsupported release archive name: $name" ;;
esac
version=${bundle#shumi-tui-}
version=${version%-$target}
printf '%s\n' "$version" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
    fail "Invalid release version: $version"

site=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
releases="$site/releases"
mkdir -p "$releases"
stage=$(mktemp -d "$releases/.stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT
trap 'exit 1' HUP INT TERM

cp "$archive" "$stage/$name"
tar -xzf "$stage/$name" -C "$stage"
[ -x "$stage/$bundle/shumi-tui" ] && [ -d "$stage/$bundle/plugins" ] ||
    fail 'Expected a Shumi release bundle with its executable and plugins.'

if command -v sha256sum >/dev/null 2>&1; then
    checksum=$(sha256sum < "$stage/$name")
else
    checksum=$(shasum -a 256 < "$stage/$name")
fi
printf '%s\n' "$version" "${checksum%% *}" > "$stage/$target.txt"

if ! ln "$stage/$name" "$releases/$name" 2>/dev/null; then
    cmp -s "$stage/$name" "$releases/$name" || fail "Release already exists or could not be staged: $name"
fi
python3 "$site/scripts/release-assets.py" record "releases/$name" "$tag" "$stage/$name"
mv -f "$stage/$target.txt" "$releases/$target.txt"
printf 'Staged %s for %s.\n' "$version" "$target"
