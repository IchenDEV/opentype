#!/usr/bin/env bash
#
# Lightweight CI guardrails for pull-request checks.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
    echo "error: $*" >&2
    exit 1
}

step() {
    echo ""
    echo "==> $*"
}

step "Checking Package.swift"
swift package describe >/dev/null

step "Linting property lists and localized strings"
plutil -lint Resources/Info.plist
plutil -lint Resources/OpenType.entitlements
plutil -lint Sources/Resources/en.lproj/Localizable.strings
plutil -lint Sources/Resources/zh-Hans.lproj/Localizable.strings

step "Checking localization key parity"
en_keys="$(mktemp)"
zh_keys="$(mktemp)"
trap 'rm -f "$en_keys" "$zh_keys"' EXIT

grep -E '^"[^"]+"\s*=' Sources/Resources/en.lproj/Localizable.strings \
    | sed -E 's/^"([^"]+)".*/\1/' \
    | sort >"$en_keys"
grep -E '^"[^"]+"\s*=' Sources/Resources/zh-Hans.lproj/Localizable.strings \
    | sed -E 's/^"([^"]+)".*/\1/' \
    | sort >"$zh_keys"

if ! diff -u "$en_keys" "$zh_keys"; then
    fail "localized string keys differ between en and zh-Hans"
fi

step "Checking required app resources"
test -f Sources/Resources/Sounds/start.caf || fail "missing start sound"
test -f Sources/Resources/Sounds/stop.caf || fail "missing stop sound"
test -s Resources/Info.plist || fail "missing Info.plist"
test -s Resources/OpenType.entitlements || fail "missing entitlements"

step "Checking for conflict markers"
if command -v rg >/dev/null 2>&1; then
    conflict_markers="$(rg -n '^(<<<<<<<|=======|>>>>>>>)' --glob '!Package.resolved' . || true)"
else
    conflict_markers="$(grep -RInE '^(<<<<<<<|=======|>>>>>>>)' \
        --exclude=Package.resolved \
        --exclude-dir=.git \
        --exclude-dir=.build \
        --exclude-dir=.swiftpm \
        . || true)"
fi

if [ -n "$conflict_markers" ]; then
    echo "$conflict_markers"
    fail "found unresolved conflict markers"
fi

step "Checking for broken symlinks"
if find . \
    -path ./.git -prune -o \
    -path ./.build -prune -o \
    -path ./.swiftpm -prune -o \
    -type l ! -exec test -e {} \; -print | grep .; then
    fail "found broken symlinks"
fi

echo ""
echo "Basic CI checks passed."
