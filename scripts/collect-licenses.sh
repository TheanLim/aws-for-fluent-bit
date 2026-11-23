#!/bin/bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
# 	http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

# Copies the license files of third-party code built into the image.
#
#   collect-licenses.sh c <fluent-bit source dir> <dest dir> <extra notices dir>
#       Copies Fluent Bit's own license files, and the license files of every
#       directory under <fluent-bit source dir>/lib into <dest dir>/lib/<dir>/.
#       A lib directory with no license file uses <extra notices dir>/<name>,
#       where <name> is the directory name without its version.
#
#   collect-licenses.sh go <plugin .so> <dest dir>
#       Reads the Go modules built into the plugin and copies the license files
#       of each module into <dest dir>/<module path>/.
#
#   collect-licenses.sh notices <licenses dir>
#       Joins all license files under <licenses dir> into <licenses dir>/THIRD-PARTY.
#
# Exits 1 if a component has no license file, so the build fails.

set -euo pipefail

shopt -s nullglob nocaseglob

# copy_license_files <src dir> <dest dir>: top-level license files only.
copy_license_files() {
    local f found=0
    for f in "$1"/licen[cs]e* "$1"/copying* "$1"/copyright* "$1"/notice*; do
        [ -f "$f" ] || continue
        mkdir -p "$2"
        cp "$f" "$2/"
        found=1
    done
    [ "$found" -eq 1 ]
}

# Lib directory name without its version: c-ares-1.34.6 -> c-ares.
lib_name() {
    sed -E 's/-amalgamation.*//; s/-[0-9].*//; s/-[0-9a-f]{7,}$//' <<< "$1"
}

collect_c() {
    local src="$1" dest="$2" extra="$3" missing=0 dir name
    copy_license_files "$src" "$dest"
    for dir in "$src"/lib/*/; do
        dir="$(basename "$dir")"
        name="$(lib_name "$dir")"
        if copy_license_files "$src/lib/$dir" "$dest/lib/$dir"; then
            continue
        elif [ -f "$extra/$name" ]; then
            mkdir -p "$dest/lib/$dir"
            cp "$extra/$name" "$dest/lib/$dir/NOTICE"
        else
            echo "ERROR: no license file in lib/$dir and no $extra/$name" >&2
            missing=$((missing + 1))
        fi
    done
    return $(( missing > 0 ))
}

collect_go() {
    local so="$1" dest="$2" missing=0 module version dir
    while read -r module version; do
        dir="$(go mod download -json "$module@$version" | sed -n 's/^\s*"Dir": "\(.*\)",$/\1/p')"
        if ! copy_license_files "$dir" "$dest/$module"; then
            echo "ERROR: no license file in Go module $module@$version" >&2
            missing=$((missing + 1))
        fi
    done < <(go version -m "$so" | awk '$1 == "dep" {print $2, $3}')
    return $(( missing > 0 ))
}

# Writes <licenses dir>/THIRD-PARTY: every license file under <licenses dir>,
# each under a header that names its component (the file's directory).
collect_notices() {
    local dir="$1" out="$1/THIRD-PARTY" f component files
    shopt -s globstar
    shopt -u nocaseglob
    files=("$dir"/**/*)
    {
        echo "Third-party software in this image and its license files."
        echo "The same files are in the directories next to this file."
        for f in "${files[@]}"; do
            [ -f "$f" ] && [ "$f" != "$out" ] || continue
            component="${f#"$dir"/}"
            component="${component%/*}"
            printf '\n%s\n** %s (%s)\n%s\n\n' "$(printf '=%.0s' {1..80})" "$component" "$(basename "$f")" "$(printf '=%.0s' {1..80})"
            cat "$f"
        done
    } > "$out.tmp"
    mv "$out.tmp" "$out"
}

case "${1:-}" in
    c)       collect_c "$2" "$3" "$4" ;;
    go)      collect_go "$2" "$3" ;;
    notices) collect_notices "$2" ;;
    *)       echo "usage: $0 c <src> <dest> <extra notices dir> | go <plugin .so> <dest> | notices <licenses dir>" >&2; exit 2 ;;
esac
