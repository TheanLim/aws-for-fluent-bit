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

# Checks that a built image has license files for the code built into it.
#   C libraries: read from the debug info of /fluent-bit/bin/fluent-bit
#                (source paths fluent-bit/lib/<dir>); each needs files in
#                /fluent-bit/licenses/fluent-bit/lib/<dir>/.
#   Go modules:  read from the build info of each plugin .so; each needs
#                /fluent-bit/licenses/<plugin>/<module path>/.
#   Each component also needs a section in /fluent-bit/licenses/THIRD-PARTY.
# Usage: check-image-licenses.sh <image>. Exits 1 if a component has no license files.

set -euo pipefail

image="$1"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cid="$(docker create "$image")"
docker cp "$cid:/fluent-bit" "$work/fluent-bit" > /dev/null
docker rm "$cid" > /dev/null
licenses="$work/fluent-bit/licenses"
missing=0

libs="$(strings -n 8 "$work/fluent-bit/bin/fluent-bit" | grep -oE 'fluent-bit/lib/[^/ ]+' | sed 's#fluent-bit/lib/##' | sort -u || true)"
if [ -z "$libs" ]; then
    echo "ERROR: no library source paths in /fluent-bit/bin/fluent-bit (stripped?), cannot check it" >&2
    exit 1
fi
echo "Libraries built into fluent-bit: $(wc -w <<< "$libs")"
notices="$licenses/THIRD-PARTY"
if [ ! -s "$notices" ]; then
    echo "ERROR: $notices is missing or empty" >&2
    missing=$((missing + 1))
    notices=/dev/null
fi

# in_notices <component>: the joined notices file has a section for it.
in_notices() {
    grep -qF "** $1 (" "$notices"
}

for dir in $libs; do
    if [ -z "$(ls -A "$licenses/fluent-bit/lib/$dir" 2> /dev/null)" ] || ! in_notices "fluent-bit/lib/$dir"; then
        echo "ERROR: no license files for lib/$dir" >&2
        missing=$((missing + 1))
    fi
done

for plugin in cloudwatch firehose kinesis; do
    modules="$(go version -m "$work/fluent-bit/$plugin.so" | awk '$1 == "dep" {print $2}')"
    echo "Go modules built into $plugin.so: $(wc -w <<< "$modules")"
    for module in $modules; do
        if [ ! -d "$licenses/$plugin/$module" ] || ! in_notices "$plugin/$module"; then
            echo "ERROR: no license files for $plugin Go module $module" >&2
            missing=$((missing + 1))
        fi
    done
done

if [ "$missing" -gt 0 ]; then
    echo "ERROR: $missing component(s) in $image have no license files" >&2
    exit 1
fi
echo "All components in $image have license files"
