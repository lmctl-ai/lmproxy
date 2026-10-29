#!/usr/bin/env bash
# Build complete static Squid engine convenience libraries for lmproxy.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_DIR="${SOURCE_DIR:-$HERE/third_party/squid}"
BUILD_DIR="${BUILD_DIR:-$HERE/build/squid-build}"
JOBS="${JOBS:-$(nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)}"

# Ensure source exists
if [ ! -f "$SOURCE_DIR/configure" ]; then
  "$HERE/scripts/sync-squid.sh"
fi

SENTINEL="$BUILD_DIR/src/libsquid_objects.a"
if [ -f "$SENTINEL" ] && [ "${FORCE_REBUILD:-0}" != "1" ]; then
  echo "Squid engine already built in $BUILD_DIR"
  exit 0
fi

mkdir -p "$BUILD_DIR"

# Configure Squid with static-only, lean flags (forward/intercept/ssl-bump ready)
if [ ! -f "$BUILD_DIR/Makefile" ]; then
  echo "Configuring Squid engine in $BUILD_DIR..."
  OPENSSL_ARG="--with-openssl"
  if [ -n "${OPENSSL_ROOT_DIR:-}" ]; then
    OPENSSL_ARG="--with-openssl=$OPENSSL_ROOT_DIR"
  elif [ "$(uname -s)" = "Darwin" ]; then
    BREW_OPENSSL="$(brew --prefix openssl@3 2>/dev/null || echo "")"
    if [ -n "$BREW_OPENSSL" ]; then
      OPENSSL_ARG="--with-openssl=$BREW_OPENSSL"
    fi
  fi

  (cd "$BUILD_DIR" && "$SOURCE_DIR/configure" \
    --prefix="$BUILD_DIR/install" \
    $OPENSSL_ARG \
    --enable-static \
    --disable-shared \
    --disable-arch-native \
    --disable-dependency-tracking \
    --disable-auth \
    --disable-snmp \
    --disable-htcp \
    --disable-wccp \
    --disable-wccpv2 \
    --disable-unlinkd \
    --disable-translation \
    --disable-auto-locale \
    --disable-ident-lookups \
    --disable-eui \
    --disable-icap-client \
    --disable-ecap \
    --without-cppunit \
    --without-tdb \
    --without-cap \
    --without-nettle \
    --without-gnutls \
    --without-mit-krb5 \
    --without-heimdal-krb5 \
    --without-gss \
    --without-ldap \
    --without-sasl \
    --without-systemd \
    --without-netfilter-conntrack \
    --disable-external-acl-helpers \
    --disable-url-rewrite-helpers \
    --disable-security-cert-validators \
    --disable-security-cert-generators \
    --disable-storeid-rewrite-helpers \
    --disable-log-daemon-helpers \
    --enable-ssl-crtd \
    --enable-disk-io="Blocking" \
    CXXFLAGS="${CXXFLAGS:- -O2 -g}" \
    CFLAGS="${CFLAGS:- -O2 -g}")
fi

echo "Compiling Squid engine..."
make -C "$BUILD_DIR" -j"$JOBS"

# Recompile main.o with -Dmain=squid_main_orig so it does not collide with lmproxy's main
echo "Preparing Squid main entry without colliding main symbol..."
rm -f "$BUILD_DIR/src/main.o"
make -C "$BUILD_DIR/src" main.o CPPFLAGS="-Dmain=squid_main_orig" CXXFLAGS="${CXXFLAGS:- -O2 -g} -Wno-missing-declarations -Wno-error"

# Archive src/*.o into libsquid_objects.a
echo "Creating libsquid_objects.a from compiled engine objects..."
ar rcs "$BUILD_DIR/src/libsquid_objects.a" "$BUILD_DIR/src/"*.o

# Remove assert.o from libcompatsquid.a so it never collides with libdebug.a's xassert
ar d "$BUILD_DIR/compat/.libs/libcompatsquid.a" assert.o 2>/dev/null || true

echo "Squid engine successfully built at $BUILD_DIR"
