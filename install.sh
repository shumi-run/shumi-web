#!/bin/sh
set -eu

fail() {
    printf 'Shumi: %s\n' "$*" >&2
    exit 1
}

download() {
    curl -fsSL --proto '=https' --proto-redir '=https' --retry 2 --output "$2" "$1"
}

main() {
    case "$(uname -s):$(uname -m)" in
        Linux:x86_64) target=x86_64-unknown-linux-gnu ;;
        Linux:aarch64|Linux:arm64) target=aarch64-unknown-linux-gnu ;;
        Darwin:x86_64) target=x86_64-apple-darwin ;;
        Darwin:arm64) target=aarch64-apple-darwin ;;
        *) fail "Unsupported platform ($(uname -s) $(uname -m))." ;;
    esac

    [ -n "${HOME:-}" ] || fail 'Set HOME before running the installer.'
    [ "$#" -eq 0 ] || fail 'The installer takes no arguments.'

    releases=https://shumi.run/releases
    bin_dir="$HOME/.local/bin"
    data_dir="$HOME/.local/share/shumi-tui"
    launcher="$bin_dir/shumi-tui"
    marker='# Managed by the Shumi installer'
    if [ -e "$launcher" ] || [ -L "$launcher" ]; then
        if [ -L "$launcher" ] || [ ! -f "$launcher" ] || [ "$(sed -n '2p;2q' "$launcher")" != "$marker" ]; then
            fail "An existing command is at $launcher. Move it before installing Shumi."
        fi
    fi

    umask 022
    mkdir -p "$data_dir" "$bin_dir"
    stage=$(mktemp -d "$data_dir/.install.XXXXXX")
    launcher_tmp=
    trap 'rm -rf "$stage"; if [ -n "$launcher_tmp" ]; then rm -f "$launcher_tmp"; fi' EXIT
    trap 'exit 1' HUP INT TERM

    download "$releases/$target.txt" "$stage/release" ||
        fail "Could not download release information for $target. Check the supported platforms at https://shumi.run/#install."
    {
        IFS= read -r version && IFS= read -r expected_checksum
    } < "$stage/release" || fail 'Incomplete release information.'
    printf '%s\n' "$version" | LC_ALL=C grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' ||
        fail 'Invalid release version.'
    case "$expected_checksum" in
        ''|*[!0123456789abcdef]*) fail 'Invalid release checksum.' ;;
    esac
    [ "${#expected_checksum}" -eq 64 ] || fail 'Invalid release checksum.'

    bundle="shumi-tui-$version-$target"
    archive="$stage/$bundle.tar.gz"
    download "$releases/$bundle.tar.gz" "$archive" || fail "Could not download $bundle."
    if command -v sha256sum >/dev/null 2>&1; then
        checksum=$(sha256sum < "$archive")
    else
        checksum=$(shasum -a 256 < "$archive")
    fi
    [ "${checksum%% *}" = "$expected_checksum" ] || fail 'Release checksum mismatch.'

    tar -xzf "$archive" -C "$stage"
    [ -x "$stage/$bundle/shumi-tui" ] && [ -d "$stage/$bundle/plugins" ] ||
        fail 'The archive is missing the Shumi executable or bundled plugins.'
    # Publish the complete bundle in one rename. Another installer may already have placed it.
    installed_bundle="$data_dir/$bundle"
    if [ ! -d "$installed_bundle" ]; then
        mv "$stage/$bundle" "$data_dir/" || [ -d "$installed_bundle" ] ||
            fail "Could not install the bundle in $data_dir."
    fi
    [ -x "$installed_bundle/shumi-tui" ] && [ -d "$installed_bundle/plugins" ] ||
        fail "The installed bundle at $installed_bundle is incomplete."

    # Launch the executable directly so it can locate its sibling plugins on macOS too.
    executable=$(printf '%s\n' "$installed_bundle/shumi-tui" | sed "s/'/'\\\\''/g")
    launcher_tmp=$(mktemp "$bin_dir/.shumi-tui.XXXXXX")
    printf '%s\n' '#!/bin/sh' "$marker" "exec '$executable' \"\$@\"" > "$launcher_tmp"
    chmod 755 "$launcher_tmp"
    mv -f "$launcher_tmp" "$launcher"
    launcher_tmp=

    printf 'Installed Shumi %s.\n' "$version"
    case ":${PATH:-}:" in
        *":$bin_dir:"*) printf 'Run shumi-tui to get started.\n' ;;
        *) printf 'Run %s, or add %s to your PATH.\n' "$launcher" "$bin_dir" ;;
    esac
}

main "$@"
