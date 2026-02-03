#!/usr/bin/env bash

set -euo pipefail

# package.sh - create a nacos-setup-VERSION.zip from workspace
# Usage: ./package.sh [version]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"

print() { echo "[package] $*"; }

usage() {
    cat <<EOF
Usage: $0 [version]

If version is not provided, the script will try to detect it from:
  1) variable NACOS_SETUP_VERSION in ./nacos-setup.sh
  2) git describe --tags --always
  3) fallback to timestamp

Output: ./dist/nacos-setup-VERSION.zip
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

VERSION="${1:-}"

# Prefer version declared in nacos-setup.sh
file_version=""
if [ -f "$PROJECT_ROOT/nacos-setup.sh" ]; then
    file_version=$(sed -n 's/^NACOS_SETUP_VERSION="\(.*\)"/\1/p' "$PROJECT_ROOT/nacos-setup.sh" || true)
fi

if [ -n "$file_version" ]; then
    if [ -n "$VERSION" ] && [ "$VERSION" != "$file_version" ]; then
        echo "[package] Warning: provided version '$VERSION' differs from NACOS_SETUP_VERSION='$file_version' in nacos-setup.sh; using file version."
    fi
    VERSION="$file_version"
else
    if [ -z "$VERSION" ]; then
        echo "[package] Error: NACOS_SETUP_VERSION not found in nacos-setup.sh and no version argument provided."
        echo "Provide a version: ./package.sh 1.2.3  or define NACOS_SETUP_VERSION in nacos-setup.sh"
        exit 1
    fi
fi

NAME="nacos-setup-$VERSION"
DIST_DIR="$PROJECT_ROOT/dist"
TMP_DIR="/tmp/${NAME}-package-$$"

print "Packaging version: $VERSION"
print "Staging to: $TMP_DIR"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR/$NAME"

# Files/dirs to include - adjust as needed
INCLUDE=("nacos-setup.sh" "lib" "README.md" "LICENSE")

for f in "${INCLUDE[@]}"; do
    if [ -e "$PROJECT_ROOT/$f" ]; then
        cp -a "$PROJECT_ROOT/$f" "$TMP_DIR/$NAME/"
    else
        print "Warning: $f not found, skipping"
    fi
done

# Ensure scripts are executable
if [ -d "$TMP_DIR/$NAME/lib" ]; then
    chmod +x "$TMP_DIR/$NAME/lib"/*.sh || true
fi
if [ -f "$TMP_DIR/$NAME/nacos-setup.sh" ]; then
    chmod +x "$TMP_DIR/$NAME/nacos-setup.sh" || true
fi

mkdir -p "$DIST_DIR"
pushd "$TMP_DIR" >/dev/null
zipfile="$DIST_DIR/${NAME}.zip"
print "Creating zip: $zipfile"
zip -r -q "$zipfile" "$NAME"
popd >/dev/null

print "Packaged: $zipfile"

# simple verify
if unzip -tqq "$zipfile" >/dev/null 2>&1; then
    print "Verification: zip OK"
else
    print "Verification: zip FAILED"
    exit 1
fi

# cleanup
rm -rf "$TMP_DIR"

print "Done"

exit 0
