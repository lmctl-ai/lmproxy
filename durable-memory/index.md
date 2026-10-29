# lmproxy durable memory

Technical documentation and operational notes for `lmproxy`.
`lmproxy` embeds Squid 7's URL and HTTP/1.1 message parsing engine as a standalone CLI host for lmscript.
Repository: https://github.com/lmctl-ai/lmproxy.

## Document map

| File | Contents |
| --- | --- |
| [01-sdk-catalog.md](01-sdk-catalog.md) | Shared SDK catalogs, collection handles, Squid compatibility shims |

## Architecture & Build
- Host C++ entry points in `cpp/` embed `dslvm::Registry` (pinned via `sdk.lock` to `lmcode-cpp` `ee1f084`) and Squid 7 parser.
- Build: `cmake -S . -B build -G Ninja && cmake --build build`.
- Test: `./test.sh` runs 26 checks (9-file SDK pin, Squid lock, CLI flags, full and `--without-std` signature parity with `lmscript >= 0.2.420`, URL parsing, request/response parsing, DSL bytecode runs, and dynamic glibc / system library linkage check).

## Adding an example or function

### Adding an example
1. Create `examples/<name>.lms` using `_dsl_ cli="lmproxy" install="github:lmctl-ai/lmproxy@latest"`.
2. Compile and run: `PATH=$PWD/build:$PATH lmscript examples/<name>.lms build/<name>.dslb && ./build/lmproxy --dsl build/<name>.dslb`.
3. Add expected output assertions (`#| <expected>`) in `examples/<name>.lms` for `./test.sh`.
4. Capture output to `docs/images/src/<name>.txt`, run `scripts/render-readme-images.sh`, and update `README.md` gallery.

### Adding a host function/method
1. Declare in `schema/lmproxy.host.json` (CMake copies exact host-only bytes to `schema/lmproxy.dsl.json`; `lmscript >= 0.2.420` supplies std implicitly).
2. Implement in `cpp/` and register via `dslvm::Registry`.
3. Verify `./test.sh` passes and schema signatures match compiler.

## Releases
Releases are built, tested, and published automatically on every push across Linux and macOS (rolling builds to the `dist` branch on `main`, tagged releases on `v*` tags).
