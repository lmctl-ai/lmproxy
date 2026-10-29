# Squid 7 Embedded Engine Architecture

This document describes how `lmproxy` embeds the complete upstream Squid 7 proxy engine alongside its original URL and HTTP/1.1 message parsing capabilities, enabling forward proxying, transparent interception, and SSL-bump TLS inspection without runtime packaging dependencies.

## 1. Engine Build Pipeline

Squid 7 source is pinned via `squid.lock` and downloaded to `third_party/squid/` via `scripts/sync-squid.sh`. Rather than compiling only isolated parsing files, `scripts/build-squid.sh` builds the entire core engine into convenience static libraries:

1. **Autoconf Configuration:**
   - `--enable-static --disable-shared`: All Squid archives are built statically.
   - `--with-openssl`: Uses static OpenSSL (`OpenSSL::SSL` and `OpenSSL::Crypto`).
   - `--enable-ssl-crtd`: Enables dynamic SSL certificate generation and bump machinery.
   - `--enable-disk-io="Blocking"`: Provides core synchronous disk I/O.
   - Isolation and Dependency Stripping:
     - `--disable-auth`, `--disable-snmp`, `--disable-htcp`, `--disable-wccp`, `--disable-wccpv2`, `--disable-unlinkd`, `--disable-translation`, `--disable-auto-locale`, `--disable-ident-lookups`, `--disable-eui`, `--disable-icap-client`, `--disable-ecap`.
     - `--without-cppunit`, `--without-tdb`, `--without-cap`, `--without-nettle`, `--without-gnutls`, `--without-mit-krb5`, `--without-heimdal-krb5`, `--without-gss`, `--without-ldap`, `--without-sasl`, `--without-systemd`, `--without-netfilter-conntrack`.
     - `--disable-external-acl-helpers`, `--disable-url-rewrite-helpers`, `--disable-security-cert-validators`, `--disable-security-cert-generators`, `--disable-storeid-rewrite-helpers`, `--disable-log-daemon-helpers`.
   - By eliminating external auxiliary daemons and third-party crypto libraries (e.g. Nettle, GnuTLS, Kerberos, libcap), the binary has zero dynamic dependencies other than the host C library (glibc on Linux, libSystem on macOS).

2. **Entry Point Symbol De-confliction (`main` vs `SquidMain`):**
   - Squid's `src/main.cc` defines both `main(argc, argv)` and `SquidMain(argc, argv)`.
   - To prevent duplicate `main` symbols when linking with `lmproxy`'s `cpp/main.cpp`, `src/main.o` is recompiled with:
     ```sh
     CPPFLAGS="-Dmain=squid_main_orig" CXXFLAGS="-O2 -g -Wno-missing-declarations -Wno-error"
     ```
   - This macro-renames Squid's top-level `main` while exporting `SquidMain(argc, argv)`.
   - `src/*.o` files are archived into `libsquid_objects.a`.

3. **Symbol Cleanliness & Link Grouping:**
   - Both `src/debug/debug.cc` (in `libdebug.a`) and `compat/assert.cc` (in `libcompatsquid.a`) define `xassert`.
   - To avoid linker collision, `assert.o` is deleted from `libcompatsquid.a` (`ar d ... assert.o`), ensuring `xassert` resolves cleanly to `libdebug.a`.
   - On Linux, static archives are enclosed in `-Wl,--whole-archive libsquid_objects.a -Wl,--no-whole-archive` and `-Wl,--start-group ... -Wl,--end-group`.
   - On macOS, `-Wl,-force_load,libsquid_objects.a` is used, and the linker links only system frameworks (`CoreFoundation`, `Security`, `libz`, `libresolv`, `libc++`).

## 2. Ephemeral Configuration & Dynamic CA Engine

Squid natively requires a configuration file (`squid.conf`), MIME tables, icon paths, and certificate databases. `lmproxy` automates all of this at runtime:

- **Ephemeral Directory Structure:**
  - `cpp/engine/config.cpp` generates an ephemeral staging directory under `/tmp/lmproxy-XXXXXX`.
  - Generates minimal `mime.conf` and `icons/` directory so Squid startup assertions are satisfied without external files.
- **Dynamic CA & Self-Signed Certificates:**
  - `ensure_ca_certificate()` uses OpenSSL C APIs (`EVP_RSA_gen`, `X509_new`, `X509_sign`) to generate a 2048-bit RSA key and self-signed Root CA (`lmproxy Root CA`) on demand if not provided.
  - Generates combined PEM for Squid's SSL bump directives:
    ```
    http_port <bind>:<port> ssl-bump cert=<cert.pem> generate-host-certificates=on dynamic_cert_mem_cache_size=16MB
    acl step1 at_step SslBump1
    ssl_bump peek step1
    ssl_bump bump all
    ```
- **Transparent Interception:**
  - Generates `http_port <bind>:<port> intercept` (with or without `ssl-bump`).
- **Memory-Only In-Memory Cache:**
  - `cache_mem 32 MB`, `maximum_object_size_in_memory 4 MB`, `cache allow all`.
- **Zero-Friction Daemon Lifecycle:**
  - Configures `shutdown_lifetime 1 seconds` and `pid_filename`.
  - Disables daemon helper lookups: `access_log none`, `logfile_daemon /bin/true`.

## 3. CLI Subcommand Reference

In addition to the original message parsing and DSL execution commands, `lmproxy` provides:

- `lmproxy forward [--port <P>] [--bind <ADDR>] [--ssl-bump] [--ca-cert <CRT>] [--ca-key <KEY>]`
  Runs a standard forward proxy daemon. Default port `3128`, default bind `0.0.0.0`.
- `lmproxy intercept [--port <P>] [--bind <ADDR>] [--ssl-bump] [--ca-cert <CRT>] [--ca-key <KEY>]`
  Runs a transparent interception proxy daemon. Default port `3129`, default bind `0.0.0.0`.
- `lmproxy run --config <SQUID.CONF>`
  Runs the embedded Squid engine directly with an existing custom Squid configuration file.
- Backward-compatible commands:
  - `lmproxy parse-url URL...`
  - `lmproxy parse-request FILE`
  - `lmproxy parse-response FILE`
  - `lmproxy --dsl-schema [--json]`
  - `lmproxy --dsl-signatures`
  - `lmproxy --version`
  - `lmproxy --dsl FILE.dslb...`

## 4. Linkage Invariants (Rule 14)

- **Linux:** Only dynamic glibc is permitted (`libc.so.6`, `libm.so.6`, `ld-linux*.so`). All third-party libraries (Squid, OpenSSL, libstdc++, libgcc) must be statically linked.
- **macOS:** Only system libraries and frameworks (`/usr/lib/*`, `/System/Library/*`) are linked dynamically. OpenSSL and Squid are static.
- Verified in CI and locally via `test.sh` (check 28).
