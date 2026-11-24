#!/bin/sh
set -eu

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

[ "$#" -ge 2 ] && [ "$#" -le 3 ] && [ -f "$1" ] ||
    fail "Usage: sh $0 ARCHIVE RELEASE_TAG [MINIMUM_SHUMI_VERSION]"
archive=$1
tag=$2
name=${archive##*/}
case "$name" in
    session-shuffle-*) id=session-shuffle ;;
    todays-focus-*) id=todays-focus ;;
    *) fail "Unknown plugin archive: $name" ;;
esac
case "$name" in
    *-source.tar.gz) kind=source; label=Source ;;
    *-linux-x86_64.tar.gz) kind=linux-x86_64; label='Linux x86_64' ;;
    *) fail "Unsupported plugin archive: $name" ;;
esac
version=${name#"$id-"}
version=${version%"-$kind.tar.gz"}
semver='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
printf '%s\n' "$version" | LC_ALL=C grep -Eq "$semver" ||
    fail "Expected a stable plugin release version: $version"
manifest=$(tar -xOzf "$archive" "$id/plugin.toml") || fail 'Missing plugin manifest.'
header=$(printf '%s\n' "$manifest" | sed '/^[[:space:]]*\[/q')
manifest_id=$(printf '%s\n' "$header" | sed -n 's/^id = "\([^"]*\)"$/\1/p')
[ "$manifest_id" = "$id" ] || fail 'The manifest ID must match the archive name.'
if [ "$kind" != source ]; then
    min=${3:-}
    printf '%s\n' "$min" | LC_ALL=C grep -Eq "$semver" ||
        fail 'Provide the minimum supported Shumi version for a binary archive.'
    api=$(printf '%s\n' "$header" | sed -n 's/^api_version = \([0-9][0-9]*\)$/\1/p')
    printf '%s\n' "$api" | LC_ALL=C grep -Eq '^[1-9][0-9]*$' || fail 'Missing plugin API version.'
fi

site=$(CDPATH= cd "$(dirname "$0")/.." && pwd)
destination="$site/plugins/$id"
mkdir -p "$destination"
staged=$(mktemp "$destination/.release.XXXXXX")
trap 'rm -f "$staged"' EXIT
trap 'exit 1' HUP INT TERM
cp "$archive" "$staged"
chmod 644 "$staged"
if ! ln "$staged" "$destination/$name" 2>/dev/null; then
    cmp -s "$staged" "$destination/$name" || fail "Release already exists with different contents: $name"
fi
python3 "$site/scripts/release-assets.py" record "plugins/$id/$name" "$tag" "$staged"
if [ "$kind" = source ]; then
    printf '<a href="%s/%s" download>%s %s</a>\n' "$id" "$name" "$label" "$version"
else
    if command -v sha256sum >/dev/null 2>&1; then
        checksum=$(sha256sum < "$staged")
    else
        checksum=$(shasum -a 256 < "$staged")
    fi
    printf '<a class="button button-secondary" href="%s/%s" download data-api-version="%s" data-min-shumi-version="%s" data-sha256="%s">%s %s</a>\n' \
        "$id" "$name" "$api" "$min" "${checksum%% *}" "$label" "$version"
fi
