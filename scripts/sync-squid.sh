#!/usr/bin/env bash
# Download the pinned Squid source tarball and unpack it into third_party/squid.
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOCK="$HERE/squid.lock"
DEST="$HERE/third_party/squid"
URL="$(sed -n 's/^repo=//p' "$LOCK")"
WANT="$(sed -n 's/^sha256=//p' "$LOCK")"

if [ "${1:-}" = "--verify" ]; then
  [ -f "$DEST/COPYING" ] || { echo "third_party/squid missing: run scripts/sync-squid.sh" >&2; exit 1; }
  grep -q "Copyright (C) 1996-2023 The Squid Software Foundation" "$DEST/include/version.h" 2>/dev/null \
    || { echo "third_party/squid does not look like the pinned Squid release" >&2; exit 1; }
  echo "third_party/squid present (sha256 $WANT)"
  exit 0
fi

[ -n "$WANT" ] || { echo "sha256 missing in $LOCK" >&2; exit 1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/lmproxy-squid-XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
echo "fetching $URL"
curl -fL "$URL" -o "$WORK/squid.tar.gz"
HAVE="$(sha256sum "$WORK/squid.tar.gz" | cut -c1-64)"
[ "$HAVE" = "$WANT" ] || { echo "sha256 $HAVE differs from squid.lock $WANT" >&2; exit 1; }
rm -rf "$DEST"
mkdir -p "$DEST"
tar xzf "$WORK/squid.tar.gz" -C "$DEST" --strip-components=1
echo "unpacked Squid into $DEST (sha256 verified)"
