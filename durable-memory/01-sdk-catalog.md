# Shared SDK catalogs

The host registers the SDK byte-string and collection catalogs. `Message.header_names` returns an independent SDK StrList snapshot. Its mutable superset edits only that returned collection, never message headers; native Message and Url storage remain separate. Collection handles live for a chunk run, and the stable arena resets between chunks. SDK bounds errors and byte semantics apply unchanged.

`scripts/sync-sdk.sh` vendors the VM and all SDK catalog headers from one commit. `sdk.lock` stores per-file SHA-256 entries; verification checks every vendored header. The schema includes string and collection fragment entries unchanged alongside the proxy domain API.

The Squid feature shim marks native POSIX message/socket structures and statvfs as available, avoiding upstream fallback redefinitions on macOS. Its pinned compatibility memrchr source is compiled where the GNU function is absent. These remain part of the existing Squid source dependency.
