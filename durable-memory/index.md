# lmproxy durable memory

Technical documentation and operational notes for `lmproxy`.
`lmproxy` embeds Squid 7's complete engine (forward proxy, transparent interception, SSL-bump TLS interception, URL and HTTP/1.1 message parsers) as a standalone CLI host and proxy daemon for lmscript.
Repository: https://github.com/lmctl-ai/lmproxy.

## Document map

| File | Contents |
| --- | --- |
| [01-sdk-catalog.md](01-sdk-catalog.md) | Shared SDK catalogs, collection handles, and standard declarations |
| [02-squid-engine-architecture.md](02-squid-engine-architecture.md) | Squid 7 full engine architecture, convenience static libraries, ephemeral runtime, and subcommands |

## Architecture & Build
- Host C++ entry points in `cpp/` embed `dslvm::Registry` (pinned via `sdk.lock` to `lmcode-cpp` `93bddf1`), Squid 7 proxy engine, and static OpenSSL.
- Build: `cmake -S . -B build -G Ninja && cmake --build build`.
- Test: `./test.sh` runs 31 checks (SDK pin, Squid lock, CLI flags, full and `--without-std` signature parity with `lmscript >= 0.2.460`, URL parsing, request/response parsing, lmcode runs, forward proxy routing to upstream, intercept SSL-bump CA generation, certgen embedded helper, live traffic tap/record, route/redirect traffic swapping, HTTPS SSL-bump end-to-end interception and swap, and dynamic glibc / system library linkage check).

See also [03-invocation-envelope.md](03-invocation-envelope.md): run_lmcode, the one-frame envelope, exit codes, dry mode, how tests capture programs.

## Adding an example or function

### Adding an example
1. Create `examples/<name>.lms` using `_lmcode_ cli="lmproxy" install="github:lmctl-ai/lmproxy@latest"`.
2. End it with `r = run_lmcode(program); require(r.ok, json_stringify(r));`, then run it: `PATH=$PWD/build:$PATH lmscript examples/<name>.lms`.
3. Add expected output assertions (`#| <expected>`) in `examples/<name>.lms` for `./test.sh`.
4. Capture output to `docs/images/src/<name>.txt`, run `scripts/render-readme-images.sh`, and update `README.md` gallery.

### Adding a host function/method
1. Declare in `schema/lmproxy.host.json` (CMake copies exact host-only bytes to `schema/lmproxy.dsl.json`; `lmscript >= 0.2.460` supplies std implicitly).
2. Implement in `cpp/` and register via `dslvm::Registry`.
3. Verify `./test.sh` passes and schema signatures match compiler.

## Releases
Releases are built, tested, and published automatically on every push across Linux and macOS (rolling builds to the `dist` branch on `main`, tagged releases on `v*` tags).
