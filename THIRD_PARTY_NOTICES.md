# Third-Party Notices

## Squid

This repository builds against, and includes verbatim source files from,
**Squid** — a caching proxy for the Web.

- Upstream: https://www.squid-cache.org / https://github.com/squid-cache/squid
- Version: 7.0.0 (squid-7.0.0-20250103-rb56774dd09), pinned in `squid.lock`
- License: **GNU General Public License, version 2 or later (GPLv2+)**
- Copyright (C) 1996-2023 The Squid Software Foundation and contributors
- Full license text: the upstream `COPYING` file, vendored at
  `third_party/squid/COPYING` after running `scripts/sync-squid.sh`

Squid's GPL license differs from the MIT license of the lmproxy-authored
code. The MIT license (see `LICENSE`) applies only to files authored for
lmproxy; Squid source files remain under GPLv2+ as marked in their headers.
Because the compiled lmproxy executable links Squid object code, that
executable is a combined work distributed under GPLv2+.

## lmcode-cpp SDK

`cpp/dslvm.hpp` is vendored from lmcode-cpp (MIT License, Lattice Systems
LLC), pinned by `sdk.lock` and synced by `scripts/sync-sdk.sh`.
