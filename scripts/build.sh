#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AMXX_VERSION="${AMXX_VERSION:-1.9}"
DOCKER_IMAGE="${DOCKER_IMAGE:-debian@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171}"

case "$AMXX_VERSION" in
    1.8|1.8.2)
        AMXX_VERSION="1.8.2"
        AMXX_URL="https://www.amxmodx.org/amxxdrop/1.8/amxmodx-1.8.2-dev-hg34-base.tar.gz"
        AMXX_SHA256="8a8293df0f9cc4ab1f2040b60e7cbd5ac86ee95c0fda2d40b344f12ed18bc5cc"
        ;;
    1.9)
        AMXX_URL="https://www.amxmodx.org/amxxdrop/1.9/amxmodx-1.9.0-git5303-base-linux.tar.gz"
        AMXX_SHA256="1ed6898ced2c1fcf225c288b94effc19917e987b284e42911587738ee3c93699"
        ;;
    1.10)
        AMXX_URL="https://github.com/alliedmodders/amxmodx/releases/download/1.10.0.5479/amxmodx-1.10.0-git5479-base-linux.tar.gz"
        AMXX_SHA256="425b53256dbad0ddaeb7935f771d07d85b6c146ed7d1e72d815221042030602d"
        ;;
    *)
        printf 'Unsupported AMXX_VERSION: %s\n' "$AMXX_VERSION" >&2
        exit 1
        ;;
esac

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

archive_name="${AMXX_URL##*/}"
archive="$ROOT_DIR/.ci/downloads/$AMXX_VERSION/$archive_name"
compiler_root="$ROOT_DIR/.ci/amxx/$AMXX_VERSION/addons/amxmodx/scripting"
mkdir -p "$(dirname "$archive")"

if ! test -f "$archive" || test "$(hash_file "$archive")" != "$AMXX_SHA256"; then
    partial="$archive.part"
    rm -f "$partial"
    curl --fail --location --show-error --silent "$AMXX_URL" --output "$partial"
    test "$(hash_file "$partial")" = "$AMXX_SHA256" || {
        rm -f "$partial"
        printf 'AMX Mod X archive checksum mismatch.\n' >&2
        exit 1
    }
    mv "$partial" "$archive"
fi

if ! test -x "$compiler_root/amxxpc"; then
    rm -rf "$ROOT_DIR/.ci/amxx/$AMXX_VERSION"
    mkdir -p "$ROOT_DIR/.ci/amxx/$AMXX_VERSION"
    tar -xzf "$archive" -C "$ROOT_DIR/.ci/amxx/$AMXX_VERSION"
fi

for include in amxmodx amxmisc cstrike fun hamsandwich; do
    test -f "$compiler_root/include/$include.inc" || {
        printf 'Required compiler include is missing: %s.inc\n' "$include" >&2
        exit 1
    }
done

mkdir -p "$ROOT_DIR/compiled"
for plugin in kgb_player_hub kgb_deathmatch_loadout; do
    output="$ROOT_DIR/compiled/$plugin.amxx"
    rm -f "$output"
    compile_log="$(mktemp)"
    compile_status=0
    docker run --rm --platform linux/386 --network none --read-only \
        --tmpfs /tmp:rw,noexec,nosuid,size=16m \
        --volume "$ROOT_DIR:/work" --volume "$compiler_root:/amxx:ro" \
        --env LD_LIBRARY_PATH=/amxx --workdir /work "$DOCKER_IMAGE" \
        /amxx/amxxpc "src/$plugin.sma" -i/amxx/include "-ocompiled/$plugin.amxx" \
        > "$compile_log" 2>&1 || compile_status=$?
    cat "$compile_log"
    if test "$compile_status" -ne 0 || grep -Eq ' : (fatal )?error [0-9]+:| : warning [0-9]+:|^[1-9][0-9]* Errors?\.$' "$compile_log"; then
        rm -f "$compile_log" "$output"
        exit 1
    fi
    rm -f "$compile_log"
    test -s "$output"
    test "$(LC_ALL=C od -An -tx1 -N4 "$output" | tr -d '[:space:]')" = "58584d41"
    printf '%s  %s\n' "$(hash_file "$output")" "$plugin.amxx" > "$output.sha256"
done
